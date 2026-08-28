/// Онбординг первого запуска — порт десктопного `features/onboarding/*`,
/// одетый в мобильный язык Bloom.
///
/// Мастер из шести шагов: «Язык» → «Привет» → «Профиль» → «Тема» → «Музыка» →
/// «Финал». Отличия от ПК выбрал пользователь: шаг языка встал ПЕРВЫМ (на
/// десктопе язык берётся у системы) и слайд идёт НА ВЕСЬ ЭКРАН, а не карточкой
/// с орбами.
///
/// Хром — наш, а не десктопный: сверху ряд шапки (круглая кнопка «назад» и
/// стеклянная пилюля с сегментами шагов — та же пара, что в [SubPageHeader]),
/// снизу одна широкая кнопка-пилюля, как «Сохранить» в редакторе профиля.
/// Тонкой линейки прогресса нет: её роль взяли сегменты.
/// Листается и пальцем — свайп влево/вправо, чего на ПК нет вовсе.
///
/// Под всем этим живёт мягкое свечение акцента ([_LivingBackground]) — тише
/// десктопных орбов и перекрашивается вместе с темой, которую выбирают на
/// третьем шаге.
///
/// Переходы: во время смены шага уходящий и приходящий слайды живут вместе и
/// разъезжаются по горизонтали, направление задаёт [_dir]. Числа взяты из
/// `onboarding.css` (340/300 мс, сдвиг 36, каскад детей по 50 мс).
///
/// Тема применяется LIVE на тап (как `applyTheme` на ПК), а профиль коммитится
/// одним куском на переходе к «Финалу», чтобы «Назад» не оставлял следов.
/// Картинки — исключение: они сохраняются файлом сразу, иначе их нечем
/// показывать в превью.
library;

import 'dart:async';
import 'dart:math' show cos, pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/bloom_theme.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/settings_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/language_card.dart';
import '../../profile/profile_store.dart';
import '../../profile/ui/image_cropper.dart';
import '../../profile/ui/profile_avatar.dart';
import '../onboarding_store.dart';
import 'onboarding_platforms.dart';

/// Длительность перекрытия слайдов: приходящий заезжает 340, уходящий уезжает
/// 300 — снимаем уходящий по большему из них.
const Duration kSlideEnter = Duration(milliseconds: 340);
const Duration kSlideLeave = Duration(milliseconds: 300);
const Duration kSlideOverlap = Duration(milliseconds: 360);

/// Сколько «Финал» висит перед угасанием и сколько длится само угасание.
const Duration kFinalHold = Duration(milliseconds: 1900);
const Duration kFinalFade = Duration(milliseconds: 420);

/// Сдвиг слайда по горизонтали, px (`translateX(36px)` на ПК).
const double kSlideShift = 36;

/// Скорость броска, с которой свайп считается перелистыванием (px/с).
/// Ниже — палец просто скользнул по экрану, шаг не меняем.
const double kSwipeVelocity = 220;

/// Приветствие и выбор языка живут ОДНИМ экраном (его правка): два подряд
/// почти пустых слайда в начале мастера читались как лишний клик.
const int _kHello = 0;
const int _kProfile = 1;
const int _kTheme = 2;
const int _kMusic = 3;
const int _kFinal = 4;

/// Шаги, которые показывает индикатор: «Финал» в нём не участвует — на нём
/// шапки уже нет.
const int _kSteps = _kFinal;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();

  /// `local:<имя файла>` выбранных картинок — уже лежат на диске, в профиль
  /// уходят на финише.
  String? _avatar;
  String? _banner;

  int _step = _kHello;

  /// Уходящий слайд; `null` — перехода сейчас нет.
  int? _prev;

  /// 1 — вперёд, −1 — назад.
  int _dir = 1;

  /// Экран гаснет: «Финал» отвисел своё.
  bool _exiting = false;

  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(profileProvider).name;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _name.dispose();
    super.dispose();
  }

  void _after(Duration d, VoidCallback fn) =>
      _timers.add(Timer(d, () => mounted ? fn() : null));

  void _go(int next) {
    // Перехода поверх идущего не начинаем — иначе уходящий слайд остался бы
    // висеть: снять его некому, таймер один.
    if (next == _step || _prev != null) return;
    setState(() {
      _dir = next > _step ? 1 : -1;
      _prev = _step;
      _step = next;
    });
    _after(kSlideOverlap, () => setState(() => _prev = null));
  }

  void _back() {
    if (_step > _kHello && _step < _kFinal) _go(_step - 1);
  }

  /// Свайп: влево — дальше, вправо — назад. На «Финале» жест не слушаем, там
  /// экран уже уходит сам.
  void _swipe(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_step == _kFinal || v.abs() < kSwipeVelocity) return;
    // Клавиатуру убираем сами: на шаге профиля свайп из-под неё иначе
    // перелистывает экран с открытым полем.
    FocusScope.of(context).unfocus();
    v < 0 ? _next() : _back();
  }

  // ── Картинки профиля ──────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final picked = await pickAndCropImage(
      context,
      shape: CropShape.circle,
      prefix: 'ava',
    );
    if (picked == null) return;
    final stale = _avatar;
    setState(() => _avatar = picked);
    unawaited(deleteCover(stale));
  }

  Future<void> _pickBanner() async {
    // Аспект — у настоящей полосы на странице профиля: туда картинка и встанет.
    final width = MediaQuery.sizeOf(context).width;
    final picked = await pickAndCropImage(
      context,
      shape: CropShape.rect,
      aspect: _ProfileSlide.bannerHeight / width,
      output: 1440,
      prefix: 'banner',
    );
    if (picked == null) return;
    final stale = _banner;
    setState(() => _banner = picked);
    unawaited(deleteCover(stale));
  }

  void _dropAvatar() {
    final stale = _avatar;
    setState(() => _avatar = null);
    unawaited(deleteCover(stale));
  }

  void _dropBanner() {
    final stale = _banner;
    setState(() => _banner = null);
    unawaited(deleteCover(stale));
  }

  // ── Финиш ─────────────────────────────────────────────────────────────────

  /// Записать профиль, показать «Финал», затем погасить экран.
  ///
  /// Тему повторно не применяем: она уже применилась на тап, и второй заход
  /// сбросил бы включённый тут же авто-акцент — та же причина, что на ПК.
  void _complete() {
    final name = _name.text.trim();
    ref
        .read(profileProvider.notifier)
        .save(
          ref
              .read(profileProvider)
              .copyWith(name: name, avatar: _avatar, banner: _banner),
        );
    _go(_kFinal);
    _after(kFinalHold, () {
      setState(() => _exiting = true);
      _after(kFinalFade, () {
        ref.read(onboardedProvider.notifier).finish();
        context.go('/home');
      });
    });
  }

  void _next() => _step == _kMusic ? _complete() : _go(_step + 1);

  // ── Слайды ────────────────────────────────────────────────────────────────

  Widget _slide(int i) => switch (i) {
    _kHello => const _HelloSlide(),
    _kProfile => _ProfileSlide(
      name: _name,
      avatar: _avatar,
      banner: _banner,
      onPickAvatar: _pickAvatar,
      onPickBanner: _pickBanner,
      onDropAvatar: _dropAvatar,
      onDropBanner: _dropBanner,
      onSubmit: _next,
    ),
    _kTheme => const _ThemeSlide(),
    _kMusic => const _MusicSlide(),
    _ => _FinalSlide(name: _name.text.trim(), avatar: _avatar),
  };

  String _cta(AppLocalizations l) => switch (_step) {
    _kHello => l.onbHelloCta,
    _kMusic => l.onbDone,
    _ => l.onbNext,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final finale = _step == _kFinal;

    return PopScope(
      // Системное «назад» ведёт на шаг назад, а не из приложения. С первого
      // шага и с «Финала» уходить некуда — жест просто ничего не делает.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      // Свой [Scaffold]: страница живёт в корневом навигаторе, а без
      // material-предка `TextField` падает. Он же поднимает подвал над
      // клавиатурой.
      child: Scaffold(
        backgroundColor: t.bg,
        body: AnimatedOpacity(
          opacity: _exiting ? 0 : 1,
          duration: kFinalFade,
          child: Stack(
            children: [
              const Positioned.fill(child: _LivingBackground()),
              SafeArea(
                child: Column(
                  children: [
                    // Шапка и подвал уезжают вместе, а не по отдельности: на
                    // «Финале» экран должен остаться пустым, как на ПК.
                    _Fade(
                      visible: !finale,
                      child: _Header(step: _step, onBack: _back),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onHorizontalDragEnd: _swipe,
                        child: Stack(
                          children: [
                            if (_prev case final prev?)
                              _SlideTransition(
                                // Ключ по номеру шага: без него Flutter
                                // переиспользует состояние анимации и слайды
                                // меняются рывком.
                                key: ValueKey('leave$prev'),
                                leaving: true,
                                dir: _dir,
                                child: _slide(prev),
                              ),
                            _SlideTransition(
                              key: ValueKey('enter$_step'),
                              leaving: false,
                              dir: _dir,
                              child: _slide(_step),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _Fade(
                      visible: !finale,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                        child: _CtaButton(label: _cta(context.l), onTap: _next),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Хром ───────────────────────────────────────────────────────────────────

/// Шапка мастера — та же пара, что у наших подстраниц: круглая кнопка слева и
/// стеклянная пилюля во всю оставшуюся ширину. Внутри пилюли не заголовок, а
/// сегменты шагов: пройденные заливаются акцентом, текущий — тоже, но шире.
class _Header extends StatelessWidget {
  const _Header({required this.step, required this.onBack});

  final int step;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final first = step == _kHello;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Row(
        children: [
          // На первом шаге кнопки нет ВОВСЕ, и пилюля занимает всю ширину:
          // зарезервированное пустое место слева читалось как дырка. Ширина
          // едет анимацией, поэтому на втором шаге пилюля не прыгает, а
          // ужимается.
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: const Cubic(0.22, 1, 0.36, 1),
            width: first ? 0 : kHeaderControl + 10,
            height: kHeaderControl,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                maxWidth: kHeaderControl + 10,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: AnimatedOpacity(
                    opacity: first ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: IgnorePointer(
                      ignoring: first,
                      child: CircleIconButton(
                        icon: SolarIconsOutline.altArrowLeft,
                        onTap: onBack,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GlassBox(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: kHeaderControl,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _Steps(step: step),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Сегменты шагов: пройденные — акцент, будущие — тихая дорожка, текущий
/// вытягивается вдвое (десктопная `.ob-dot.active`, но во всю ширину пилюли).
class _Steps extends StatelessWidget {
  const _Steps({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      children: [
        for (var i = 0; i < _kSteps; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            flex: i == step ? 2 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: const Cubic(0.22, 1, 0.36, 1),
              height: 6,
              decoration: BoxDecoration(
                color: i <= step ? t.accent : t.track,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Широкая кнопка шага — ровно та же, что «Сохранить» в редакторе профиля:
/// высота 56 и полное скругление.
class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      height: 56,
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(shape: const StadiumBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Подпись меняется на месте: «Далее» → «Готово» без прыжка ряда.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                label,
                key: ValueKey(label),
                style: bloomText(size: 15, weight: 700, color: t.accentText),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              SolarIconsOutline.altArrowRight,
              size: 18,
              color: t.accentText,
            ),
          ],
        ),
      ),
    );
  }
}

/// Появление и уход хрома. `Visibility` тут не годится: подвал должен таять, а
/// не исчезать кадром.
class _Fade extends StatelessWidget {
  const _Fade({required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: visible ? 1 : 0,
    duration: const Duration(milliseconds: 260),
    child: IgnorePointer(ignoring: !visible, child: child),
  );
}

/// Живой фон: два мягких пятна, медленно дрейфующих по противоположным углам —
/// порт десктопных орбов (`.ob-orb`, там 16% и блюр 90).
///
/// Цвет пятна — не голый акцент: на тёмных темах с белым акцентом он даёт
/// серую заливку, а на светлой теме и на Nord почти сливается с фоном, и по
/// краям не видно НИЧЕГО. Поэтому светлота пятна отодвигается от светлоты фона
/// на фиксированный зазор ([_gap]), а насыщенность подтягивается вверх —
/// эффект читается одинаково во всех темах, оставаясь цветом темы.
///
/// Рисуем художником, а не двумя `BackdropFilter`: размытая заливка на весь
/// экран стоила бы двух `saveLayer` на кадр, а `MaskFilter` размывает сам
/// круг.
class _LivingBackground extends ConsumerStatefulWidget {
  const _LivingBackground();

  @override
  ConsumerState<_LivingBackground> createState() => _LivingBackgroundState();
}

class _LivingBackgroundState extends ConsumerState<_LivingBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _BlobsPainter(
            phase: _c.value,
            first: blobColor(t.accent, t.bg, t.isLight),
            second: blobColor(t.accent2, t.bg, t.isLight),
          ),
        ),
      ),
    );
  }
}

/// Насколько светлота пятна обязана отличаться от светлоты фона.
const double _gap = 0.3;

/// Цвет пятна для темы: тот же тон, но заведомо отличимый от фона.
///
/// На светлых темах пятно уходит ВНИЗ по светлоте (тень), на тёмных — вверх
/// (свет): иначе на Light дымка светлее фона просто не существует, а на Nord
/// голубой акцент по светлоте почти равен серо-синему фону.
@visibleForTesting
Color blobColor(Color accent, Color bg, bool isLight) {
  final hsl = HSLColor.fromColor(accent);
  final bgL = HSLColor.fromColor(bg).lightness;
  final target = isLight ? bgL - _gap : bgL + _gap;
  final lightness = isLight
      ? (hsl.lightness < target ? hsl.lightness : target)
      : (hsl.lightness > target ? hsl.lightness : target);
  // Ахроматичный акцент (белый в тёмных темах) так и остаётся ахроматичным:
  // подкрашивать пятно тоном, которого в теме нет, нельзя.
  final saturation = hsl.saturation < 0.05
      ? hsl.saturation
      : (hsl.saturation < 0.45 ? 0.45 : hsl.saturation);
  return hsl
      .withLightness(lightness.clamp(0.0, 1.0))
      .withSaturation(saturation)
      .toColor();
}

class _BlobsPainter extends CustomPainter {
  const _BlobsPainter({
    required this.phase,
    required this.first,
    required this.second,
  });

  final double phase;
  final Color first;
  final Color second;

  @override
  void paint(Canvas canvas, Size size) {
    // Пятно шире экрана: видно только его край, поэтому свечение читается
    // подсветкой угла, а не кругом посреди страницы.
    final r = size.width * 0.62;
    void blob(Color color, Offset center, double drift) {
      canvas.drawCircle(
        center +
            Offset(cos(2 * pi * drift) * 26, sin(2 * pi * drift) * 34) *
                (size.height / 800),
        r,
        Paint()
          // Плотность та же, что была изначально: её он менять не просил,
          // за видимость в слабых темах отвечает [blobColor].
          ..color = color.withValues(alpha: 0.12)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70),
      );
    }

    blob(first, Offset(-r * 0.35, -r * 0.2), phase);
    blob(
      second,
      Offset(size.width + r * 0.3, size.height + r * 0.1),
      1 - phase,
    );
  }

  @override
  bool shouldRepaint(_BlobsPainter old) =>
      old.phase != phase || old.first != first || old.second != second;
}

/// Заезд и отъезд слайда: сдвиг по горизонтали + прозрачность. Кривые у входа
/// и выхода разные — те же, что в `onboarding.css`.
class _SlideTransition extends StatefulWidget {
  const _SlideTransition({
    super.key,
    required this.leaving,
    required this.dir,
    required this.child,
  });

  final bool leaving;
  final int dir;
  final Widget child;

  @override
  State<_SlideTransition> createState() => _SlideTransitionState();
}

class _SlideTransitionState extends State<_SlideTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.leaving ? kSlideLeave : kSlideEnter,
  )..forward();

  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: widget.leaving
        ? const Cubic(0.4, 0, 1, 1)
        : const Cubic(0.22, 1, 0.36, 1),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      // Дерево слайда собирается ОДИН раз и переносится в builder: перестраивать
      // его на каждый кадр анимации незачем.
      child: widget.leaving ? IgnorePointer(child: widget.child) : widget.child,
      builder: (context, child) {
        final v = _a.value;
        final dx = widget.leaving
            ? -kSlideShift * widget.dir * v
            : kSlideShift * widget.dir * (1 - v);
        return Opacity(
          opacity: widget.leaving ? 1 - v : v,
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

/// Тело слайда, при нехватке места прокручивается.
///
/// Слайды-обложки («Язык», «Привет», «Финал») ставят содержимое по центру
/// экрана, шаги-формы — СВЕРХУ, сразу под шапкой: на телефоне центрированный
/// заголовок формы висел посреди пустого экрана, а список под ним упирался в
/// кнопку.
///
/// Прямые дети проявляются каскадом — по 50 мс друг за другом, как
/// `.ob-body > *:nth-child(n)` на ПК.
class _Body extends StatelessWidget {
  const _Body({
    required this.children,
    this.centered = false,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
  });

  final List<Widget> children;

  /// Содержимое по центру и текст по центру — слайды «Привет» и «Финал».
  final bool centered;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: padding,
        // Свайп обязан ловиться и на пустом месте слайда, а `ListView` без
        // содержимого под пальцем жест не отдаёт.
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.maxHeight - padding.vertical,
          ),
          child: Column(
            mainAxisAlignment: centered
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++)
                _Rise(index: i, child: children[i]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Проявление ребёнка каскадом: подъём на 14px с задержкой по порядку.
class _Rise extends StatefulWidget {
  const _Rise({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  static const int _riseMs = 440;
  static const int _stepMs = 50;

  /// Задержек больше шести на ПК нет (`nth-child(6)`) — дальше все едут вместе.
  late final int _delayMs = _stepMs * (widget.index.clamp(0, 5) + 1);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _riseMs + _delayMs),
  )..forward();

  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Interval(
      _delayMs / (_riseMs + _delayMs),
      1,
      curve: const Cubic(0.22, 1, 0.36, 1),
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - _a.value)),
          child: child,
        ),
      ),
    );
  }
}

/// Заголовок и подпись слайда. Крупнее десктопных 21/13: на телефоне заголовок
/// — единственный ориентир, а шапки с названием экрана у мастера нет.
class _Title extends StatelessWidget {
  const _Title(this.text, {this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: bloomText(
        size: 26,
        weight: 800,
        color: context.bloom.text,
        height: 1.15,
        letterSpacing: -0.6,
      ),
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text, {this.centered = false});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: centered ? 0 : 24),
    child: Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: bloomText(
        size: 14,
        weight: 500,
        color: context.bloom.text2,
        height: 1.5,
      ),
    ),
  );
}

/// Капсовая подпись группы — та же, что над группами настроек.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 10),
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

// ─── Слайд «Привет» с выбором языка ─────────────────────────────────────────

/// Знак, вордмарк, слоган и сразу выбор языка.
///
/// На ПК отдельного языкового шага нет вовсе (там язык системный), а у нас он
/// сперва стоял своим слайдом — пользователь свёл их в один: два почти пустых
/// экрана подряд в начале мастера читались как лишний клик.
///
/// Тап по карточке ТОЛЬКО применяет язык, дальше ведёт «Поехали» в подвале:
/// на общем слайде уход по выбору языка утаскивал бы человека с приветствия,
/// которое он ещё не дочитал.
class _HelloSlide extends ConsumerWidget {
  const _HelloSlide();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return _Body(
      centered: true,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 22),
          child: _PulsingMark(),
        ),
        Text(
          'Bloom',
          style: bloomText(
            size: 42,
            weight: 900,
            color: t.text,
            letterSpacing: -1.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.l.onbTagline,
          style: bloomText(size: 14, weight: 500, color: t.muted),
        ),
        const SizedBox(height: 18),
        _Sub(context.l.onbHelloSub, centered: true),
        const SizedBox(height: 30),
        Row(
          children: [
            for (final locale in kLocales) ...[
              if (locale != kLocales.first) const SizedBox(width: 12),
              Expanded(
                child: LanguageCard(
                  locale: locale,
                  // Пока язык не выбран руками, активна та карточка, на которой
                  // приложение сейчас говорит, — как в «Интерфейсе».
                  active:
                      (settings.locale ?? Localizations.localeOf(context))
                          .languageCode ==
                      locale.languageCode,
                  onTap: () => controller.setLocale(locale),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Две расходящиеся волны со сдвигом фазы — «дыхание» логотипа (`.ob-mark`).
///
/// Кольца рисуются одним художником по фазе одного контроллера: два
/// независимых, как две CSS-анимации с delay, разошлись бы после первой же
/// паузы кадров.
class _PulsingMark extends StatefulWidget {
  const _PulsingMark();

  @override
  State<_PulsingMark> createState() => _PulsingMarkState();
}

class _PulsingMarkState extends State<_PulsingMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              size: const Size.square(132),
              painter: _PulsePainter(phase: _c.value, color: t.accent),
            ),
          ),
          // Голый знак: ни свечения, ни серой подложки под ним (его правка) —
          // остались только кольца вокруг.
          BloomMark(size: 64),
        ],
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  const _PulsePainter({required this.phase, required this.color});

  final double phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // Кольца стартуют от края знака, а не от края холста: между свечением и
    // первой волной должен быть виден зазор.
    final base = size.width * 0.39;
    for (final shift in const [0.0, 0.5]) {
      final v = (phase + shift) % 1;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        // scale 1 → 1.5, opacity .5 → 0 — те же ключевые кадры, что у `obPulse`.
        ..color = color.withValues(alpha: 0.45 * (1 - v));
      canvas.drawCircle(center, base * (1 + 0.5 * v), paint);
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.phase != phase || old.color != color;
}

// ─── Слайд «Профиль» ────────────────────────────────────────────────────────

/// Обложка во всю ширину, аватар на её нижней кромке и поле ника.
///
/// Размеры — как на настоящей странице профиля (полоса 168, аватар 120), чтобы
/// первый экран не расходился с тем, что человек увидит потом. Наведения на
/// телефоне нет, поэтому десктопные кнопки «Изменить/Удалить» поверх обложки
/// заменены круглыми стеклянными: тап по самой картинке открывает галерею.
class _ProfileSlide extends ConsumerWidget {
  const _ProfileSlide({
    required this.name,
    required this.avatar,
    required this.banner,
    required this.onPickAvatar,
    required this.onPickBanner,
    required this.onDropAvatar,
    required this.onDropBanner,
    required this.onSubmit,
  });

  final TextEditingController name;
  final String? avatar;
  final String? banner;
  final VoidCallback onPickAvatar;
  final VoidCallback onPickBanner;
  final VoidCallback onDropAvatar;
  final VoidCallback onDropBanner;
  final VoidCallback onSubmit;

  /// Те же числа, что на странице профиля.
  static const double bannerHeight = 168;
  static const double _avatarSize = 120;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    // Пластинка-заглушка на месте аватара — та же, что потом на странице
    // профиля: свой цвет диска пользователь мог выбрать и раньше (повтор
    // онбординга), терять его незачем.
    final profile = ref.watch(profileProvider).copyWith(avatar: avatar);
    final image = coverImage(banner);

    return _Body(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      children: [
        // Обложка и аватар — ОДНОЙ карточкой со всеми скруглёнными углами, а
        // не полосой во всю ширину: обрезанная по краям экрана полоса посреди
        // мастера читалась обрубком страницы профиля.
        SizedBox(
          height: bannerHeight + _avatarSize / 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: onPickBanner,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(t.radius * 1.4),
                  child: SizedBox(
                    height: bannerHeight,
                    width: double.infinity,
                    child: image == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [t.pill, t.coverEmpty],
                              ),
                            ),
                          )
                        : Image(image: image, fit: BoxFit.cover),
                  ),
                ),
              ),
              // Кнопки поверх картинки — стеклянные: под ними чужой снимок, а
              // не поверхность темы. Пустая обложка вместо них показывает
              // пилюлю-приглашение: бледная подпись читалась как «тут ничего
              // нет», а не как «нажми».
              Positioned(
                top: 14,
                left: 14,
                right: 14,
                child: banner == null
                    ? Center(
                        child: GestureDetector(
                          onTap: onPickBanner,
                          child: GlassSurface(
                            shape: BorderRadius.circular(999),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                11,
                                18,
                                11,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    SolarIconsOutline.gallery,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.l.onbAddCover,
                                    style: bloomText(
                                      size: 13,
                                      weight: 600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GlassIconButton(
                            icon: SolarIconsOutline.gallery,
                            size: 40,
                            iconSize: 18,
                            onTap: onPickBanner,
                          ),
                          const SizedBox(width: 8),
                          GlassIconButton(
                            icon: SolarIconsOutline.trashBinMinimalistic,
                            size: 40,
                            iconSize: 18,
                            onTap: onDropBanner,
                          ),
                        ],
                      ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onTap: onPickAvatar,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // Кромка цветом фона: аватар лежит на границе
                            // обложки, и без неё картинки склеиваются.
                            border: Border.all(color: t.bg, width: 4),
                          ),
                          child: ProfileAvatar(
                            profile: profile,
                            size: _avatarSize,
                          ),
                        ),
                      ),
                      // Значок «сменить» на кромке аватара — как в макете
                      // редактора: без него не понять, что круг нажимается.
                      Positioned(
                        right: -2,
                        bottom: 4,
                        child: GestureDetector(
                          onTap: avatar == null ? onPickAvatar : onDropAvatar,
                          child: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: avatar == null ? t.accent : t.sysFavIco,
                              shape: BoxShape.circle,
                              border: Border.all(color: t.bg, width: 3),
                            ),
                            child: Icon(
                              avatar == null
                                  ? SolarIconsOutline.camera
                                  : SolarIconsOutline.closeCircle,
                              size: 15,
                              color: avatar == null
                                  ? t.accentText
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Column(
            children: [
              _Title(context.l.onbProfileTitle, centered: true),
              _Sub(context.l.onbProfileSub, centered: true),
              const SizedBox(height: 22),
              _NameField(controller: name, onSubmit: onSubmit),
            ],
          ),
        ),
      ],
    );
  }
}

/// Поле ника — тот же вид, что у полей редактора профиля: капсовая подпись,
/// стеклянная плашка и счётчик символов внутри неё.
class _NameField extends StatelessWidget {
  const _NameField({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  static const int _limit = 32;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupLabel(context.l.profileNickname),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => GlassBox(
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 16, 15),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      textInputAction: TextInputAction.done,
                      cursorColor: t.accent,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(_limit),
                      ],
                      style: theme.titleMedium,
                      onSubmitted: (_) => onSubmit(),
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: context.l.profileNicknameHint,
                        hintStyle: theme.titleMedium?.copyWith(color: t.muted),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${value.text.characters.length}/$_limit',
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Слайд «Тема» ───────────────────────────────────────────────────────────

/// Сетка встроенных пресетов и тумблер авто-акцента. Тап применяет тему сразу —
/// перекрашивается весь экран вместе со свечением фона, это и есть превью.
class _ThemeSlide extends ConsumerWidget {
  const _ThemeSlide();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context).textTheme;

    return _Body(
      children: [
        _Title(context.l.onbThemeTitle),
        _Sub(context.l.onbThemeSub),
        // Три столбца — как `.ob-theme-grid`: шесть встроенных пресетов встают
        // ровно в два ряда. Свои темы сюда не попадают: на первом запуске их
        // нет, а список ради повтора онбординга раздувать незачем.
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.82,
          children: [
            for (final preset in kThemePresets)
              _ThemeCard(
                preset: preset,
                active: preset.id == settings.themeId,
                onTap: () => controller.setTheme(preset.id),
              ),
          ],
        ),
        const SizedBox(height: 22),
        GlassBox(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.l.apAutoAccent, style: theme.titleMedium),
                      const SizedBox(height: 3),
                      Text(context.l.apAutoAccentSub, style: theme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                BloomSwitch(
                  value: settings.autoAccent,
                  onChanged: controller.setAutoAccent,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(SolarIconsOutline.palette, size: 14, color: t.muted),
              const SizedBox(width: 6),
              Text(context.l.onbThemeHint, style: theme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

/// Превью темы — МАКЕТ САМОГО ПРИЛОЖЕНИЯ в её цветах: шапка, пара строк списка
/// и миниплеер с круглой кнопкой акцентом. Абстрактные полоски, которые тут
/// стояли сперва (порт `.ob-tc-bar` с ПК), на телефоне читались как «три
/// столбика непонятно чего»; по маленькому экрану сразу видно, во что тема
/// покрасит настоящие плашки.
///
/// У выбранной — кольцо акцентом и галочка, как в шторке выбора темы.
/// Подпись — ПОД превью, на фоне экрана: внутри цветного прямоугольника она
/// пропадала бы на светлых темах (та же причина, что на ПК).
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.active,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final preview = preset.tokens();
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: preview.bg,
                borderRadius: BorderRadius.circular(t.radius),
                border: Border.all(
                  color: active ? preview.accent : preview.border,
                  width: active ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ThemeGlyph(preview)),
                  ),
                  if (active)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Icon(
                        SolarIconsBold.checkCircle,
                        size: 16,
                        color: preview.accent,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            preset.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: bloomText(
              size: 12,
              weight: active ? 700 : 600,
              color: active ? t.text : t.text2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Мини-экран Bloom в цветах темы: шапка-пилюля, две строки списка и миниплеер
/// с круглой кнопкой акцентом. Рисуем в сетке 100×130 и масштабируем разом —
/// тот же приём, что у значков вида таб-бара в «Интерфейсе».
class _ThemeGlyph extends CustomPainter {
  const _ThemeGlyph(this.preview);

  final BloomTokens preview;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 130);
    final paint = Paint()..color = preview.pill;

    void bar(double l, double top, double r, double bottom, double radius) =>
        canvas.drawRRect(
          RRect.fromLTRBR(l, top, r, bottom, Radius.circular(radius)),
          paint,
        );

    // Шапка занимает половину ширины: во второй половине у выбранной карточки
    // стоит галочка, и полная пилюля лезла бы под неё.
    bar(0, 0, 52, 13, 6.5);
    bar(0, 26, 100, 37, 3.5);
    bar(0, 43, 76, 54, 3.5);

    // Миниплеер: пилюля, кружок обложки и две строчки подписи.
    bar(0, 96, 100, 130, 11);
    paint.color = preview.accent;
    canvas.drawCircle(const Offset(17, 113), 9, paint);
    paint.color = preview.text.withValues(alpha: 0.75);
    bar(32, 106, 74, 111, 2.5);
    paint.color = preview.text.withValues(alpha: 0.35);
    bar(32, 115, 58, 120, 2.5);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThemeGlyph old) =>
      old.preview.bg != preview.bg || old.preview.accent != preview.accent;
}

// ─── Слайд «Музыка» ─────────────────────────────────────────────────────────

/// От десктопного слайда «Подключи музыку» осталась половина: локальных папок
/// на телефоне нет, поэтому здесь только аккордеон площадок.
class _MusicSlide extends StatelessWidget {
  const _MusicSlide();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return _Body(
      children: [
        _Title(context.l.onbMusicTitle),
        _Sub(context.l.onbMusicSub),
        _GroupLabel(context.l.onbMusicPlatforms),
        const OnboardingPlatforms(),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text(
            context.l.onbMusicSkip,
            textAlign: TextAlign.center,
            style: theme.bodySmall,
          ),
        ),
      ],
    );
  }
}

// ─── Слайд «Финал» ──────────────────────────────────────────────────────────

class _FinalSlide extends ConsumerWidget {
  const _FinalSlide({required this.name, required this.avatar});

  final String name;
  final String? avatar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final profile = ref.watch(profileProvider);
    final shown = name.isEmpty ? profile.displayName(context.l) : name;

    return _Body(
      centered: true,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 26),
          // Ни свечения, ни обводки: он попросил убрать их у знака на первом
          // экране — на «Финале» такой же ореол смотрелся бы разнобоем.
          child: ProfileAvatar(
            profile: profile.copyWith(avatar: avatar),
            size: 128,
          ),
        ),
        Text(
          context.l.onbWelcome(shown),
          textAlign: TextAlign.center,
          style: bloomText(
            size: 28,
            weight: 800,
            color: t.text,
            height: 1.15,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              context.l.onbWelcomeSub,
              style: bloomText(size: 14, weight: 500, color: t.text2),
            ),
            const SizedBox(width: 7),
            Icon(SolarIconsOutline.musicNote, size: 15, color: t.text2),
          ],
        ),
      ],
    );
  }
}
