/// Артист площадки по одному лишь имени.
///
/// Нужен там, где точного id взять неоткуда: в истории от артиста остаётся имя
/// (топ статистики), а у трека с несколькими артистами id есть только у того,
/// кто трек залил.
library;

import '../entities/entities.dart';
import 'music_provider.dart';

/// Найти артиста по имени. `null` — площадка ничего не вернула.
///
/// Точное совпадение имени лучше первого попавшегося: у SoundCloud по запросу
/// «Onda» первым легко идёт чужой фан-аккаунт.
Future<Artist?> findArtistByName(MusicProvider provider, String name) async {
  final key = name.trim().toLowerCase();
  if (key.isEmpty) return null;
  final found = await provider.searchArtists(name, limit: 3);
  for (final a in found) {
    if (a.name.toLowerCase() == key) return a;
  }
  return found.isEmpty ? null : found.first;
}
