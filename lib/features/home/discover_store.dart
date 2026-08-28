/// Витрина «Чарты и новинки» на главной — порт `DiscoverSections.tsx`.
///
/// Блок провайдеро-агностичен: чарт — всегда треки, новинки — альбомы (Яндекс,
/// YTM) либо треки (SoundCloud «New & Hot»). Площадка берётся первая, которая
/// умеет нужный метод; сейчас это Яндекс, поэтому переключателя нет — рядом с
/// заголовком просто стоит её логотип.
///
/// Кеш и тихие повторы — как на ПК: пустой ответ у Яндекса почти всегда
/// транзиентный сбой landing3, поэтому пустое НЕ кешируется, а запрос тихо
/// повторяется. Пока данных нет, секции не видно вовсе: пустое место лучше
/// мигающей заглушки.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/music_provider.dart';
import '../../core/providers/registry.dart';

enum DiscoverMode { charts, newReleases }

/// Содержимое блока: либо треки, либо альбомы.
sealed class DiscoverBlock {
  const DiscoverBlock();

  bool get isEmpty;
}

class DiscoverTracks extends DiscoverBlock {
  const DiscoverTracks(this.tracks);
  final List<Track> tracks;

  @override
  bool get isEmpty => tracks.isEmpty;
}

class DiscoverAlbums extends DiscoverBlock {
  const DiscoverAlbums(this.albums);
  final List<Playlist> albums;

  @override
  bool get isEmpty => albums.isEmpty;
}

/// Загруженный блок с площадкой, у которой он взят: логотип рядом с заголовком
/// рисуется по ней, а не по первому попавшемуся треку.
class DiscoverResult {
  const DiscoverResult(this.source, this.block);

  final MusicSource source;
  final DiscoverBlock block;
}

/// Сколько живёт кеш блока. Чарты и новинки меняются раз в сутки — получасовой
/// TTL нужен лишь для того, чтобы не ходить в сеть на каждый заход на главную.
const Duration kDiscoverTtl = Duration(minutes: 30);

/// Паузы перед тихими повторами, если ответ пустой или запрос упал (после
/// последней сдаёмся и оставляем блок скрытым).
const List<Duration> kDiscoverRetries = [
  Duration(milliseconds: 1500),
  Duration(seconds: 4),
];

class _CacheEntry {
  _CacheEntry(this.result, this.at);
  final DiscoverResult result;
  final DateTime at;
}

/// Кеш переживает пересоздание провайдера — уход с главной и возврат на неё не
/// должен снова дёргать сеть.
final Map<DiscoverMode, _CacheEntry> _cache = {};

/// Сбросить кеш витрины (тесты и смена аккаунта площадки).
void resetDiscoverCache() => _cache.clear();

/// Один заход в сеть, без повторов. Пустой результат не кешируется.
Future<DiscoverResult?> fetchDiscover(
  ProviderRegistry registry,
  DiscoverMode mode,
) async {
  final hit = _cache[mode];
  if (hit != null && DateTime.now().difference(hit.at) < kDiscoverTtl) {
    return hit.result;
  }
  for (final provider in registry.enabled) {
    final DiscoverBlock? block;
    if (mode == DiscoverMode.charts) {
      final tracks = await provider.getCharts();
      block = tracks == null ? null : DiscoverTracks(tracks);
    } else {
      final releases = await provider.getNewReleases();
      block = switch (releases) {
        null => null,
        NewAlbums(:final albums) => DiscoverAlbums(albums),
        NewTracks(:final tracks) => DiscoverTracks(tracks),
      };
    }
    // Метода у площадки нет — идём к следующей; пустой ответ считаем сбоем
    // ЭТОЙ площадки и тоже пробуем следующую.
    if (block == null || block.isEmpty) continue;
    final result = DiscoverResult(provider.source, block);
    _cache[mode] = _CacheEntry(result, DateTime.now());
    return result;
  }
  return null;
}

/// Блок витрины с тихими повторами. `null` в данных — показывать нечего.
final discoverProvider = FutureProvider.family<DiscoverResult?, DiscoverMode>((
  ref,
  mode,
) async {
  final registry = ref.read(registryProvider);
  for (var attempt = 0; ; attempt++) {
    try {
      final result = await fetchDiscover(registry, mode);
      if (result != null) return result;
    } on Object {
      // Сбой площадки секцию не ломает — она просто не появится.
    }
    if (attempt >= kDiscoverRetries.length) return null;
    await Future<void>.delayed(kDiscoverRetries[attempt]);
  }
});
