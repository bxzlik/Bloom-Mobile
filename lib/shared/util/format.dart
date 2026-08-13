/// Форматирование длительностей.
library;

String mmss(Duration d) {
  final s = d.inSeconds.clamp(0, 24 * 3600);
  final m = s ~/ 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  if (m < 60) return '$m:$sec';
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:$sec';
}

String mmssMs(int ms) => mmss(Duration(milliseconds: ms));

/// Короткое число: 1234 → «1.2K», 6700572 → «6.7M».
String compactCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) {
    final k = n / 1000;
    return '${k < 10 ? k.toStringAsFixed(1) : k.round()}K';
  }
  final m = n / 1000000;
  return '${m < 10 ? m.toStringAsFixed(1) : m.round()}M';
}

// «12 треков» переехало в словарь: ключ `tracksCount` в `lib/l10n/*.arb`
// считает формы через ICU-плюрали, поэтому русская тройка (трек/трека/треков)
// и английская пара живут рядом с остальными строками, а не в коде.
