/// Инлайн-режим «Найти дубли»: вместо списка треков — те же треки, но
/// сгруппированные по повторам.
///
/// Порт десктопного `DupsInline`: шапка списка остаётся на месте (это всё ещё
/// тот же плейлист), а сам список подменяется — сверху полоса со счётом и
/// «Удалить все дубли», ниже группы, в каждой первый помечен «оставить», а
/// лишние можно убрать поштучно или группой.
///
/// Убирает режим только из ПЛЕЙЛИСТА: трек уходит из списка, но остаётся в
/// библиотеке. Удаление насквозь — это «Все треки», туда режим не заводят.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../dups.dart';

/// Слайвер с полосой и группами. Живёт внутри `CustomScrollView` треклиста —
/// поэтому не экран, а именно слайвер.
class DupsSliver extends ConsumerWidget {
  const DupsSliver({super.key, required this.listId, required this.tracks});

  /// Плейлист, в котором ищем: из него же и убираем.
  final String listId;

  /// Пул для поиска — состав списка в его собственном порядке.
  final List<Track> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    // Считаем от свежего состава: убрали копию — группа пересобралась, пустые
    // ушли сами (на десктопе это тот же `useMemo` по пулу).
    final groups = dupGroups(tracks, addedAt: lib.inLib);
    final extra = extraDups(groups);

    return SliverList.list(
      children: [
        _Bar(
          groups: groups.length,
          extra: extra.length,
          checked: tracks.length,
          onDeleteAll: extra.isEmpty
              ? null
              : () => removeDups(context, ref, listId, extra),
          onExit: () => ref.read(dupsProvider.notifier).exit(),
        ),
        for (final group in groups)
          _Group(
            group: group,
            onDelete: () =>
                removeDups(context, ref, listId, group.skip(1).toList()),
            onDeleteOne: (track) => removeDups(context, ref, listId, [track]),
          ),
        if (groups.isEmpty) _Empty(checked: tracks.length),
      ],
    );
  }
}

/// Убрать копии из плейлиста — с «Отменить», как и любое другое удаление в
/// списке: снимок библиотеки возвращает и состав, и порядок разом.
void removeDups(
  BuildContext context,
  WidgetRef ref,
  String listId,
  List<Track> extra,
) {
  if (extra.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l;
  final lib = ref.read(libraryProvider.notifier);
  final before = lib.snapshot();

  for (final track in extra) {
    lib.removeTrackFromPlaylist(listId, track.id);
  }
  messenger.toast(
    l.dupsRemoved(extra.length),
    action: ToastAction(fn: () => lib.restoreSnapshot(before)),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.groups,
    required this.extra,
    required this.checked,
    required this.onDeleteAll,
    required this.onExit,
  });

  final int groups;
  final int extra;
  final int checked;
  final VoidCallback? onDeleteAll;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
      child: Row(
        children: [
          Icon(SolarIconsOutline.copy, size: 18, color: t.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l.dupsTitle, style: theme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  groups > 0
                      ? context.l.dupsFound(groups, extra)
                      : context.l.dupsChecked(checked),
                  style: theme.bodySmall,
                ),
              ],
            ),
          ),
          if (onDeleteAll != null)
            _TextButton(
              label: context.l.dupsDelAll,
              danger: true,
              onTap: onDeleteAll!,
            ),
          IconButton(
            onPressed: onExit,
            icon: Icon(SolarIconsOutline.closeCircle, size: 22, color: t.text2),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.onDelete,
    required this.onDeleteOne,
  });

  final List<Track> group;
  final VoidCallback onDelete;
  final ValueChanged<Track> onDeleteOne;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Material(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l.dupsCopies(group.length),
                      style: theme.bodySmall,
                    ),
                  ),
                  _TextButton(
                    label: context.l.dupsDelGroup,
                    danger: true,
                    onTap: onDelete,
                  ),
                ],
              ),
            ),
            for (var i = 0; i < group.length; i++)
              _Row(
                track: group[i],
                keep: i == 0,
                onDelete: () => onDeleteOne(group[i]),
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.track, required this.keep, required this.onDelete});

  final Track track;

  /// Тот, кого предлагается оставить, — первый в группе.
  final bool keep;

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final plays = track.playCount ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: Row(
        children: [
          Cover(url: track.cover, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: keep
                      ? theme.titleSmall?.copyWith(color: t.accent)
                      : theme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  plays > 0
                      ? '${track.artist} · ${context.l.dupsPlays(plays)}'
                      : track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (keep)
            Text(
              context.l.dupsKeep,
              style: theme.bodySmall?.copyWith(color: t.accent),
            )
          else
            IconButton(
              onPressed: onDelete,
              icon: Icon(
                SolarIconsOutline.closeCircle,
                size: 20,
                color: t.sysFavIco,
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.checked});

  final int checked;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      child: Column(
        children: [
          Icon(SolarIconsOutline.checkCircle, size: 30, color: t.accent),
          const SizedBox(height: 10),
          Text(context.l.dupsNone, style: theme.titleMedium),
          const SizedBox(height: 4),
          Text(context.l.dupsChecked(checked), style: theme.bodySmall),
        ],
      ),
    );
  }
}

/// Плоская текстовая кнопка полосы и группы — своя, чтобы не тащить сюда
/// material-кнопку с её палитрой и отступами.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: danger ? t.sysFavIco : t.text,
          ),
        ),
      ),
    );
  }
}
