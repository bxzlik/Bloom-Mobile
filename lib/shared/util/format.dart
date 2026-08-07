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

/// «12 треков» с русскими формами множественного числа.
String tracksCount(int n) {
  final mod100 = n % 100;
  final mod10 = n % 10;
  final String word;
  if (mod100 >= 11 && mod100 <= 14) {
    word = 'треков';
  } else if (mod10 == 1) {
    word = 'трек';
  } else if (mod10 >= 2 && mod10 <= 4) {
    word = 'трека';
  } else {
    word = 'треков';
  }
  return '$n $word';
}
