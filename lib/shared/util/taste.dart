/// Общие правила вкуса — как `Taste` ПК: по ним волна и витрины главной
/// узнают артистов трека и держат их в меру.
library;

import '../../core/entities/entities.dart';
import 'artists.dart';

/// Имя артиста как ключ сравнения: регистр и пробелы по краям не различают.
String artistKey(String name) => name.trim().toLowerCase();

/// Ключи всех имён трека: «A feat. B» — это и A, и B.
Set<String> artistKeys(Track t) => {
  for (final n in parseArtists(t.artist)) artistKey(n),
};

/// Не больше [max] треков на артиста — по каждому имени трека, а не по строке
/// целиком: «A feat. B» занимает место и A, и B.
class ArtistCap {
  ArtistCap(this.max);

  final int max;
  final Map<String, int> _count = {};

  bool fits(Track t) => artistKeys(t).every((k) => (_count[k] ?? 0) < max);

  void take(Track t) {
    for (final k in artistKeys(t)) {
      _count[k] = (_count[k] ?? 0) + 1;
    }
  }
}
