/// Разбор строки артистов — порт `src/shared/lib/parseArtists`.
library;

/// Разделители: `,` `;` `&` `×` и слова-связки (feat./ft./vs./x/with/and/и).
///
/// Символы режут строку в любом окружении, слова — только между пробелами:
/// иначе «Andrew» и «Fixt» разлетелись бы на куски прямо посреди имени.
final RegExp _sep = RegExp(
  r'\s*[,;&×]\s*|\s+(?:feat\.?|ft\.?|vs\.?|and|with|x|и)\s+',
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
