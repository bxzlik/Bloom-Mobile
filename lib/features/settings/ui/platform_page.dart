/// Каркас страницы интеграции в настройках: крупный знак посреди экрана,
/// содержимое под ним и действия, прибитые к низу. Одинаков у площадок и у
/// сервисов вроде Last.fm — отсюда [BrandMark] вместо `MusicSource`.
///
/// Раскладка взята с референса: шапки подстраницы тут нет вовсе — логотип и
/// служит заголовком, а «Назад» стоит последней кнопкой внизу. Вид — свой:
/// плашки и кнопки те же `GlassBox` с радиусом темы, что и на остальных
/// страницах настроек.
///
/// Страница живёт в двух состояниях: свёрнутом (только знак и кнопки) и
/// раскрытом (под знаком появляется [body] — форма или карточки). Знак при
/// раскрытии уменьшается, чтобы форма не уезжала за нижние кнопки.
///
/// Здесь же — шторка с инструкцией ([showPlatformGuide]): десктопные гайды из
/// попапа «?» на телефоне живут в ней.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/platform_logo.dart';

/// Зелёный «всё в порядке» — один на все страницы площадок.
const Color kPlatformOk = Color(0xFF1DB954);

/// Длительность и кривая раскрытия — те же, что у аккордеона площадок в
/// онбординге: страница и онбординг показывают одни и те же формы.
const Duration _kExpand = Duration(milliseconds: 280);
const Curve _kExpandCurve = Cubic(0.4, 0, 0.2, 1);

class PlatformPage extends StatelessWidget {
  const PlatformPage({
    super.key,
    required this.mark,
    required this.onBack,
    this.status,
    this.statusColor,
    this.body,
    this.actions = const [],
  });

  /// Чей это раздел: площадка или сервис-интеграция (Last.fm).
  final BrandMark mark;
  final VoidCallback onBack;

  /// Строка под знаком: подключено / не подключено / чем настроено.
  final String? status;
  final Color? statusColor;

  /// Раскрытое содержимое. `null` — страница свёрнута, знак стоит по центру.
  final Widget? body;

  /// Главные действия. «Назад» дописывается сам последней кнопкой.
  final List<Widget> actions;

  /// Сторона квадрата под знаком: в покое и в раскрытом виде.
  static const double _logoFull = 112;
  static const double _logoCompact = 84;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final open = body != null;

    return SafeArea(
      // Нижний вырез оставляем самому низу: над ним ещё плавают бары каркаса,
      // и кнопки считают отступ от них ([bottomBarsInset]).
      bottom: false,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: ConstrainedBox(
                  // Пока содержимое короче экрана, знак стоит по центру
                  // свободного места; длинная форма просто начинает листаться.
                  constraints: BoxConstraints(minHeight: box.maxHeight - 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: open ? _logoCompact : _logoFull),
                        duration: _kExpand,
                        curve: _kExpandCurve,
                        builder: (_, size, _) => mark.logo(size: size),
                      ),
                      if (status case final text?) ...[
                        const SizedBox(height: 18),
                        Text(
                          text,
                          textAlign: TextAlign.center,
                          style: theme.bodySmall?.copyWith(
                            color: statusColor ?? t.muted,
                          ),
                        ),
                      ],
                      // Рост высоты, а не появление рывком: знак над формой
                      // едет вверх вместе с ней.
                      AnimatedSize(
                        duration: _kExpand,
                        curve: _kExpandCurve,
                        alignment: Alignment.topCenter,
                        child: body == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: body,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              14 + bottomBarsInset(context),
            ),
            child: Column(
              children: [
                for (final action in actions) ...[
                  action,
                  const SizedBox(height: 10),
                ],
                PlatformButton(
                  label: context.l.commonBack,
                  muted: true,
                  onTap: onBack,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка страницы площадки: во всю ширину, со скруглением темы.
///
/// [muted] — второстепенная («Назад»): без заливки, одной рамкой, текст
/// приглушён. Главная кнопка красится не акцентом, а обычной плашкой `pill`:
/// на этих страницах она стоит внизу большим прямоугольником, и белое пятно
/// в пол-экрана перетягивало бы на себя всё внимание.
class PlatformButton extends StatelessWidget {
  const PlatformButton({
    super.key,
    required this.label,
    required this.onTap,
    this.muted = false,
    this.busy = false,
    this.height = 54,
  });

  final String label;
  final VoidCallback? onTap;
  final bool muted;
  final bool busy;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final enabled = !busy && onTap != null;
    final color = muted || !enabled ? t.muted : t.text;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: GlassBox(
        color: muted ? Colors.transparent : null,
        // Прозрачной кнопке стекло не нужно: размывать под ней нечего, а
        // плёнка заливки сделала бы её похожей на главную.
        enabled: !muted,
        borderRadius: BorderRadius.circular(t.radius),
        borderSide: muted ? BorderSide(color: t.ovlLine2) : BorderSide.none,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: t.text,
                    ),
                  )
                : Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Карточка-ссылка на инструкцию: знак площадки, название, подпись и значок
/// справа. Тап открывает шторку с гайдом.
class PlatformCard extends StatelessWidget {
  const PlatformCard({
    super.key,
    required this.mark,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = SolarIconsOutline.questionCircle,
  });

  final BrandMark mark;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: mark.logo(size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.bodyMedium?.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 20, color: t.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Разделитель «или» между карточкой подключения и ручным вводом. Без линий:
/// на референсе это одно слово посреди пустоты.
class OrLabel extends StatelessWidget {
  const OrLabel({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Text(
      context.l.commonOr,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.bloom.muted),
    ),
  );
}

/// Шторка с инструкцией — то, что на десктопе лежит в попапе под кнопкой «?».
///
/// [steps] размечаются как на ПК: `**жирным**` выделяются адреса, клавиши и
/// имена параметров — то, что пользователь ищет глазами.
Future<void> showPlatformGuide(
  BuildContext context, {
  required BrandMark mark,
  required String title,
  List<String> steps = const [],
  String? note,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: _GuideHeader(mark: mark, title: title),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (steps.isNotEmpty)
          SheetPanel(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) sheetDivider(),
                _GuideStep(index: i + 1, mark: mark, text: steps[i]),
              ],
            ],
          ),
        if (note case final text?)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
            child: Builder(
              builder: (context) => Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.bloom.text2,
                  height: 1.6,
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _GuideHeader extends StatelessWidget {
  const _GuideHeader({required this.mark, required this.title});

  final BrandMark mark;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      child: Row(
        children: [
          // Знак в кружке своего цвета — тот же приём, что в строках площадок
          // на онбординге: без подложки мелкий логотип теряется.
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (mark.color ?? t.accent).withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: mark.logo(size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(title, style: theme.titleLarge)),
        ],
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.index,
    required this.mark,
    required this.text,
  });

  final int index;
  final BrandMark mark;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final brand = mark.color ?? t.accent;
    final base = theme.bodyMedium?.copyWith(color: t.text2, height: 1.5);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: brand.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: theme.labelSmall?.copyWith(
                color: brand,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: markupSpans(
                  text,
                  base,
                  base?.copyWith(color: t.text, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Разбор `**жирного**` в куски текста. Нечётные куски — выделенные.
List<TextSpan> markupSpans(String text, TextStyle? base, TextStyle? strong) => [
  for (final (i, part) in text.split('**').indexed)
    if (part.isNotEmpty) TextSpan(text: part, style: i.isOdd ? strong : base),
];
