/// Разбор строки артистов — как `Artists::split` ПК.
library;

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
