/// Страница поиска. Раскладка из референса: круглая «назад», поле-пилюля,
/// круглая кнопка площадки; под ними чипы-фильтры, ниже — выдача секциями.
///
/// О площадках экран не знает: спрашивает [ProviderRegistry.searchAll] и
/// рисует нейтральные сущности. Чипы фильтруют УЖЕ полученную выдачу, а не
/// ходят в сеть заново — провайдер отдаёт все разделы за один прогон.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/music_provider.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/entity_tiles.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../../shared/ui/skeleton.dart';

/// Просвет под чипами-фильтрами: без него ряд чипов слипался с первой строкой
/// выдачи и читался как её часть.
const double _chipsGap = 14;

enum SearchFilter {
  all('Всё', SolarIconsOutline.widget_4),
  tracks('Треки', SolarIconsOutline.musicNote),
  playlists('Плейлисты', SolarIconsOutline.playlistMinimalistic),
  albums('Альбомы', SolarIconsOutline.vinyl),
  artists('Артисты', SolarIconsOutline.user);

  const SearchFilter(this.label, this.icon);

  final String label;
  final IconData icon;
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  SearchFilter _filter = SearchFilter.all;
  SearchResults _results = SearchResults.empty;
  bool _loading = false;
  String? _error;

  /// Был ли уже прогон. Нужен, чтобы отличать «ещё не искали» от «искали и не
  /// нашли»: реестр гасит ошибки провайдеров в пустую выдачу, и без этого
  /// флага неудачный поиск выглядел как нетронутый экран.
  bool _searched = false;

  /// Номер запроса: ответ на устаревший поиск не должен перебить свежий.
  int _generation = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await ref
          .read(registryProvider)
          .searchAll(query, providerId: ref.read(activeProviderIdProvider));
      if (!mounted || gen != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                CircleIconButton(
                  icon: SolarIconsOutline.arrowLeft,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SearchField(
                    controller: _controller,
                    focusNode: _focus,
                    onSubmit: _search,
                    onClear: () => setState(() {
                      _controller.clear();
                      _results = SearchResults.empty;
                      _error = null;
                      _searched = false;
                    }),
                  ),
                ),
                const SizedBox(width: 10),
                const _PlatformButton(),
              ],
            ),
          ),
          _FilterChips(
            active: _filter,
            onPick: (f) => setState(() => _filter = f),
          ),
          const SizedBox(height: _chipsGap),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    // Заготовка вместо полоски прогресса: она сразу занимает высоту будущей
    // выдачи, поэтому при ответе ничего не дёргается. Старые результаты при
    // новом запросе прячем — иначе непонятно, что показано.
    if (_loading) return _SearchSkeleton(filter: _filter);
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: theme.bodyMedium?.copyWith(color: t.sysFavIco),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final text = _searched ? 'Ничего не нашлось' : 'Найди что-нибудь';
      return Center(
        child: Text(text, style: theme.bodyMedium?.copyWith(color: t.muted)),
      );
    }
    return _ResultsView(results: _results, filter: _filter);
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      height: kHeaderControl,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(SolarIconsOutline.magnifier, size: 20, color: t.muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              onSubmitted: (_) => onSubmit(),
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.titleMedium,
              cursorColor: t.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Поиск',
                hintStyle: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: t.muted),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: onClear,
                    child: Icon(
                      SolarIconsOutline.closeCircle,
                      size: 18,
                      color: t.muted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка площадки. Пока зарегистрирован один провайдер, поэтому она просто
/// показывает его логотип; станет переключателем, когда появятся YTM и Яндекс.
class _PlatformButton extends ConsumerWidget {
  const _PlatformButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final registry = ref.watch(registryProvider);
    final activeId = ref.watch(activeProviderIdProvider);
    final provider =
        registry.byId(activeId) ??
        (registry.enabled.isEmpty ? null : registry.enabled.first);

    return Material(
      color: t.pill,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        child: SizedBox(
          width: kHeaderControl,
          height: kHeaderControl,
          child: Center(
            child: provider == null
                ? Icon(SolarIconsOutline.widget_4, size: 22, color: t.iconFg)
                : PlatformLogo(provider.source, size: 22),
          ),
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.active, required this.onPick});

  final SearchFilter active;
  final ValueChanged<SearchFilter> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kChipHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: SearchFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final filter = SearchFilter.values[i];
          return _Chip(
            filter: filter,
            active: filter == active,
            onTap: () => onPick(filter),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.filter,
    required this.active,
    required this.onTap,
  });

  final SearchFilter filter;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    // Активный чип — заливка акцентом с контрастной надписью, как в референсе.
    final fg = active ? t.accentText : t.text2;
    return Material(
      color: active ? t.accent : t.pill,
      borderRadius: BorderRadius.circular(999),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(filter.icon, size: 18, color: fg),
              const SizedBox(width: 8),
              Text(
                filter.label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сколько строк трек-листа показывать в «Всё» — как на референсе.
const int _tracksPreview = 4;

/// Отступы сеток выдачи: поля экрана и просвет между ячейками.
const double _gridPad = 16;
const double _gridGap = 16;

/// Сетка плейлистов/альбомов — две колонки, подпись в две строки под обложкой.
class _SetGrid extends StatelessWidget {
  const _SetGrid({required this.sets});

  final List<Playlist> sets;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap) / 2;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        // Высота ячейки задаётся явно: обложка квадратная плюс две строки
        // подписи. Через childAspectRatio то же самое пришлось бы подбирать
        // на глаз, и на узком экране подпись обрезало бы.
        mainAxisExtent: cell + 48,
      ),
      itemCount: sets.length,
      itemBuilder: (context, i) => SetCard(set: sets[i], size: null),
    );
  }
}

/// Сетка артистов — три колонки кружков с подписью по центру.
class _ArtistGrid extends StatelessWidget {
  const _ArtistGrid({required this.artists});

  final List<Artist> artists;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap * 2) / 3;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + 48,
      ),
      itemCount: artists.length,
      itemBuilder: (context, i) =>
          ArtistCard(artist: artists[i], size: null, centerLabel: true),
    );
  }
}

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.results, required this.filter});

  final SearchResults results;
  final SearchFilter filter;

  bool _shows(SearchFilter section) =>
      filter == SearchFilter.all || filter == section;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;

    // Под своим чипом раздел разворачивается: сеты — в две колонки, артисты —
    // в три, как в референсе. Карусель остаётся только в «Всё», где она нужна,
    // чтобы раздел занимал одну строку.
    // Пустой раздел до сетки не доходит — ниже общее «ничего не нашлось».
    final grid = switch (filter) {
      SearchFilter.playlists when results.playlists.isNotEmpty => _SetGrid(
        sets: results.playlists,
      ),
      SearchFilter.albums when results.albums.isNotEmpty => _SetGrid(
        sets: results.albums,
      ),
      SearchFilter.artists when results.artists.isNotEmpty => _ArtistGrid(
        artists: results.artists,
      ),
      _ => null,
    };
    if (grid != null) return grid;

    // Заголовки нужны только в «Всё»: у одиночного фильтра подпись повторяет
    // имя чипа.
    final titled = filter == SearchFilter.all;
    final tracks = results.tracks;
    // В «Всё» треки идут первыми, поэтому показываем только начало списка:
    // иначе до артистов и плейлистов пришлось бы листать три десятка строк.
    // Весь список — под своим чипом.
    final shownTracks = titled && tracks.length > _tracksPreview
        ? _tracksPreview
        : tracks.length;

    // Порядок секций — из референса: треки, артисты, плейлисты, альбомы.
    final sections = <Widget>[
      if (_shows(SearchFilter.tracks) && tracks.isNotEmpty) ...[
        if (titled) const SectionTitle('Треки'),
        for (var i = 0; i < shownTracks; i++)
          // Очередь — весь список, а не превью: с четвёртой строки
          // проигрывание должно ехать дальше по выдаче.
          TrackRow(track: tracks[i], queue: tracks, index: i),
      ],
      if (_shows(SearchFilter.artists) && results.artists.isNotEmpty) ...[
        if (titled) const SectionTitle('Артисты'),
        EntityCarousel(
          height: 168,
          itemCount: results.artists.length,
          builder: (i) => ArtistCard(artist: results.artists[i]),
        ),
      ],
      if (_shows(SearchFilter.playlists) && results.playlists.isNotEmpty) ...[
        if (titled) const SectionTitle('Плейлисты'),
        EntityCarousel(
          height: 194,
          itemCount: results.playlists.length,
          builder: (i) => SetCard(set: results.playlists[i]),
        ),
      ],
      if (_shows(SearchFilter.albums) && results.albums.isNotEmpty) ...[
        if (titled) const SectionTitle('Альбомы'),
        EntityCarousel(
          height: 194,
          itemCount: results.albums.length,
          builder: (i) => SetCard(set: results.albums[i]),
        ),
      ],
    ];

    if (sections.isEmpty) {
      return Center(
        child: Text(
          'В этом разделе ничего не нашлось',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: t.muted),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      children: sections,
    );
  }
}

/// Заготовка выдачи на время запроса: та же раскладка, что покажет активный
/// чип, поэтому при ответе плашки просто сменяются содержимым.
///
/// Заготовки не листаются: их ровно столько, сколько влезает в экран, и
/// скроллить пустые плашки незачем.
class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton({required this.filter});

  final SearchFilter filter;

  @override
  Widget build(BuildContext context) {
    return SkeletonPulse(
      child: switch (filter) {
        SearchFilter.all => const _AllSkeleton(),
        SearchFilter.tracks => const _TracksSkeleton(count: 9),
        SearchFilter.playlists ||
        SearchFilter.albums => const _GridSkeleton(columns: 2, count: 6),
        SearchFilter.artists => const _GridSkeleton(
          columns: 3,
          count: 9,
          circle: true,
        ),
      },
    );
  }
}

/// Ширины «строк» подписей — по кругу, чтобы плашки не выстраивались в
/// одинаковую линейку.
const List<double> _titleWidths = [0.62, 0.48, 0.71, 0.55];
const List<double> _subWidths = [0.34, 0.42, 0.28, 0.38];

/// Плашка на месте [TrackRow]: те же отступы и обложка 48, поэтому высота
/// строки совпадает с настоящей.
class _TrackRowSkeleton extends StatelessWidget {
  const _TrackRowSkeleton({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          const SkeletonBox(width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  widthFactor: _titleWidths[index % _titleWidths.length],
                  height: 13,
                ),
                const SizedBox(height: 7),
                SkeletonLine(
                  widthFactor: _subWidths[index % _subWidths.length],
                  height: 11,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          const SkeletonBox(width: 30, height: 11, radius: 6),
        ],
      ),
    );
  }
}

class _TracksSkeleton extends StatelessWidget {
  const _TracksSkeleton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, i) => _TrackRowSkeleton(index: i),
    );
  }
}

/// Плашка на месте [SetCard]/[ArtistCard]: обложка на всю ширину ячейки и две
/// строки подписи (у артиста — одна, как и в карточке без счётчика).
class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton({required this.circle, this.width});

  final bool circle;

  /// `null` — на всю ширину ячейки сетки; число — фиксированная ширина
  /// карточки в карусели.
  final double? width;

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, box) => Column(
        crossAxisAlignment: circle
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          SkeletonBox(
            width: box.maxWidth,
            height: box.maxWidth,
            circle: circle,
          ),
          const SizedBox(height: 10),
          SkeletonBox(width: box.maxWidth * (circle ? 0.7 : 0.8), height: 12),
          if (!circle) ...[
            const SizedBox(height: 6),
            SkeletonBox(width: box.maxWidth * 0.5, height: 10),
          ],
        ],
      ),
    );
    return width == null ? content : SizedBox(width: width, child: content);
  }
}

/// Сетка заготовок — геометрия [_SetGrid] и [_ArtistGrid] один в один.
class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({
    required this.columns,
    required this.count,
    this.circle = false,
  });

  final int columns;
  final int count;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cell = (width - _gridPad * 2 - _gridGap * (columns - 1)) / columns;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(_gridPad, 8, _gridPad, 16),
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: _gridGap,
        mainAxisSpacing: 20,
        mainAxisExtent: cell + 48,
      ),
      itemCount: count,
      itemBuilder: (context, _) => _CardSkeleton(circle: circle),
    );
  }
}

/// Заготовка «Всё»: заголовок и превью треков, затем ленты артистов и сетов —
/// тот же порядок секций, что в [_ResultsView].
class _AllSkeleton extends StatelessWidget {
  const _AllSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const _SectionTitleSkeleton(width: 84),
        for (var i = 0; i < _tracksPreview; i++) _TrackRowSkeleton(index: i),
        const _SectionTitleSkeleton(width: 104),
        const _CarouselSkeleton(height: 168, card: 104, circle: true),
        const _SectionTitleSkeleton(width: 128),
        const _CarouselSkeleton(height: 194, card: 132),
      ],
    );
  }
}

/// Плашка на месте [SectionTitle] — с его же отступами.
class _SectionTitleSkeleton extends StatelessWidget {
  const _SectionTitleSkeleton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 10),
      child: SkeletonBox(width: width, height: 18, radius: 9),
    );
  }
}

/// Лента заготовок вместо [EntityCarousel]: карточек ровно столько, чтобы
/// ряд был заполнен до правого края.
class _CarouselSkeleton extends StatelessWidget {
  const _CarouselSkeleton({
    required this.height,
    required this.card,
    this.circle = false,
  });

  final double height;
  final double card;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final count = (width / (card + 12)).ceil();

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, _) => _CardSkeleton(circle: circle, width: card),
      ),
    );
  }
}
