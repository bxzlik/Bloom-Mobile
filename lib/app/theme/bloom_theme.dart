/// Сборка [ThemeData] из токенов Bloom.
///
/// Inter подключён вариативным файлом, поэтому вес задаётся ДВАЖДЫ:
/// `fontWeight` (для fallback-синтеза) и `fontVariations` с осью `wght` —
/// без второго вариативный шрифт рисуется одним начертанием.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

const String kFontFamily = 'Inter';

TextStyle bloomText({
  required double size,
  required int weight,
  required Color color,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: kFontFamily,
  fontSize: size,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
  fontWeight: FontWeight.values[(weight ~/ 100) - 1],
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

ThemeData buildBloomTheme(BloomTokens t) {
  final scheme = ColorScheme(
    brightness: t.isLight ? Brightness.light : Brightness.dark,
    primary: t.accent,
    onPrimary: t.accentText,
    secondary: t.accent2,
    onSecondary: t.accentText,
    surface: t.blockColor,
    onSurface: t.text,
    surfaceContainerHighest: t.card,
    onSurfaceVariant: t.text2,
    outline: t.border,
    error: const Color(0xFFFF5578),
    onError: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: kFontFamily,
    // Переход между страницами. Дефолт Android — предиктивный: пока тянешь
    // системный жест «назад», страница сжимается в карточку и в щель видно
    // предыдущий экран. Ставим сдвиг с растворением (переход Android U):
    // ничего не «подглядывает», анимация играет целиком по факту ухода.
    // Фон перехода — цвет темы, иначе между страницами мигает чёрное.
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final p in TargetPlatform.values)
          p: FadeForwardsPageTransitionsBuilder(backgroundColor: t.bg),
      },
    ),
    // Нажатие НЕ подсвечивается вообще: ни ряби, ни плёнки под пальцем.
    // Гасим сразу три источника — фабрику всплеска, цвет всплеска и цвет
    // подсветки удержания, — иначе material вернёт заливку через любой из них.
    // Новые кнопки тоже не должны её заводить: если понадобится отклик на
    // нажатие, он делается движением самого элемента, а не заливкой.
    splashFactory: NoSplash.splashFactory,
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    extensions: [t],
    textTheme: TextTheme(
      // Заголовок экрана / название трека в плеере.
      headlineSmall: bloomText(
        size: 22,
        weight: 700,
        color: t.text,
        height: 1.2,
      ),
      // Заголовок секции («Для вас», «Популярное»).
      titleLarge: bloomText(size: 19, weight: 700, color: t.text, height: 1.25),
      // Строка списка, название карточки.
      titleMedium: bloomText(size: 15, weight: 600, color: t.text, height: 1.3),
      titleSmall: bloomText(size: 13, weight: 600, color: t.text, height: 1.3),
      // Артист, подпись под карточкой.
      bodyMedium: bloomText(
        size: 13,
        weight: 500,
        color: t.text2,
        height: 1.35,
      ),
      bodySmall: bloomText(size: 12, weight: 500, color: t.muted, height: 1.35),
      // Капсовый заголовок группы настроек.
      labelSmall: bloomText(
        size: 11,
        weight: 600,
        color: t.muted,
        letterSpacing: 0.6,
      ),
    ),
    iconTheme: IconThemeData(color: t.iconFg, size: 22),
    dividerTheme: DividerThemeData(color: t.ovlLine, thickness: 1, space: 1),
    // Запасной вид для голого `SnackBar`. Свои тосты его не используют: они
    // рисуются `BloomToastCard` (`shared/ui/bloom_toast.dart`), а сам снекбар
    // делают прозрачным — см. `_show` там же.
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.pill,
      contentTextStyle: bloomText(size: 14, weight: 500, color: t.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.ovlLine),
      ),
      insetPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: t.iconFg,
      textColor: t.text,
      titleTextStyle: bloomText(size: 15, weight: 600, color: t.text),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: t.accent,
      inactiveTrackColor: t.track,
      thumbColor: t.accent,
      trackHeight: 3,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    // Кнопки material берут подсветку нажатия из своего `overlayColor`, мимо
    // `highlightColor` темы, — гасим её отдельно для каждого вида.
    textButtonTheme: const TextButtonThemeData(style: _flatButton),
    filledButtonTheme: const FilledButtonThemeData(style: _flatButton),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: _flatButton),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: _flatButton),
    iconButtonTheme: const IconButtonThemeData(style: _flatButton),
  );
}

/// Кнопка без заливки под пальцем.
const ButtonStyle _flatButton = ButtonStyle(
  splashFactory: NoSplash.splashFactory,
  overlayColor: WidgetStatePropertyAll(Colors.transparent),
);
