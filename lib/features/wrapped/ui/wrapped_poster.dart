/// Постер «Итогов» — порт десктопного `buildWrappedCard.ts`.
///
/// На ПК карточка рисуется на `canvas` и уходит в PNG через `cover_download`.
/// Здесь она СОБРАНА ВИДЖЕТАМИ и снимается [RepaintBoundary] — рисовать то же
/// самое второй раз на `Canvas` пришлось бы вручную (перенос строк, эллипсис,
/// скруглённые обложки), а виджеты это уже умеют.
///
/// Раскладка считается в фиксированном дизайн-боксе [_kPosterW]×[_kPosterH]
/// (те же 420×560, что на ПК) и масштабируется `FittedBox`: снимок тогда не
/// зависит от диагонали телефона, а размеры шрифтов можно брать с десктопа
/// один в один.
library;

import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/bloom_mark.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../periods.dart';
import '../share_image.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import 'wrapped_stories.dart' show coverOfWrappedTrack, periodTitle;

/// Дизайн-бокс постера (3:4, как на ПК — удобно для сторис и чатов).
const double _kPosterW = 420;
const double _kPosterH = 560;

/// Во сколько раз снимок крупнее дизайн-бокса. 3 даёт 1260×1680 — с запасом
/// для любой ленты и без гигантских PNG.
const double kPosterCapture = 3;

class WrappedPosterCard extends ConsumerStatefulWidget {
  const WrappedPosterCard({
    super.key,
    required this.data,
    required this.accent,
  });

  final WrappedData data;
  final Color accent;

  @override
  ConsumerState<WrappedPosterCard> createState() => _WrappedPosterCardState();
}

class _WrappedPosterCardState extends ConsumerState<WrappedPosterCard> {
  final GlobalKey _shot = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final lib = ref.watch(libraryProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: AspectRatio(
            aspectRatio: _kPosterW / _kPosterH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: RepaintBoundary(
                key: _shot,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _kPosterW,
                    height: _kPosterH,
                    child: _Poster(
                      data: widget.data,
                      accent: widget.accent,
                      lib: lib,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ShareButton(
          label: l.wrShareSave,
          busy: _busy,
          onTap: _busy ? null : _share,
        ),
      ],
    );
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final title = periodTitle(l, widget.data.range.kind);
    final dates = periodDatesLabel(widget.data.range, locale);
    var ok = false;
    try {
      // Обложки могли ещё не долететь: в снимок попадает ровно то, что
      // отрисовано, и незагруженная картинка стала бы дыркой в постере.
      await _precacheCovers();
      final png = await _capture();
      if (png != null) {
        ok = await shareImageBytes(
          png,
          filename: 'bloom-wrapped-${periodKey(widget.data.range)}.png',
          text: '$title · $dates',
        );
      }
    } catch (_) {
      // Снимок не удался — ниже покажем тост, ронять историю незачем.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) showToast(context, l.wrShareFail);
  }

  Future<void> _precacheCovers() async {
    final lib = ref.read(libraryProvider);
    for (final tr in widget.data.topTracks) {
      final url = coverOfWrappedTrack(tr, lib);
      final image = url == null ? null : coverImage(url);
      if (image == null || !mounted) continue;
      // Промах не должен рушить отправку: постер переживёт пустую ячейку.
      await precacheImage(image, context, onError: (_, _) {});
    }
  }

  Future<Uint8List?> _capture() async {
    final boundary =
        _shot.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: kPosterCapture);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.label, required this.busy, this.onTap});

  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: busy ? const Color(0x8AFFFFFF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF111111),
                ),
              )
            else
              const Icon(Icons.ios_share, size: 17, color: Color(0xFF111111)),
            const SizedBox(width: 9),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сам постер. Ничего не грузит и не считает — только раскладка, как и
/// десктопный `buildWrappedCard` (строки ему тоже приходят готовыми).
class _Poster extends StatelessWidget {
  const _Poster({required this.data, required this.accent, required this.lib});

  final WrappedData data;
  final Color accent;
  final LibraryState lib;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final tracks = data.topTracks.take(5).toList();

    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF0D0D0D)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Акцентный градиент на верхней половине, затухающий в фон карточки.
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              heightFactor: 0.52,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(
                        accent.withValues(alpha: 0.5),
                        const Color(0xFF0D0D0D),
                      ),
                      const Color(0xFF0D0D0D),
                    ],
                  ),
                ),
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x000D0D0D), Color(0xFF0D0D0D)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BloomMark(size: 17, color: Colors.white, opacity: 0.85),
                    const SizedBox(width: 8),
                    const Text(
                      'BLOOM',
                      style: TextStyle(
                        color: Color(0x99FFFFFF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  periodTitle(l, data.range.kind),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  periodDatesLabel(data.range, locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x8CFFFFFF),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PosterNumber(
                        value: fmtListenTime(l, data.seconds),
                        label: l.wrCardTime,
                      ),
                    ),
                    Expanded(
                      child: _PosterNumber(
                        value: fmtCount(locale, data.plays),
                        label: l.wrPlaysWord(data.plays),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _PosterCaption(l.wrCardTopTracks),
                const SizedBox(height: 10),
                for (var i = 0; i < tracks.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _PosterTrack(
                      index: i,
                      cover: coverOfWrappedTrack(tracks[i], lib),
                      name: tracks[i].name.isEmpty
                          ? l.commonTracks
                          : tracks[i].name,
                      artist: tracks[i].artist,
                    ),
                  ),
                if (data.topArtists.isNotEmpty) ...[
                  const Spacer(),
                  _PosterCaption(l.wrCardTopArtists),
                  const SizedBox(height: 10),
                  // Чипы в одну строку с обрезкой хвоста: на ПК лишние просто
                  // не рисуются, здесь их прячет `clipBehavior`.
                  SizedBox(
                    height: 26,
                    child: Wrap(
                      spacing: 8,
                      clipBehavior: Clip.hardEdge,
                      children: [
                        for (final a in data.topArtists.take(5))
                          _PosterChip(a.name),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PosterNumber extends StatelessWidget {
  const _PosterNumber({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11),
        ),
      ],
    );
  }
}

class _PosterCaption extends StatelessWidget {
  const _PosterCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Color(0x73FFFFFF),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );
}

class _PosterTrack extends StatelessWidget {
  const _PosterTrack({
    required this.index,
    required this.cover,
    required this.name,
    required this.artist,
  });

  final int index;
  final String? cover;
  final String name;
  final String artist;

  @override
  Widget build(BuildContext context) {
    final image = cover == null ? null : coverImage(cover!);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 36,
            height: 36,
            child: image == null
                ? const ColoredBox(color: Color(0x14FFFFFF))
                : Image(
                    image: image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0x14FFFFFF)),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${index + 1}. $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PosterChip extends StatelessWidget {
  const _PosterChip(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0x17FFFFFF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xE6FFFFFF),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
