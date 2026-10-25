/// Вид библиотеки: сортировка и фильтр карточек — настройки, а не данные.
///
/// Сами место и закрепление карточки лежат в её строке базы (`side_pos`,
/// `pinned` у плейлистов и подписок), как на ПК, — здесь их только
/// раскладывают. «По умолчанию» — НЕ порядок создания, а пользовательский,
/// собранный перетаскиванием. Закреплённые всегда идут сверху, в каком бы
/// режиме ни был список ([LibOrderState.arrange]).
///
/// Папок в мобилке нет, поэтому видов два: плейлист и артист.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../core/l10n/l10n.dart';
import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../core/store/library_store.dart' show UserPlaylist;

enum LibSort { manual, nameAsc, nameDesc, type }

/// Чем показывать библиотеку: всем подряд, только списками или только
/// артистами.
///
/// Живёт в сторе, а не в состоянии экрана: выбранный чип обязан пережить и уход
/// с вкладки, и перезапуск приложения — иначе фильтр каждый раз сбрасывается на
/// «Все». По той же причине он лежит рядом с сортировкой и порядком: это одна и
/// та же настройка вида библиотеки, и пишется она одной записью.
enum LibFilter { all, playlists, artists }

extension LibFilterMeta on LibFilter {
  String label(AppLocalizations l) => switch (this) {
    LibFilter.all => l.libFilterAll,
    LibFilter.playlists => l.commonPlaylists,
    LibFilter.artists => l.commonArtists,
  };

  /// Идентификатор для диска.
  String get id => switch (this) {
    LibFilter.all => 'all',
    LibFilter.playlists => 'playlists',
    LibFilter.artists => 'artists',
  };
}

LibFilter _filterFromId(Object? id) =>
    LibFilter.values.firstWhere((f) => f.id == id, orElse: () => LibFilter.all);

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

/// Ранг типа для режима «По типу»: сначала плейлисты, потом артисты.
const int kLibRankPlaylist = 0;
const int kLibRankArtist = 1;

class LibOrderState {
  const LibOrderState({
    this.sort = LibSort.manual,
    this.filter = LibFilter.all,
  });

  final LibSort sort;

  final LibFilter filter;

  LibOrderState copyWith({LibSort? sort, LibFilter? filter}) =>
      LibOrderState(sort: sort ?? this.sort, filter: filter ?? this.filter);

  /// Разложить карточки библиотеки по текущему режиму. [name] — по чему
  /// сортировать имена, [rank] — тип (`kLibRank*`), [sidePos] и [pinned] —
  /// место и закрепление из базы.
  ///
  /// Сортировки в Dart нестабильны, поэтому в компараторе последним идёт
  /// сравнение исходных позиций: без него равные имена (или один и тот же
  /// ранг) тасовались бы на каждой перерисовке.
  List<T> arrange<T>(
    List<T> items, {
    required String Function(T) name,
    required int Function(T) rank,
    required int Function(T) sidePos,
    required bool Function(T) pinned,
  }) {
    final indexed = [
      for (var i = 0; i < items.length; i++) (item: items[i], at: i),
    ];

    if (sort == LibSort.manual) {
      indexed.sort((a, b) {
        final byPlace = sidePos(a.item).compareTo(sidePos(b.item));
        return byPlace != 0 ? byPlace : a.at.compareTo(b.at);
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
    return [...sorted.where(pinned), ...sorted.where((e) => !pinned(e))];
  }

  /// Одни плейлисты — в том же порядке, что их плитки в библиотеке.
  List<UserPlaylist> arrangePlaylists(List<UserPlaylist> playlists) => arrange(
    playlists,
    name: (p) => p.name,
    rank: (_) => kLibRankPlaylist,
    sidePos: (p) => p.sidePos,
    pinned: (p) => p.pinned,
  );
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
      filter: _filterFromId(raw['filter']),
    );
  }

  void _save() => ref.read(jsonStoreProvider).write('libOrder', {
    'sort': state.sort.id,
    'filter': state.filter.id,
  });

  void setSort(LibSort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort);
    _save();
  }

  void setFilter(LibFilter filter) {
    if (filter == state.filter) return;
    state = state.copyWith(filter: filter);
    _save();
  }
}
