/// Порядок и сортировка библиотеки — порт десктопных `useLibSidebarSort` и
/// `unifiedOrderStore`.
///
/// Как на ПК: режимов четыре, и «По умолчанию» — это НЕ порядок создания, а
/// пользовательский, собранный перетаскиванием. Закреплённые всегда идут
/// сверху, в каком бы режиме ни был список: на десктопе вынос pinned делает
/// `buildOrderedUnifiedEntries` уже после сортировки, здесь — [LibOrderState.arrange].
///
/// Папок в мобилке нет (их приносит folder_watcher, которого тут не бывает),
/// поэтому типов два: плейлист и артист — ранги те же, что в десктопном
/// `TYPE_ORDER`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/l10n/l10n.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;

enum LibSort { manual, nameAsc, nameDesc, type }

extension LibSortMeta on LibSort {
  String label(AppLocalizations l) => switch (this) {
    LibSort.manual => l.libSortManual,
    LibSort.nameAsc => l.libSortNameAsc,
    LibSort.nameDesc => l.libSortNameDesc,
    LibSort.type => l.libSortType,
  };

  IconData get icon => switch (this) {
    LibSort.manual => SolarIconsOutline.reorder,
    LibSort.nameAsc => SolarIconsOutline.sortFromTopToBottom,
    LibSort.nameDesc => SolarIconsOutline.sortFromBottomToTop,
    LibSort.type => SolarIconsOutline.library,
  };

  /// Идентификатор для диска — те же строки, что в `localStorage` на ПК.
  String get id => switch (this) {
    LibSort.manual => 'default',
    LibSort.nameAsc => 'name-asc',
    LibSort.nameDesc => 'name-desc',
    LibSort.type => 'type',
  };
}

LibSort _sortFromId(Object? id) =>
    LibSort.values.firstWhere((s) => s.id == id, orElse: () => LibSort.manual);

/// Ключ записи: тип и id вместе, иначе плейлист и артист с одинаковым id
/// схлопнулись бы в один элемент порядка (десктопный `keyOf`).
String libKeyOfPlaylist(String id) => 'playlist:$id';
String libKeyOfArtist(String id) => 'artist:$id';

/// Ранг типа для режима «По типу»: сначала плейлисты, потом артисты.
const int kLibRankPlaylist = 0;
const int kLibRankArtist = 1;

class LibOrderState {
  const LibOrderState({
    this.sort = LibSort.manual,
    this.order = const [],
    this.pinned = const {},
  });

  final LibSort sort;

  /// Пользовательский порядок ключей. Новые записи в нём не значатся и
  /// уезжают в конец — как `applyOrder` на десктопе.
  final List<String> order;

  final Set<String> pinned;

  bool isPinned(String key) => pinned.contains(key);

  LibOrderState copyWith({
    LibSort? sort,
    List<String>? order,
    Set<String>? pinned,
  }) => LibOrderState(
    sort: sort ?? this.sort,
    order: order ?? this.order,
    pinned: pinned ?? this.pinned,
  );

  /// Разложить записи библиотеки по текущему режиму. [key] — ключ записи,
  /// [name] — по чему сортировать имена, [rank] — тип (`kLibRank*`).
  ///
  /// Сортировки в Dart нестабильны, поэтому в компараторе последним идёт
  /// сравнение исходных позиций: без него равные имена (или один и тот же
  /// ранг) тасовались бы на каждой перерисовке.
  List<T> arrange<T>(
    List<T> items, {
    required String Function(T) key,
    required String Function(T) name,
    required int Function(T) rank,
  }) {
    final indexed = [
      for (var i = 0; i < items.length; i++) (item: items[i], at: i),
    ];

    if (sort == LibSort.manual) {
      final at = {for (var i = 0; i < order.length; i++) order[i]: i};
      indexed.sort((a, b) {
        final pa = at[key(a.item)] ?? order.length + a.at;
        final pb = at[key(b.item)] ?? order.length + b.at;
        return pa != pb ? pa.compareTo(pb) : a.at.compareTo(b.at);
      });
    } else {
      indexed.sort((a, b) {
        final byKind = switch (sort) {
          LibSort.nameAsc => name(
            a.item,
          ).toLowerCase().compareTo(name(b.item).toLowerCase()),
          LibSort.nameDesc => name(
            b.item,
          ).toLowerCase().compareTo(name(a.item).toLowerCase()),
          _ => rank(a.item).compareTo(rank(b.item)),
        };
        return byKind != 0 ? byKind : a.at.compareTo(b.at);
      });
    }

    final sorted = indexed.map((e) => e.item).toList();
    if (pinned.isEmpty) return sorted;
    return [
      ...sorted.where((e) => pinned.contains(key(e))),
      ...sorted.where((e) => !pinned.contains(key(e))),
    ];
  }
}

final libOrderProvider = NotifierProvider<LibOrderController, LibOrderState>(
  LibOrderController.new,
);

class LibOrderController extends Notifier<LibOrderState> {
  @override
  LibOrderState build() {
    final raw = ref.read(jsonStoreProvider).readMap('libOrder');
    return LibOrderState(
      sort: _sortFromId(raw['sort']),
      order: (raw['order'] as List?)?.whereType<String>().toList() ?? const [],
      pinned: (raw['pinned'] as List?)?.whereType<String>().toSet() ?? const {},
    );
  }

  void _save() => ref.read(jsonStoreProvider).write('libOrder', {
    'sort': state.sort.id,
    'order': state.order,
    'pinned': state.pinned.toList(),
  });

  void setSort(LibSort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort);
    _save();
  }

  /// Записать порядок целиком — результат перетаскивания плитки.
  void setOrder(List<String> keys) {
    state = state.copyWith(order: keys);
    _save();
  }

  void togglePin(String key) {
    final pinned = Set<String>.from(state.pinned);
    if (!pinned.remove(key)) pinned.add(key);
    state = state.copyWith(pinned: pinned);
    _save();
  }
}
