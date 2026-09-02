/// Подпись списка под названием: «177 треков · 🖫 1/177 · 1ч 23м».
///
/// Одним виджетом, а не тремя кусками по месту, из-за ширины: на плитке
/// библиотеки полная строка не влезает, и счётчик тогда сокращается до голого
/// числа («177 · 🖫 1/177 · 1ч 23м»). Решать это порознь в шапке, на плитке и
/// в шторке — три разных обрезки одной и той же строки.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../features/offline/offline_actions.dart';
import '../../../features/offline/offline_store.dart';
import '../../../shared/util/format.dart';

class ListMeta extends ConsumerWidget {
  const ListMeta({
    super.key,
    required this.tracks,
    this.count,
    this.style,
    this.showCount = true,
    this.showOffline = true,
    this.showDuration = true,
  });

  /// Состав списка: по нему считаются и офлайн-тег, и общее время.
  final List<Track> tracks;

  /// Число треков, если оно берётся не из [tracks] — на плитке счётчик идёт по
  /// составу плейлиста, даже когда сами треки ещё не подняты из библиотеки.
  final int? count;

  /// Стиль подписи. По умолчанию — `bodyMedium` шапки списка; на плитках
  /// подпись мельче, а в шторке она поверх обложки и своего цвета.
  final TextStyle? style;

  /// В «Истории» счётчика нет: список упирается в лимит, и число всегда
  /// показывало бы 200.
  final bool showCount;

  /// Сколько из списка уже на устройстве. Только у своих плейлистов: у «Всех
  /// треков» / «Любимых» / «Истории» на десктопе этого тега нет.
  final bool showOffline;

  /// Общее время. В «Истории» его нет: там не состав списка, а последние
  /// проигранные — сумма по ним ничего не значит.
  final bool showDuration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = this.style ?? Theme.of(context).textTheme.bodyMedium;
    final l = context.l;

    final status = showOffline
        ? listOfflineState(
            ref.watch(offlineProvider),
            ref.read(offlineProvider.notifier),
            tracks,
          )
        : null;
    // Индикатор «доступно офлайн»: скачан целиком — «офлайн», частично —
    // «N/M», ни одного трека нет — тега нет вовсе (порт `PlaylistOfflineTag`).
    final offline = status == null || !status.any
        ? null
        : status.all
        ? l.commonOfflineBadge
        : '${status.cached}/${status.total}';

    final sum = showDuration
        ? tracks.fold(Duration.zero, (acc, x) => acc + x.duration)
        : Duration.zero;
    final duration = sum > Duration.zero ? totalDur(l, sum) : null;

    final iconSize = style?.fontSize ?? 13;
    const iconGap = 3.0;

    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        double width(String text) => (TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout()).width;

        String? counter;
        if (showCount) {
          final n = count ?? tracks.length;
          // Хвост (тег и время) не режется: ради него счётчик и ужимается.
          // Ширина неизвестна (виджет в бесконечном Row) — тогда полная форма,
          // как было до появления времени.
          // Значок не масштабируется вместе с текстом (`applyTextScaling` у
          // `Icon` по умолчанию выключен) — его ширина ровно `iconSize`.
          final tail =
              (offline == null
                  ? 0
                  : width(' · ') + iconSize + iconGap + width(offline)) +
              (duration == null ? 0 : width(' · $duration'));
          final full = l.tracksCount(n);
          counter = !box.maxWidth.isFinite || width(full) + tail <= box.maxWidth
              ? full
              : '$n';
        }

        final parts = <Widget>[];
        void separator() {
          if (parts.isNotEmpty) parts.add(Text(' · ', style: style));
        }

        if (counter != null) {
          // Даже голое число ужимается многоточием, если плитка совсем узкая.
          parts.add(
            Flexible(
              child: Text(
                counter,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          );
        }
        if (offline != null) {
          separator();
          parts.addAll([
            // Та же дискета, что в строке трека и в теге плейлиста на десктопе.
            Icon(
              SolarIconsOutline.diskette,
              size: iconSize,
              color: style?.color,
            ),
            const SizedBox(width: iconGap),
            Text(offline, style: style),
          ]);
        }
        if (duration != null) {
          separator();
          parts.add(Text(duration, style: style));
        }

        // Показывать нечего («История» без счётчика и времени) — строка всё
        // равно занимает свою высоту: в шапке списка она задана снаружи, и
        // выброшенная подпись растянула бы отступ до ряда действий.
        if (parts.isEmpty) return Text(' ', style: style);
        return Row(mainAxisSize: MainAxisSize.min, children: parts);
      },
    );
  }
}
