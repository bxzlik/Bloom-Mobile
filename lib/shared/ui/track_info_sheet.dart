/// Track info: what's known beyond title and artist. The artists, each opening
/// their page; album, release date, duration, label, authors, genres; a local
/// file's quality, size and name; the description. Empty fields don't show at
/// all. The row's own data shows at once, the platform's full record or the
/// file's tags fill in when they come. Opens from the actions sheet and should
/// look like its continuation, so the header is the same.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/music_provider.dart';
import '../../features/detail/artists_sheet.dart';
import '../../features/detail/detail_nav.dart';
import '../../features/library/local_tracks.dart';
import '../util/artists.dart';
import '../util/format.dart';
import 'atoms.dart';
import 'bloom_icon.dart';
import 'bloom_sheet.dart';

/// [addedAt] is when the track came into the library: the header is the same as
/// in the actions sheet. The caller reads it: no `ref` comes into the sheet.
Future<void> showTrackInfoSheet(
  BuildContext context,
  Track track, {
  int? addedAt,
}) {
  return showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
      meta: sheetDateMeta(context, context.l.commonAddedOn, addedAt),
    ),
    child: _TrackInfo(track: track),
  );
}

class _TrackInfo extends ConsumerStatefulWidget {
  const _TrackInfo({required this.track});

  final Track track;

  @override
  ConsumerState<_TrackInfo> createState() => _TrackInfoState();
}

class _TrackInfoState extends ConsumerState<_TrackInfo> {
  TrackDetails? _details;
  LocalFileInfo? _file;
  bool _loading = true;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Here, not in initState: the genre names need the language.
    if (_started) return;
    _started = true;
    unawaited(_load(Localizations.localeOf(context).languageCode));
  }

  Future<void> _load(String lang) async {
    final track = widget.track;
    TrackDetails? details;
    LocalFileInfo? file;
    try {
      if (isLocalTrack(track)) {
        file = await localFileInfo(track);
      } else {
        final provider = ref.read(registryProvider).byId(track.source.id);
        if (provider != null && provider.isEnabled) {
          details = await provider.trackDetails(track, lang: lang);
        }
      }
    } catch (_) {
      // No network or the platform said no: the row's own data stands.
    }
    if (!mounted) return;
    setState(() {
      _details = details;
      _file = file;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final track = widget.track;
    final d = _details;
    final f = _file;
    final locale = Localizations.localeOf(context).toString();
    String? text(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

    final album = text(d?.album) ?? text(f?.album) ?? text(track.album);
    final releasedRaw =
        text(d?.released) ?? text(f?.released) ?? text(track.releaseDate);
    // Full release date when the platform knows day and month; with only the
    // year, the row stays Year.
    final released = releaseDateLabel(releasedRaw, locale);
    final year = released == null
        ? (releasedRaw != null && releasedRaw.length >= 4
              ? releasedRaw.substring(0, 4)
              : text(track.year))
        : null;
    // Zero means the platform didn't send it, not a zero-length track.
    final duration = track.duration > Duration.zero
        ? mmss(track.duration)
        : null;
    final label = text(d?.label) ?? text(f?.label) ?? text(track.publisher);
    final authors = (d?.authors.isNotEmpty ?? false)
        ? d!.authors
        : f?.authors ?? const <String>[];
    final genres = (d?.genres.isNotEmpty ?? false)
        ? d!.genres
        : track.genres.isNotEmpty
        ? track.genres
        : [?text(f?.genre)];
    final description = text(d?.description) ?? text(track.description);
    final explicit = (d?.explicit ?? false) || track.explicit;
    final quality = f == null ? null : _quality(l, f, locale);
    final size = switch (track.sourceData?['size']) {
      final num n when n > 0 => formatSize(l, n.toInt()),
      _ => null,
    };
    // A file name only for local tracks; platform ones have none.
    final file = switch (track.sourceData) {
      {'file': final String path} when path.trim().isNotEmpty => path,
      {'name': final String name} when name.trim().isNotEmpty => name,
      _ => null,
    };

    final rows = <Widget>[
      if (text(track.creditedArtist) case final credited?)
        if (credited != track.artist)
          _InfoRow(label: l.tiCredited, value: credited),
      if (album != null) _InfoRow(label: l.tiAlbum, value: album),
      if (released != null)
        _InfoRow(label: l.tiReleased, value: released)
      else if (year != null)
        _InfoRow(label: l.tiYear, value: year),
      if (duration != null) _InfoRow(label: l.tiDuration, value: duration),
      if (label != null) _InfoRow(label: l.tiLabel, value: label),
      if (authors.isNotEmpty)
        _InfoRow(label: l.tiAuthors, value: authors.join(', ')),
      if (genres.isNotEmpty)
        _InfoRow(
          label: l.tiGenres,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final genre in genres)
                  BloomTag(text: genre, active: false),
              ],
            ),
          ),
        ),
      if (quality != null) _InfoRow(label: l.tiQuality, value: quality),
      if (size != null) _InfoRow(label: l.tiSize, value: size),
      if (file != null) _InfoRow(label: l.tiFile, value: file),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Own files have no platform to find their artists on.
        if (track.source != MusicSource.local && artistLinks(track).isNotEmpty)
          TrackArtistRows(
            track: track,
            onPick: (sheet, artist) =>
                openArtist(sheet, artist.id, initial: artist),
          ),
        if (explicit) const _ExplicitMark(),
        if (rows.isNotEmpty) SheetPanel(children: rows),
        if (description != null)
          SheetPanel(
            children: [_InfoRow(label: l.tiDescription, value: description)],
          ),
        if (_loading && rows.isEmpty && description == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: BloomSpinner(size: 20, color: context.bloom.muted),
            ),
          )
        // An empty track is an answer too: saying so in words beats an empty
        // sheet.
        else if (rows.isEmpty && description == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Text(
              l.tiNothing,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
      ],
    );
  }
}

/// "FLAC · 24-bit · 96 kHz", "MP3 · 320 kbps": the depth and rate for lossless,
/// the bitrate for the rest.
String? _quality(AppLocalizations l, LocalFileInfo f, String locale) {
  final codec = f.codec;
  if (codec == null) return null;
  final parts = [codec];
  if (f.lossless) {
    if (f.bits > 0) parts.add(l.tiBits('${f.bits}'));
    if (f.sampleRate > 0) {
      parts.add(
        l.tiKhz(NumberFormat('0.#', locale).format(f.sampleRate / 1000)),
      );
    }
  } else if (f.bitrate > 0) {
    parts.add(l.tiKbps('${(f.bitrate / 1000).round()}'));
  }
  return parts.join(' · ');
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, this.value, this.child});

  final String label;
  final String? value;

  /// Instead of [value].
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.bodySmall),
          const SizedBox(height: 3),
          child ?? Text(value!, style: theme.titleMedium),
        ],
      ),
    );
  }
}

/// The E mark: the only track field with a fact rather than a value, so it's a
/// first row; the header is shared by sheets.
class _ExplicitMark extends StatelessWidget {
  const _ExplicitMark();

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          BloomIcon(Bi.dangerCircle, size: 16, color: t.muted),
          const SizedBox(width: 8),
          Text(
            context.l.tiExplicit,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
