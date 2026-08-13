/// Вкладка «Статистика» на странице профиля — порт десктопной `StatsSection`.
///
/// Состав блоков десктопный: плитки-показатели, «в среднем за день», разбивка
/// по площадкам, топ треков, график активности (7д / 30д / всё теплокартой) и
/// топ исполнителей. Раскладка мобильная — одна колонка, плитки по две в ряд;
/// на десктопе это широкая сетка в два столбца.
///
/// Копирование сводки и очистка — те же две кнопки в шапке, что на ПК, включая
/// подтверждение очистки вторым нажатием.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../core/store/stats_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../player/player_controller.dart';
import '../achievements.dart';
import '../artist_avatars.dart';
import '../stats.dart';

/// Периоды графика активности.
enum _Period { week, month, all }

class StatsSection extends ConsumerStatefulWidget {
  const StatsSection({super.key});

  @override
  ConsumerState<StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends ConsumerState<StatsSection> {
  _Period _period = _Period.week;

  /// Очистка спрашивает вторым нажатием — своей модалки на ПК тоже нет.
  bool _confirmClear = false;

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
    if (!_confirmClear) {
      setState(() => _confirmClear = true);
      // Само остывает, как таймер на десктопе.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirmClear = false);
      });
      return;
    }
    setState(() => _confirmClear = false);
    ref.read(libraryProvider.notifier).clearHistory();
    ref.read(statsProvider.notifier).clear();
    ref.read(unlockedAchievementsProvider.notifier).clear();
    showToast(context, context.l.statsCleared);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final s = ref.watch(profileStatsProvider);
    final avatars = ref.watch(artistAvatarsProvider);

    // Аватары исполнителей догружаются в фоне и оседают в кеше на 30 дней;
    // из `build` их дёргать нельзя — стор меняет состояние.
    final names = [for (final a in s.topArtists) a.name];
    if (names.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(artistAvatarsProvider.notifier).ensure(names);
      });
    }

    final hoursDay = (s.listenSec / 3600 / s.daySpan).toStringAsFixed(1);
    final tracksDay = (s.totalPlays / s.daySpan).toStringAsFixed(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ToolButton(
              icon: SolarIconsOutline.copy,
              label: context.l.statsCopy,
              onTap: () => _copy(s),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: SolarIconsOutline.trashBinMinimalistic,
              label: _confirmClear
                  ? context.l.statsClearConfirm
                  : context.l.statsClear,
              color: t.sysFavIco,
              onTap: _clear,
            ),
          ],
        ),
        const SizedBox(height: 14),
        // Плитки по две в ряд: на телефоне десктопная лента из восьми штук в
        // строку не живёт.
        _Tiles(stats: s),
        const SizedBox(height: 14),
        _Card(
          title: context.l.statsAvgPerDay,
          icon: SolarIconsOutline.clockCircle,
          child: Row(
            children: [
              Expanded(
                child: _Daily(value: hoursDay, label: context.l.statsHoursDay),
              ),
              Expanded(
                child: _Daily(
                  value: tracksDay,
                  label: context.l.statsTracksDay,
                ),
              ),
              Expanded(
                child: _Daily(
                  value: '${s.uniqueArtists}',
                  label: context.l.statsArtists,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          title: context.l.statsSources,
          icon: SolarIconsOutline.musicNote,
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
        const SizedBox(height: 14),
        _Card(
          title: context.l.statsTopTracks,
          icon: SolarIconsOutline.star,
          child: s.topTracks.isEmpty
              ? _empty(context)
              : Column(
                  children: [
                    for (final (i, row) in s.topTracks.indexed)
                      _TrackRow(
                        index: i,
                        row: row,
                        onTap: () =>
                            ref.read(playbackProvider.notifier).play(row.track),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _Card(
          title: context.l.statsActivity,
          icon: SolarIconsOutline.chart,
          trailing: _PeriodSwitch(
            value: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          child: _period == _Period.all
              ? _Heatmap(log: s.activity)
              : _Bars(log: s.activity, days: _period == _Period.week ? 7 : 30),
        ),
        const SizedBox(height: 14),
        _Card(
          title: context.l.statsTopArtists,
          icon: SolarIconsOutline.user,
          child: s.topArtists.isEmpty
              ? _empty(context)
              : Column(
                  children: [
                    for (final (i, a) in s.topArtists.indexed)
                      _ArtistRow(
                        index: i,
                        row: a,
                        // Настоящий аватар, если площадка его уже отдала;
                        // пока нет — обложка его лучшего трека.
                        avatar: avatars[a.name.toLowerCase()] ?? a.cover,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        // Честно говорим, откуда взялись цифры: журнал ведётся с первого
        // прослушивания, за прошлое данных нет.
        Text(
          context.l.statsFootnote,
          textAlign: TextAlign.center,
          style: theme.bodySmall?.copyWith(color: t.muted),
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

/// Восемь показателей плитками — десктопные `.stat-hero-card`.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.stats});

  final ProfileStats stats;

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final tiles = <({IconData icon, String value, String label})>[
      (
        icon: SolarIconsOutline.musicNote,
        value: '${s.libraryTracks}',
        label: context.l.statsTracks,
      ),
      (
        icon: SolarIconsOutline.play,
        value: '${s.totalPlays}',
        label: context.l.statsPlays,
      ),
      (
        icon: SolarIconsOutline.clockCircle,
        value: fmtDurLong(context, s.listenSec),
        label: context.l.statsTime,
      ),
      (
        icon: SolarIconsOutline.stars,
        value: '${s.uniqueTracks}',
        label: context.l.statsUnique,
      ),
      (
        icon: SolarIconsOutline.chart,
        value: fmtClock(s.avgSec),
        label: context.l.statsAvgLength,
      ),
      (
        icon: SolarIconsOutline.user,
        value: s.favArtist ?? '—',
        label: context.l.statsFavArtist,
      ),
      (
        icon: SolarIconsOutline.stopwatch,
        value: fmtDurLong(context, s.appSec),
        label: context.l.statsAppTime,
      ),
      (
        icon: SolarIconsOutline.medalStar,
        value: '${s.recordDay}',
        label: context.l.statsRecordDay,
      ),
    ];

    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final width = (box.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: width,
                child: _Tile(
                  icon: tile.icon,
                  value: tile.value,
                  label: tile.label,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: t.iconFg),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleLarge?.copyWith(fontSize: 19),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.bodySmall?.copyWith(color: t.muted),
          ),
        ],
      ),
    );
  }
}

/// Плашка раздела статистики: заголовок с иконкой и содержимое.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: t.iconFg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _Daily extends StatelessWidget {
  const _Daily({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(value, style: theme.titleLarge?.copyWith(fontSize: 20)),
        const SizedBox(height: 2),
        Text(
          label,
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
                Icon(SolarIconsOutline.folder, size: 15, color: t.iconFg)
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

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.row,
    required this.onTap,
  });

  final int index;
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
            SizedBox(
              width: 20,
              child: Text(
                '${index + 1}',
                style: theme.bodySmall?.copyWith(color: t.muted),
              ),
            ),
            Cover(url: row.track.cover, size: 38),
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
              context.l.playsCount(row.plays),
              style: theme.bodySmall?.copyWith(color: t.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.index,
    required this.row,
    required this.avatar,
  });

  final int index;
  final ArtistPlays row;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              style: theme.bodySmall?.copyWith(color: t.muted),
            ),
          ),
          Cover(url: avatar, size: 34, circle: true),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.titleSmall,
            ),
          ),
          Text(
            '${row.plays}',
            style: theme.bodySmall?.copyWith(color: t.muted),
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
        color: t.bg,
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
      final date = today.subtract(Duration(days: i));
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
                              today.subtract(Duration(days: w * 7 + (dow - d))),
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

/// Кнопка в шапке статистики — «Скопировать» и «Очистить».
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Expanded(
      child: Material(
        color: t.pill,
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color ?? t.iconFg),
                const SizedBox(width: 8),
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
