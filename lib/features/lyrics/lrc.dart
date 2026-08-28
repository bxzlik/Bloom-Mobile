/// Разбор LRC — синхронизированного текста песни.
///
/// Порт десктопных `lib/parseLrc.ts` (`parseLrc`/`stripLrc`) и `strip_lrc_tags`
/// из `lyrics_service.rs`. Формат один и тот же: строка вида `[mm:ss.xx]текст`,
/// где дробная часть необязательна.
library;

/// Одна строка синхронного текста.
class LrcLine {
  const LrcLine(this.time, this.text);

  /// Секунды от начала трека.
  final double time;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is LrcLine && other.time == time && other.text == text;

  @override
  int get hashCode => Object.hash(time, text);

  @override
  String toString() => 'LrcLine($time, $text)';
}

final RegExp _lrcRow = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\](.*)');
final RegExp _lrcTag = RegExp(r'\[\d+:\d+(?:\.\d+)?\]');

/// `[mm:ss.xx]текст` построчно → строки по возрастанию времени.
///
/// Пустые строки (один тайм-код без текста) выбрасываем: на ПК так же — это
/// разделители куплетов, и в списке они дали бы пустые «активные» строки, на
/// которых подсветка просто исчезала бы.
List<LrcLine> parseLrc(String lrc) {
  final out = <LrcLine>[];
  for (final row in lrc.split('\n')) {
    final m = _lrcRow.firstMatch(row);
    if (m == null) continue;
    final text = m.group(3)!.trim();
    if (text.isEmpty) continue;
    final min = int.tryParse(m.group(1)!);
    final sec = double.tryParse(m.group(2)!);
    if (min == null || sec == null) continue;
    out.add(LrcLine(min * 60 + sec, text));
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

/// Убрать тайм-коды — LRC превращается в обычный текст.
String stripLrc(String s) => s.replaceAll(_lrcTag, '').trim();

/// Есть ли в тексте тайм-коды (`RX_LRC_DETECT` с ПК).
bool looksLikeLrc(String s) =>
    RegExp(r'\[\d{1,2}:\d{2}\.\d{2,3}\]').hasMatch(s);

/// Номер активной строки для позиции [sec]; −1 — играет вступление до первой.
///
/// Фора 0.25 с — как на ПК: тайм-коды LRC ставят по началу вокала, а строку
/// хочется видеть чуть раньше, чем её запели.
int activeLineAt(List<LrcLine> lines, double sec) {
  var idx = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time <= sec + 0.25) {
      idx = i;
    } else {
      break;
    }
  }
  return idx;
}

/// Сколько времени отводим последней строке текста, у которой нет следующей.
const double kLastLineSec = 4;

/// Границы единиц заливки внутри строки — по словам или по буквам.
///
/// LRC даёт время только целой строки, поэтому интервал делим ПРОПОРЦИОНАЛЬНО
/// числу символов (пробелы не считаем) — ровно как `LyricsUnits` на ПК.
/// Тайминги от этого синтетические, точнее исходные данные не позволяют.
///
/// Возвращает смещения в тексте: `[начало0, начало1, ..., конец]` — по ним
/// художник строки режет абзац, не пересобирая его из кусков (перенос строк
/// обязан считаться по целому тексту).
({List<int> offsets, List<double> starts}) lrcUnits(
  String text, {
  required bool byLetter,
  required double from,
  required double to,
}) {
  final offsets = <int>[];
  final lengths = <int>[];
  final chars = text.runes.toList();

  var i = 0;
  while (i < chars.length) {
    // Пробелы к единицам не относятся: на ПК они остаются текстовыми узлами,
    // чтобы не «зажигаться» отдельно.
    if (_isSpace(chars[i])) {
      i++;
      continue;
    }
    final start = i;
    if (byLetter) {
      i++;
    } else {
      while (i < chars.length && !_isSpace(chars[i])) {
        i++;
      }
    }
    offsets.add(_utf16Offset(chars, start));
    lengths.add(i - start);
  }

  final total = lengths.fold<int>(0, (a, b) => a + b);
  final starts = <double>[];
  var acc = 0;
  for (final len in lengths) {
    starts.add(total == 0 ? from : from + (acc / total) * (to - from));
    acc += len;
  }
  // Конец последней единицы = конец строки: тем же правилом живёт художник.
  offsets.add(text.length);
  return (offsets: offsets, starts: starts);
}

bool _isSpace(int rune) =>
    rune == 0x20 || rune == 0x09 || rune == 0x0A || rune == 0x0D;

/// Смещение [runeIndex]-й руны в UTF-16 — им меряется `TextPainter`, а эмодзи
/// и суррогатные пары в тексте песни встречаются.
int _utf16Offset(List<int> runes, int runeIndex) {
  var out = 0;
  for (var i = 0; i < runeIndex; i++) {
    out += String.fromCharCode(runes[i]).length > 1 || runes[i] > 0xFFFF
        ? 2
        : 1;
  }
  return out;
}
