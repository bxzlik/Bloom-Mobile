/// Тосты Bloom — порт десктопного `GlobalToast` (`#toast` в `search-misc.css`)
/// вместе с полосой обратного отсчёта, круглым значком-видом и кнопкой
/// «Отменить».
///
/// Почему поверх `ScaffoldMessenger`, а не свой оверлей: очередь (тосты не
/// налезают друг на друга, а ждут очереди), смахивание, снятие вместе с
/// экраном и позиционирование НАД нижними барами — всё это у него уже есть.
/// Мы забираем у него только внешний вид: сам `SnackBar` делается прозрачным
/// и без тени, а рисует всё [BloomToastCard].
///
/// Чтобы тост оказался над миниплеером, бары шелла лежат в
/// `Scaffold.bottomNavigationBar` (см. `app/shell.dart`) — плавающий снекбар
/// встаёт ровно над ними.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';

/// Вид тоста: от него зависят значок и цвет полосы (те же четыре, что на ПК).
enum ToastKind { info, success, warn, error }

/// Действие в тосте — «Отменить» десктопного `ToastAction`.
class ToastAction {
  const ToastAction({required this.fn, this.label, this.onExpire});

  /// Что делать по нажатию (обычно — вернуть удалённое).
  final VoidCallback fn;

  /// Текст кнопки; по умолчанию «Отменить».
  final String? label;

  /// Тост погас сам, без нажатия. Сюда вешается то, что нельзя было делать
  /// сразу, потому что отмена ещё возможна (например, удаление файла обложки).
  final VoidCallback? onExpire;
}

/// Сколько тост висит: обычный и с кнопкой — как на ПК (2с и 5с).
const Duration _plain = Duration(milliseconds: 2000);
const Duration _withAction = Duration(milliseconds: 5000);

/// Пока тост въезжает, `ScaffoldMessenger` ещё не завёл свой таймер — на
/// столько же откладывается и полоса, иначе она уходит вперёд отсчёта.
const Duration _enter = Duration(milliseconds: 250);

/// Долгий тост живёт до `close()`, но `SnackBar` требует конечный срок —
/// берём заведомо больший, чем любая загрузка.
const Duration _openEnded = Duration(minutes: 30);

/// Сколько итог висит после `finish()`.
const Duration _finished = Duration(milliseconds: 2400);

/// Мессенджер приложения (ставится в `MaterialApp.scaffoldMessengerKey`).
///
/// Нужен тем, у кого нет `BuildContext`: авто-обновление плейлистов ходит по
/// расписанию из таймера, а сказать о новых треках всё равно надо.
final GlobalKey<ScaffoldMessengerState> bloomMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

extension BloomToasts on ScaffoldMessengerState {
  /// Обычный тост: текст, значок вида и полоса отсчёта.
  ///
  /// С [action] живёт дольше (5с) и показывает кнопку; если её не нажать,
  /// сработает `action.onExpire`.
  void toast(
    String text, {
    ToastKind kind = ToastKind.info,
    ToastAction? action,
  }) {
    final duration = action == null ? _plain : _withAction;
    var used = false;
    late ScaffoldFeatureController<SnackBar, SnackBarClosedReason> entry;

    entry = _show(
      this,
      duration: duration,
      child: BloomToastCard(
        text: text,
        kind: kind,
        barDuration: duration,
        actionLabel: action == null ? null : (action.label ?? 'Отменить'),
        onAction: action == null
            ? null
            : () {
                used = true;
                entry.close();
                action.fn();
              },
      ),
    );

    if (action?.onExpire != null) {
      // Смахнули — это тоже «не нажал отмену»: решение остаётся в силе.
      unawaited(
        entry.closed.then((_) {
          if (!used) action!.onExpire!.call();
        }),
      );
    }
  }

  /// Тост «идёт работа»: значок заменён вертушкой, полосы-таймера нет, и живёт
  /// он до [ToastHandle.finish]. Заменяет пару «Скачиваю…» → «Скачано»: вместо
  /// двух тостов подряд один, который меняется на месте.
  ///
  /// [content] позволяет подменить всю карточку — так тост пакетной загрузки
  /// подписывается на стор и сам обновляет счётчик.
  ToastHandle busyToast(
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
    Widget Function(ValueListenable<ToastView>)? content,
  }) {
    final view = ValueNotifier(
      ToastView(text: text, actionLabel: actionLabel, onAction: onAction),
    );
    final entry = _show(
      this,
      duration: _openEnded,
      child: content == null ? _LiveToast(view: view) : content(view),
    );
    return ToastHandle._(entry, view);
  }
}

/// Тост из `BuildContext` — короткая запись для мест, где мессенджер не нужен
/// отдельно.
void showToast(
  BuildContext context,
  String text, {
  ToastKind kind = ToastKind.info,
  ToastAction? action,
}) => ScaffoldMessenger.of(context).toast(text, kind: kind, action: action);

/// Состояние живого тоста — то, что [ToastHandle] меняет на лету.
class ToastView {
  const ToastView({
    required this.text,
    this.kind = ToastKind.info,
    this.busy = true,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final ToastKind kind;

  /// Вертушка вместо значка.
  final bool busy;

  /// Доля 0..1 для нижней полосы; `null` — полосы прогресса нет.
  final double? progress;

  /// Полоса-таймер на столько; `null` — не отсчитывать.
  final Duration? barDuration;

  final String? actionLabel;
  final VoidCallback? onAction;
}

/// Ручка живого тоста: пока идёт работа — [update], в конце — [finish].
class ToastHandle {
  ToastHandle._(this._entry, this._view) {
    unawaited(_entry.closed.then((_) => _closed = true));
  }

  final ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _entry;
  final ValueNotifier<ToastView> _view;
  bool _closed = false;
  Timer? _timer;

  /// Обновить текст/прогресс, не пересоздавая тост.
  void update(String text, {double? progress}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      progress: progress,
      actionLabel: _view.value.actionLabel,
      onAction: _view.value.onAction,
    );
  }

  /// Подменить содержимое итогом: вертушка уходит, появляется значок вида и
  /// полоса отсчёта, через 2.4с тост гаснет сам.
  void finish(String text, {ToastKind kind = ToastKind.success}) {
    if (_closed) return;
    _view.value = ToastView(
      text: text,
      kind: kind,
      busy: false,
      barDuration: _finished,
    );
    _timer?.cancel();
    _timer = Timer(_finished, close);
  }

  void close() {
    _timer?.cancel();
    if (_closed) return;
    _closed = true;
    _entry.close();
  }
}

/// Общая часть: показать произвольный виджет как снекбар без собственного вида.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> _show(
  ScaffoldMessengerState messenger, {
  required Widget child,
  required Duration duration,
}) => messenger.showSnackBar(
  SnackBar(
    content: child,
    duration: duration,
    // Весь вид — на карточке: у самого снекбара ни фона, ни тени, ни отступов.
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
    dismissDirection: DismissDirection.horizontal,
    shape: const RoundedRectangleBorder(),
  ),
);

class _LiveToast extends StatelessWidget {
  const _LiveToast({required this.view});

  final ValueListenable<ToastView> view;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: view,
    builder: (_, v, _) => BloomToastCard(
      text: v.text,
      kind: v.kind,
      busy: v.busy,
      progress: v.progress,
      barDuration: v.barDuration,
      actionLabel: v.actionLabel,
      onAction: v.onAction,
    ),
  );
}

/// Сама плашка: цвет карточки, рамка 1.5, круглый значок в своём цвете, текст,
/// кнопка и полоса снизу — один в один десктопный `#toast`.
class BloomToastCard extends StatelessWidget {
  const BloomToastCard({
    super.key,
    required this.text,
    this.kind = ToastKind.info,
    this.busy = false,
    this.progress,
    this.barDuration,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final ToastKind kind;
  final bool busy;
  final double? progress;
  final Duration? barDuration;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = kindColor(kind, t);

    return Align(
      // Ширина по содержимому, как inline-flex на ПК: короткому «Трек удалён»
      // незачем растягиваться во весь экран.
      alignment: Alignment.center,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(t.radius),
          border: Border.all(color: t.border, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 40,
              offset: Offset(0, 14),
            ),
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Badge(color: color, kind: kind, busy: busy),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      text,
                      style: bloomText(
                        size: 13,
                        weight: 500,
                        color: t.text,
                        height: 1.35,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onAction,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        // Отступы только ради площади под палец — визуально
                        // кнопка остаётся голым текстом.
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Text(
                          actionLabel!,
                          style: bloomText(
                            size: 13,
                            weight: 700,
                            color: t.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Bar(
                color: color,
                progress: progress,
                duration: barDuration,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Цвета видов — те же значения, что в `search-misc.css`; `info` берёт акцент
/// темы, поэтому считается от токенов.
Color kindColor(ToastKind kind, BloomTokens t) => switch (kind) {
  ToastKind.info => t.accent,
  ToastKind.success => const Color(0xFF2FBF6C),
  ToastKind.warn => const Color(0xFFE0A52E),
  ToastKind.error => const Color(0xFFE0494A),
};

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.kind, required this.busy});

  final Color color;
  final ToastKind kind;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 28,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withValues(alpha: 0.16),
    ),
    child: busy
        ? SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          )
        // У «успеха» голая галочка, а не `checkCircle`: значок и так лежит в
        // круге, круг в круге читался бы мишенью (на ПК то же — `CheckBare`).
        : kind == ToastKind.success
        ? Icon(Icons.check_rounded, size: 19, color: color)
        : Icon(_glyph(kind), size: 18, color: color),
  );

  static IconData _glyph(ToastKind kind) => switch (kind) {
    ToastKind.info => SolarIconsOutline.infoCircle,
    ToastKind.warn => SolarIconsOutline.danger,
    ToastKind.error => SolarIconsOutline.dangerCircle,
    ToastKind.success => Icons.check_rounded,
  };
}

/// Полоса снизу: либо отсчёт (утекает за время жизни тоста), либо прогресс
/// загрузки. Отсчёт запускается с задержкой на въезд — таймер снекбара
/// стартует только по концу анимации появления.
class _Bar extends StatefulWidget {
  const _Bar({required this.color, this.progress, this.duration});

  final Color color;
  final double? progress;
  final Duration? duration;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    // Итог подменил содержимое — отсчёт начинается заново.
    if (widget.duration != old.duration) _run();
  }

  void _run() {
    _delay?.cancel();
    final d = widget.duration;
    if (d == null) return;
    _c
      ..duration = d
      ..value = 0;
    _delay = Timer(_enter, () {
      if (mounted) _c.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    if (progress == null && widget.duration == null) {
      return const SizedBox.shrink();
    }

    final bar = SizedBox(
      height: 2.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    if (progress != null) {
      return TweenAnimationBuilder<double>(
        tween: Tween(end: progress.clamp(0, 1)),
        duration: const Duration(milliseconds: 250),
        builder: (_, v, child) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: v,
          child: child,
        ),
        child: bar,
      );
    }

    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: 1 - _c.value,
        child: child,
      ),
      child: bar,
    );
  }
}
