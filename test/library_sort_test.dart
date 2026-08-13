/// Сортировка и порядок библиотеки: четыре режима, ручной порядок и
/// закреплённые — то же, что делает `unifiedOrderStore` на десктопе.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/features/library/lib_order_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Запись библиотеки в том виде, в каком её видит сортировка.
class _Item {
  const _Item(this.key, this.name, this.rank);
  final String key;
  final String name;
  final int rank;
}

const _playlists = [
  _Item('playlist:a', 'Бета', kLibRankPlaylist),
  _Item('playlist:b', 'Альфа', kLibRankPlaylist),
];
const _artists = [_Item('artist:x', 'Гамма', kLibRankArtist)];
const _all = [..._playlists, ..._artists];

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

List<String> _arrange(LibOrderState state, [List<_Item> items = _all]) => state
    .arrange(items, key: (e) => e.key, name: (e) => e.name, rank: (e) => e.rank)
    .map((e) => e.key)
    .toList();

void main() {
  test('без своего порядка «По умолчанию» ничего не переставляет', () {
    final c = _container(JsonStore.memory());
    expect(_arrange(c.read(libOrderProvider)), [
      'playlist:a',
      'playlist:b',
      'artist:x',
    ]);
  });

  test('ручной порядок соблюдается, новые записи уезжают в конец', () {
    final c = _container(JsonStore.memory());
    // Порядок записан до того, как появился артист, — он и есть «новая запись».
    c.read(libOrderProvider.notifier).setOrder(['playlist:b', 'playlist:a']);

    expect(_arrange(c.read(libOrderProvider)), [
      'playlist:b',
      'playlist:a',
      'artist:x',
    ]);
  });

  test('сортировка по имени идёт в обе стороны', () {
    final c = _container(JsonStore.memory());
    final order = c.read(libOrderProvider.notifier);

    order.setSort(LibSort.nameAsc);
    expect(_arrange(c.read(libOrderProvider)), [
      'playlist:b', // Альфа
      'playlist:a', // Бета
      'artist:x', // Гамма
    ]);

    order.setSort(LibSort.nameDesc);
    expect(_arrange(c.read(libOrderProvider)), [
      'artist:x',
      'playlist:a',
      'playlist:b',
    ]);
  });

  test('«По типу» держит плейлисты выше артистов, не трогая их порядок', () {
    final c = _container(JsonStore.memory());
    c.read(libOrderProvider.notifier).setSort(LibSort.type);

    expect(
      _arrange(c.read(libOrderProvider), [_artists.first, ..._playlists]),
      ['playlist:a', 'playlist:b', 'artist:x'],
    );
  });

  test('закреплённое всплывает наверх в ЛЮБОМ режиме', () {
    final c = _container(JsonStore.memory());
    final order = c.read(libOrderProvider.notifier);
    order.togglePin('artist:x');

    expect(_arrange(c.read(libOrderProvider)).first, 'artist:x');

    order.setSort(LibSort.nameAsc);
    expect(_arrange(c.read(libOrderProvider)).first, 'artist:x');

    // Открепление возвращает запись на её место в порядке.
    order.togglePin('artist:x');
    expect(_arrange(c.read(libOrderProvider)).last, 'artist:x');
  });

  test('режим, порядок и закрепления переживают перезапуск', () {
    final store = JsonStore.memory();
    final first = _container(store);
    first.read(libOrderProvider.notifier)
      ..setSort(LibSort.nameDesc)
      ..setOrder(['artist:x', 'playlist:a', 'playlist:b'])
      ..togglePin('playlist:b');

    final second = _container(store);
    final state = second.read(libOrderProvider);
    expect(state.sort, LibSort.nameDesc);
    expect(state.order, ['artist:x', 'playlist:a', 'playlist:b']);
    expect(state.isPinned('playlist:b'), isTrue);
  });
}
