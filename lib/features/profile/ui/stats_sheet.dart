/// Шторка «Статистика» — то, что раньше было вкладкой на странице профиля.
///
/// Раскладку задал скриншот чужого приложения: сверху лента любимых артистов
/// (кружки, листаются вбок), под ней топ треков, а всё остальное собрано в
/// «Обзор» — сетку цифр с тонкими линиями между рядами. Наши блоки, которых в
/// том макете нет, — «Где слушали чаще» и «Активность» — идут следом: их не
/// уложить в сетку цифр, это графики.
///
/// Цифры и расчёты прежние, десктопные (см. [ProfileStats]); поменялась только
/// подача. Копирование сводки и очистка — те же две кнопки, что были в шапке
/// вкладки, теперь в самом низу шторки.
///
/// Плашки собраны на [sheetPanelColor], а не на `GlassBox`: внутри шторки
/// заливка зависит от того, на чём та стоит (см. `bloom_sheet.dart`).
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/providers/artist_lookup.dart';
import '../../../core/store/days_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../detail/detail_nav.dart';
import '../../player/player_controller.dart';
import '../../wrapped/periods.dart';
import '../../wrapped/ui/wrapped_sheet.dart';
import '../../wrapped/wrapped_store.dart';
import '../artist_avatars.dart';
import '../level.dart';
import '../stats.dart';

/// Открыть статистику. Обложки у шторки нет — фоном встаёт [SheetSurface].
Future<void> showStatsSheet(BuildContext context) =>
    showBloomSheetChild<void>(context: context, child: const StatsSheet());

/// Периоды графика активности.
enum _Period { week, month, all }

class StatsSheet extends ConsumerStatefulWidget {
  const StatsSheet({super.key});

  @override
  ConsumerState<StatsSheet> createState() => _StatsSheetState();
}

class _StatsSheetState extends ConsumerState<StatsSheet> {
  _Period _period = _Period.week;

  /// Очистка спрашивает тут же, над кнопками, — как на ПК: что удалится и
  /// сбросить ли заодно уровень.
  bool _asking = false;
  bool _resetLevel = false;

  void _copy(ProfileStats s) {
    final l = context.l;
    final lines = <String>[
      l.statsShareTitle,
      '',
      l.statsShareTracks(s.libraryTracks),
      l.statsShareUnique(s.uniqueTracks),
      l.statsSharePlays(s.totalPlays),
      l.statsShareTime(fmtDurLong(context, s.listenSec)),
      l.statsShareAvgLength(fmtClock(s.avgSec)),
      l.statsShareAppTime(fmtDurLong(context, s.appSec)),
      if (s.favArtist != null) l.statsShareFavArtist(s.favArtist!),
      if (s.recordDay > 0) l.statsShareRecordDay(s.recordDay),
      '',
      l.statsShareAvgPerDay,
      '  ${(s.listenSec / 3600 / s.daySpan).toStringAsFixed(1)} ${l.statsHoursDay} · '
          '${(s.totalPlays / s.daySpan).toStringAsFixed(1)} ${l.statsTracksDay} · '
          '${s.uniqueArtists} ${l.statsArtists}',
      if (s.bySource.isNotEmpty) ...[
        '',
        l.statsShareSources,
        for (final (i, src) in s.bySource.take(5).indexed)
          '  ${i + 1}. ${src.source.label10n(l)} — ${src.plays} '
              '(${s.totalPlays > 0 ? (src.plays / s.totalPlays * 100).round() : 0}%)',
      ],
      if (s.topTracks.isNotEmpty) ...[
        '',
        l.statsShareTopTracks,
        for (final (i, row) in s.topTracks.take(5).indexed)
          '  ${i + 1}. ${row.track.name}'
              '${row.track.artist.isEmpty ? '' : ' — ${row.track.artist}'} '
              '(${l.playsCount(row.plays)})',
      ],
      if (s.topArtists.isNotEmpty) ...[
        '',
        l.statsShareTopArtists,
        for (final (i, a) in s.topArtists.take(5).indexed)
          '  ${i + 1}. ${a.name} (${a.plays})',
      ],
      '',
      '— Bloom',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    showToast(context, l.statsCopied, kind: ToastKind.success);
  }

  void _clear() {
    if (!_asking) {
      setState(() {
        _resetLevel = false;
        _asking = true;
      });
      return;
    }
    setState(() => _asking = false);
    ref.read(statsClearProvider.notifier).clear(keepLevel: !_resetLevel);
    showToast(context, context.l.statsCleared, kind: ToastKind.success);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final s = ref.watch(profileStatsProvider);
    final avatars = ref.watch(artistAvatarsProvider);
    final wrappedMonth = ref.watch(wrappedEntriesProvider).month;

    // Аватары исполнителей догружаются в фоне и оседают в кеше на 30 дней;
    // из `build` их дёргать нельзя — стор меняет состояние. Каждый ищется у
    // своей площадки — той, где его слушали.
    final refs = [
      for (final a in s.topArtists) (name: a.name, source: a.source),
    ];
    if (refs.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(artistAvatarsProvider.notifier).ensure(refs);
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        _Section(
          title: context.l.statsFavArtists,
          // Лента листается от края до края: боковой отступ живёт внутри
          // списка, иначе крайние кружки обрезались бы на прокрутке.
          padded: false,
          child: s.topArtists.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _empty(context),
                )
              : _ArtistStrip(rows: s.topArtists, avatars: avatars),
        ),
        _Section(
          title: context.l.statsTopTracks,
          child: s.topTracks.isEmpty
              ? _empty(context)
              : Column(
                  children: [
                    for (final row in s.topTracks)
                      _TrackRow(
                        row: row,
                        onTap: () =>
                            ref.read(playbackProvider.notifier).play(row.track),
                      ),
                  ],
                ),
        ),
        // Единственный блок с плашкой — сетка цифр: без неё ряды разъезжались
        // бы по фону шторки, а линии между ними висели в воздухе.
        _Section(
          title: context.l.statsOverview,
          padded: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: sheetPanelColor(context),
              borderRadius: BorderRadius.circular(t.radius),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: _Overview(stats: s),
              ),
            ),
          ),
        ),
        _Section(
          title: context.l.statsSources,
          child: s.bySource.isEmpty
              ? _empty(context)
              : Column(
                  children: [
                    for (final src in s.bySource)
                      _SourceRow(
                        row: src,
                        total: s.totalPlays,
                        max: s.bySource.first.plays,
                      ),
                  ],
                ),
        ),
        _Section(
          title: context.l.statsActivity,
          trailing: _PeriodSwitch(
            value: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          child: _period == _Period.all
              ? _Heatmap(log: s.activity)
              : _Bars(log: s.activity, days: _period == _Period.week ? 7 : 30),
        ),
        // Постоянный вход в итоги месяца — единственная «положительная» кнопка
        // футера, поэтому она отдельной строкой и с акцентной заливкой.
        // Подмена карточки статистики гаснет после первого просмотра, а
        // пересматривают итоги отсюда.
        if (_asking)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l.statsClearTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  context.l.statsClearSub,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: t.text2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.l.statsClearLevel,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: t.text),
                      ),
                    ),
                    BloomSwitch(
                      value: _resetLevel,
                      onChanged: (v) => setState(() => _resetLevel = v),
                    ),
                  ],
                ),
              ],
            ),
          )
        else if (wrappedMonth != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                _ToolButton(
                  icon: Bi.cup,
                  label: context.l.wrMonth,
                  color: t.accent,
                  background: t.accent.withValues(alpha: 0.12),
                  onTap: () {
                    // Шторку закрываем ДО открытия: итоги — своя шторка, и
                    // вешать её поверх этой нельзя.
                    Navigator.of(context).pop();
                    showWrappedSheet(
                      context,
                      period: PeriodKind.month,
                      data: wrappedMonth,
                    );
                  },
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
          child: Row(
            children: [
              _ToolButton(
                icon: _asking ? null : Bi.copy,
                label: _asking ? context.l.commonCancel : context.l.statsCopy,
                onTap: _asking
                    ? () => setState(() => _asking = false)
                    : () => _copy(s),
              ),
              const SizedBox(width: 8),
              _ToolButton(
                icon: Bi.trashBinMinimalistic,
                label: context.l.statsClear,
                color: t.danger,
                onTap: _clear,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      context.l.statsNoDataYet,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: context.bloom.muted),
    ),
  );
}

/// Раздел шторки: крупный заголовок БЕЗ плашки и без иконки — как в макете, —
/// а под ним содержимое прямо на фоне шторки. Своя подложка есть только у
/// «Обзора», и заводит её он сам.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing,
    this.padded = true,
  });

  final String title;
  final Widget child;

  /// Справа от заголовка — переключатель периода у «Активности».
  final Widget? trailing;

  /// Содержимое с боковыми полями. Ленте артистов и «Обзору» они не нужны:
  /// первая листается от края до края, у второго свои.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (padded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: child,
            )
          else
            child,
        ],
      ),
    );
  }
}

/// Лента любимых артистов: кружок, имя, прослушивания. Листается вбок.
///
/// Тап открывает страницу артиста — как клик по строке топа на десктопе. В
/// истории от артиста остаётся одно имя, поэтому id приходится искать у
/// площадки; спрашиваем ту же, что отдаёт аватарки для этого топа.
class _ArtistStrip extends ConsumerStatefulWidget {
  const _ArtistStrip({required this.rows, required this.avatars});

  final List<ArtistPlays> rows;
  final Map<String, String?> avatars;

  /// Сторона кружка. Подпись под ним шире него самого — иначе имена в два
  /// слова обрезаются на первом же.
  static const double avatar = 64;
  static const double item = 78;

  @override
  ConsumerState<_ArtistStrip> createState() => _ArtistStripState();
}

class _ArtistStripState extends ConsumerState<_ArtistStrip> {
  /// Кого сейчас ищем у площадки: на его кружке крутится ожидание, и второй
  /// тап в это время не проходит.
  String? _busy;

  Future<void> _open(ArtistPlays row) async {
    if (_busy != null) return;
    setState(() => _busy = row.name);

    Artist? artist;
    try {
      // Ищем у ТОЙ площадки, где его слушали: аккаунт с тем же именем на
      // соседней — другой человек.
      final provider = ref.read(registryProvider).byId(row.source.id);
      artist = provider == null
          ? null
          : await findArtistCached(provider, row.name);
    } catch (_) {
      // Сети нет или площадка отказала — ответ тот же, что и «не нашли»:
      // идти всё равно некуда.
    }
    if (!mounted) return;
    setState(() => _busy = null);

    if (artist == null) {
      showToast(context, context.l.artistNotFound);
      return;
    }
    // Шторку не закрываем руками: страница ложится в навигатор вкладки, а всё,
    // что лежит поверх каркаса, при этом схлопывается само (см. `_target` в
    // `detail_nav.dart`).
    await openArtist(context, artist.id, initial: artist);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return SizedBox(
      height: _ArtistStrip.avatar + 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: widget.rows.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final row = widget.rows[i];
          final busy = _busy == row.name;
          // Слушали только свои файлы — идти некуда: кружок просто не
          // нажимается (так же ведут себя строки в выборе артистов трека).
          final local = row.source == MusicSource.local;
          return SizedBox(
            width: _ArtistStrip.item,
            child: InkWell(
              onTap: local ? null : () => _open(row),
              borderRadius: BorderRadius.circular(t.radius),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Настоящий аватар, если площадка его уже отдала; пока
                      // нет — обложка его лучшего трека.
                      Cover(
                        url:
                            widget.avatars[artistAvatarKey(
                              row.source,
                              row.name,
                            )] ??
                            row.cover,
                        size: _ArtistStrip.avatar,
                        circle: true,
                      ),
                      if (busy)
                        Container(
                          width: _ArtistStrip.avatar,
                          height: _ArtistStrip.avatar,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    row.name,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${row.plays}',
                    maxLines: 1,
                    style: theme.bodySmall?.copyWith(color: t.muted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Строка топа: обложка, название с артистом, число прослушиваний справа.
class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.row, required this.onTap});

  final TrackPlays row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(t.radius * 0.6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Cover(url: row.track.cover, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleSmall,
                  ),
                  Text(
                    row.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.bodySmall?.copyWith(color: t.text2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${row.plays}',
              style: theme.bodySmall?.copyWith(color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Обзор» — все остальные цифры профиля сеткой: ряды по три и по две ячейки,
/// между рядами тонкая линия.
class _Overview extends StatelessWidget {
  const _Overview({required this.stats});

  final ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final l = context.l;
    final rows = <List<({String value, String label})>>[
      [
        (value: '${s.totalPlays}', label: l.statsPlays),
        (value: '${s.libraryTracks}', label: l.statsTracks),
        (value: fmtDurLong(context, s.listenSec), label: l.statsTime),
      ],
      [
        (value: '${s.uniqueTracks}', label: l.statsUnique),
        (value: fmtClock(s.avgSec), label: l.statsAvgLength),
        (value: '${s.recordDay}', label: l.statsRecordDay),
      ],
      [
        (value: fmtDurLong(context, s.appSec), label: l.statsAppTime),
        (value: '${s.uniqueArtists}', label: l.statsArtists),
      ],
      [
        (
          value: (s.listenSec / 3600 / s.daySpan).toStringAsFixed(1),
          label: l.statsHoursDay,
        ),
        (
          value: (s.totalPlays / s.daySpan).toStringAsFixed(1),
          label: l.statsTracksDay,
        ),
      ],
      [(value: s.favArtist ?? '—', label: l.statsFavArtist)],
    ];

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 21, thickness: 1, color: sheetLineColor(context)),
          Row(
            children: [
              for (final cell in rows[i])
                Expanded(
                  child: _Cell(value: cell.value, label: cell.label),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.titleLarge?.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.bodySmall?.copyWith(color: context.bloom.muted),
        ),
      ],
    );
  }
}

/// Строка площадки: знак, доля, полоска.
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.row, required this.total, required this.max});

  final SourcePlays row;
  final int total;
  final int max;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final color = platformColor[row.source] ?? t.accent;
    final percent = total > 0 ? (row.plays / total * 100).round() : 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (row.source == MusicSource.local)
                BloomIcon(Bi.folder, size: 15, color: t.iconFg)
              else
                PlatformLogo(row.source, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  row.source == MusicSource.local
                      ? context.l.statsLocalFiles
                      : row.source.label10n(context.l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.titleSmall,
                ),
              ),
              Text('$percent%', style: theme.titleSmall),
              const SizedBox(width: 8),
              Text(
                '${row.plays} · ${fmtDurLong(context, row.seconds)}',
                style: theme.bodySmall?.copyWith(color: t.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: max > 0 ? row.plays / max : 0,
              minHeight: 5,
              backgroundColor: t.track,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSwitch extends StatelessWidget {
  const _PeriodSwitch({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  static final _labels = <_Period, String Function(AppLocalizations)>{
    _Period.week: (AppLocalizations l) => l.statsPeriod7d,
    _Period.month: (AppLocalizations l) => l.statsPeriod30d,
    _Period.all: (AppLocalizations l) => l.statsPeriodAll,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        // Подложка переключателя — та же линия, что делит ряды: сплошной фон
        // темы на плашке шторки читался бы дырой.
        color: sheetLineColor(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in _labels.entries)
            GestureDetector(
              onTap: () => onChanged(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: entry.key == value ? t.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  entry.value(context.l),
                  style: theme.bodySmall?.copyWith(
                    color: entry.key == value ? t.accentText : t.text2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Столбики за последние N дней.
class _Bars extends StatelessWidget {
  const _Bars({required this.log, required this.days});

  final Map<String, int> log;
  final int days;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final today = DateTime.now();

    final bars = <({String label, int count, bool today})>[];
    for (var i = days - 1; i >= 0; i--) {
      // Календарный день, а не −24 ч·i: на переходе на летнее время сутки
      // бывают в 23 и 25 часов, и после полуночи шаг перескочил бы день.
      final date = DateTime(today.year, today.month, today.day - i);
      final label = days == 7
          // Сокращения дней недели знает `intl` — своей таблицы не держим.
          ? (i == 0
                ? context.l.statsToday
                : DateFormat.E(
                    Localizations.localeOf(context).languageCode,
                  ).format(date))
          : (i == 0 || i % 7 == 0 ? '${date.day}.${date.month}' : '');
      bars.add((label: label, count: log[dayKey(date)] ?? 0, today: i == 0));
    }
    final max = bars.fold(1, (m, b) => b.count > m ? b.count : m);

    return SizedBox(
      height: 74,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in bars)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: (bar.count / max * 46).clamp(3, 46),
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: bar.today
                          ? t.accent
                          : t.text.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 14,
                    child: FittedBox(
                      child: Text(
                        bar.label,
                        style: theme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: bar.today ? t.text : t.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Теплокарта за год — десктопный `.act-heatmap`, только колонок столько,
/// сколько влезло в ширину экрана.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.log});

  final Map<String, int> log;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final today = DateTime.now();
    final max = log.values.fold(1, (m, v) => v > m ? v : m);
    // Понедельник — верхняя строка, как на десктопе.
    final dow = today.weekday - 1;

    return LayoutBuilder(
      builder: (context, box) {
        const cell = 11.0;
        const gap = 3.0;
        final weeks = ((box.maxWidth + gap) / (cell + gap)).floor().clamp(
          4,
          53,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var w = weeks - 1; w >= 0; w--)
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Column(
                      children: [
                        for (var d = 0; d < 7; d++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: _cell(
                              t,
                              DateTime(
                                today.year,
                                today.month,
                                today.day - (w * 7 + (dow - d)),
                              ),
                              max,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  context.l.statsLess,
                  style: theme.bodySmall?.copyWith(
                    color: t.muted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 6),
                for (final level in [0.0, 0.25, 0.5, 0.75, 1.0])
                  Padding(
                    padding: const EdgeInsets.only(right: gap),
                    child: Container(
                      width: cell,
                      height: cell,
                      decoration: BoxDecoration(
                        color: _levelColor(t, level),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                const SizedBox(width: 2),
                Text(
                  context.l.statsMore,
                  style: theme.bodySmall?.copyWith(
                    color: t.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _cell(BloomTokens t, DateTime date, int max) {
    final future = date.isAfter(DateTime.now());
    final count = log[dayKey(date)] ?? 0;
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: future
            ? Colors.transparent
            : _levelColor(t, count == 0 ? 0 : count / max),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Color _levelColor(BloomTokens t, double ratio) {
    if (ratio <= 0) return t.track;
    final step = ratio >= 0.75
        ? 1.0
        : ratio >= 0.5
        ? 0.72
        : ratio >= 0.25
        ? 0.48
        : 0.26;
    return t.accent.withValues(alpha: step);
  }
}

/// Кнопка внизу шторки — «Скопировать», «Очистить» и вход в итоги месяца.
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.background,
  });

  /// `null` — одна надпись («Отмена» в подтверждении очистки).
  final BloomGlyph? icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  /// Своя заливка — у входа в итоги: он единственный здесь не нейтральный.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Expanded(
      child: Material(
        color: background ?? sheetPanelColor(context),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  BloomIcon(icon, size: 16, color: color ?? t.iconFg),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: color ?? t.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
