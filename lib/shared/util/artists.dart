/// Разбор строки артистов — как `Artists::split` ПК.
library;

import '../../core/entities/entities.dart';

/// Первый артист трека и его страница, если она известна, — первая ссылка
/// `Artists::linksOf` ПК. Строка SoundCloud — один аккаунт, что бы ни было в
/// его имени («Simon & Garfunkel»); у остальных — первое имя строки, а id —
/// только когда имя одно.
({String name, String? id}) firstArtistLink(Track t) {
  if (t.source == MusicSource.soundcloud &&
      t.artistId != null &&
      parseArtists(t.artist).isNotEmpty) {
    return (name: t.artist.trim(), id: t.artistId);
  }
  final names = parseArtists(t.artist);
  return (
    name: names.isEmpty ? '' : names.first,
    id: names.length == 1 ? t.artistId : null,
  );
}

/// Разделители: `,` `&` `×` и связки feat./ft./vs. Не «and», «x», «и»: они
/// часть слишком многих имён («Florence and the Machine», «Mr. X»).
///
/// Символы режут строку в любом окружении, слова — только между пробелами:
/// иначе «Andrew» и «Sandvs» разлетелись бы на куски прямо посреди имени.
final RegExp _sep = RegExp(
  r'\s*[,&×]\s*|\s+(?:feat\.?|ft\.?|vs\.?)\s+',
  caseSensitive: false,
);

/// «Artist A, Artist B feat. Artist C» → `[Artist A, Artist B, Artist C]`.
///
/// Строка без разделителей возвращается одним куском — так вызывающему хватает
/// длины списка, чтобы решить, один тут артист или несколько.
List<String> parseArtists(String? s) {
  final str = s?.trim() ?? '';
  if (str.isEmpty) return const [];
  final parts = [
    for (final p in str.split(_sep))
      if (p.trim().isNotEmpty) p.trim(),
  ];
  // Имя из одних разделителей («&») режется в пустоту — тогда оно и есть
  // артист, каким бы странным ни было.
  return parts.isEmpty ? [str] : parts;
}
