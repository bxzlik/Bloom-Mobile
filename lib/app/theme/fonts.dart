/// Каталог шрифтов интерфейса — порт десктопного
/// `features/settings/lib/fonts.ts`.
///
/// Встроенных два, оба файлами в `assets/fonts`: Inter (по умолчанию) и
/// Minecraft Rus. Третьего десктопного, Comic Sans MS, нет: на ПК он системный
/// из Windows, на телефоне его нет, а встроить нельзя — шрифт платный.
///
/// Сверх каталога человек грузит свои файлы (`features/settings/user_fonts.dart`).
///
/// В настройках хранится само семейство (`Inter`, `bloomfont-…`), а не
/// CSS-стек, как на ПК, — стек не нужен, запасной шрифт задаёт тема.
library;

class BloomFont {
  const BloomFont(this.name, this.family);

  /// Подпись плитки.
  final String name;

  /// Семейство из pubspec.
  final String family;
}

const String kDefaultFont = 'Inter';

const List<BloomFont> kBuiltinFonts = [
  BloomFont('Inter', 'Inter'),
  BloomFont('Minecraft', 'Minecraft Rus'),
];

/// Шрифты, заменённые другими: сохранённый выбор переезжает, а не
/// сбрасывается (как `REPLACED` на ПК).
const Map<String, String> _replaced = {'Monocraft': 'Minecraft Rus'};

/// Первое семейство из CSS-значения font-family, без кавычек: так узнаётся и
/// десктопное `'Inter',system-ui,sans-serif`.
String firstFontFamily(String value) =>
    value.split(',').first.trim().replaceAll(RegExp(r'''^['"]|['"]$'''), '');

/// Сохранённое значение → семейство, которым можно рисовать. Шрифты, которых
/// нет ни в каталоге, ни среди своих ([userFamilies]), и мусор → Inter: иначе
/// интерфейс молча уехал бы на системный запасной шрифт.
String normalizeFont(Object? raw, Iterable<String> userFamilies) {
  if (raw is! String) return kDefaultFont;
  final first = firstFontFamily(raw);
  final family = _replaced[first] ?? first;
  if (userFamilies.contains(family)) return family;
  return kBuiltinFonts.any((f) => f.family == family) ? family : kDefaultFont;
}
