/// Сортировка и порядок библиотеки: четыре режима, ручной порядок и
/// закреплённые. Место и закрепление — в строках базы, как на ПК; режим и
/// фильтр — настройки вида.
library;

import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/library/lib_order_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloom/core/db/db.dart';
import 'support/test_db.dart';

/// Карточка библиотеки в том виде, в каком её видит сортировка.
class _Card {
  const _Card(this.key, this.name, this.rank, this.sidePos, this.pinned);
  final String key;
  final String name;
  final int rank;
  final int sidePos;
  final bool pinned;
}

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(testDb(store)),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Два плейлиста и подписка — в таком порядке и заведены.
({String beta, String alpha}) _seed(ProviderContainer c) {
  final lib = c.read(libraryProvider.notifier);
  final beta = lib.createPlaylist('Бета').id;
  final alpha = lib.createPlaylist('Альфа').id;
  lib.toggleFollow(
    const Artist(
      id: 'sc:artist:1',
      name: 'Гамма',
      source: MusicSource.soundcloud,
    ),
  );
  return (beta: beta, alpha: alpha);
}

/// Раскладка, как на экране библиотеки, — именами.
List<String> _names(ProviderContainer c) {
  final lib = c.read(libraryProvider);
  final cards = [
    for (final p in lib.playlists)
      _Card(
        libKeyOfPlaylist(p.id),
        p.name,
        kLibRankPlaylist,
        p.sidePos,
        p.pinned,
      ),
    for (final f in lib.follows)
      _Card(
        libKeyOfArtist(f.artist.id),
        f.artist.name,
        kLibRankArtist,
        f.sidePos,
        f.pinned,
      ),
  ];
  return c
      .read(libOrderProvider)
      .arrange(
        cards,
        name: (e) => e.name,
        rank: (e) => e.rank,
        sidePos: (e) => e.sidePos,
        pinned: (e) => e.pinned,
      )
      .map((e) => e.name)
      .toList();
}

const _artistKey = 'artist:sc:artist:1';

void main() {
  test('«По умолчанию» новые карточки встают по порядку заведения', () {
    final c = _container(JsonStore.memory());
    _seed(c);
    expect(_names(c), ['Бета', 'Альфа', 'Гамма']);
  });

  test('перетаскивание пишет места в базу и переживает перезапуск', () {
    final store = JsonStore.memory();
    final first = _container(store);
    final ids = _seed(first);
    first.read(libraryProvider.notifier).reorderCards([
      _artistKey,
      libKeyOfPlaylist(ids.alpha),
      libKeyOfPlaylist(ids.beta),
    ]);
    expect(_names(first), ['Гамма', 'Альфа', 'Бета']);

    expect(_names(_container(store)), ['Гамма', 'Альфа', 'Бета']);
  });

  test('сортировка по имени идёт в обе стороны', () {
    final c = _container(JsonStore.memory());
    _seed(c);
    final order = c.read(libOrderProvider.notifier);

    order.setSort(LibSort.nameAsc);
    expect(_names(c), ['Альфа', 'Бета', 'Гамма']);

    order.setSort(LibSort.nameDesc);
    expect(_names(c), ['Гамма', 'Бета', 'Альфа']);
  });

  test('«По типу» держит плейлисты выше артистов, не трогая их порядок', () {
    final c = _container(JsonStore.memory());
    final ids = _seed(c);
    c.read(libraryProvider.notifier).reorderCards([
      _artistKey,
      libKeyOfPlaylist(ids.beta),
      libKeyOfPlaylist(ids.alpha),
    ]);
    c.read(libOrderProvider.notifier).setSort(LibSort.type);
    expect(_names(c), ['Бета', 'Альфа', 'Гамма']);
  });

  test('закреплённое всплывает наверх в ЛЮБОМ режиме и хранится в базе', () {
    final store = JsonStore.memory();
    final c = _container(store);
    _seed(c);
    final lib = c.read(libraryProvider.notifier);
    lib.setPinned(_artistKey, true);

    expect(_names(c).first, 'Гамма');
    expect(c.read(libraryProvider).follows.single.pinned, isTrue);

    c.read(libOrderProvider.notifier).setSort(LibSort.nameAsc);
    expect(_names(c).first, 'Гамма');
    expect(_names(_container(store)).first, 'Гамма');

    // Открепление возвращает карточку на её место.
    lib.setPinned(_artistKey, false);
    expect(_names(c).last, 'Гамма');
  });

  test('режим и фильтр переживают перезапуск', () {
    final store = JsonStore.memory();
    _container(store).read(libOrderProvider.notifier)
      ..setSort(LibSort.nameDesc)
      ..setFilter(LibFilter.artists);

    final state = _container(store).read(libOrderProvider);
    expect(state.sort, LibSort.nameDesc);
    expect(state.filter, LibFilter.artists);
  });

  test('без записи на диске фильтр — «Все»', () {
    final c = _container(JsonStore.memory());
    expect(c.read(libOrderProvider).filter, LibFilter.all);
  });
}
