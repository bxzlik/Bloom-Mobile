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

/// Кого уже искали за этот запуск: «площадка|имя» → найденный артист (null —
/// искали и не нашли).
final Map<String, Artist?> _memo = {};

/// То же, что [findArtistByName], но один и тот же артист за запуск ищется
/// однажды.
///
/// Спрашивают одни и те же имена помногу: шторка выбора артистов открывается
/// по треку не раз, а плеер лезет за аватарками на каждой смене трека — без
/// памяти это был бы запрос к площадке на каждое такое открытие.
///
/// Промахи по ошибке сети сюда НЕ попадают: исключение уходит наверх, и со
/// связью попытка повторится удачнее. Запоминается только внятный ответ
/// площадки, в том числе «такого нет».
Future<Artist?> findArtistCached(MusicProvider provider, String name) async {
  final key = '${provider.id}|${name.trim().toLowerCase()}';
  if (_memo.containsKey(key)) return _memo[key];
  final artist = await findArtistByName(provider, name);
  _memo[key] = artist;
  return artist;
}
