/// Переход к артисту ТРЕКА — с развилкой на нескольких артистов.
///
/// У площадки имя артиста одно строкой («A, B feat. C»), а точный id есть
/// только у аккаунта, который трек залил. Поэтому одного артиста открываем
/// сразу, а нескольких сначала показываем шторкой: остальных приходится искать
/// по имени (как делает `ArtistLinks` на десктопе), и выбрать, к кому идти,
/// может только сам слушатель.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.dart';
import '../../core/entities/entities.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/providers/music_provider.dart';
import '../../shared/ui/atoms.dart';
import '../../shared/ui/bloom_sheet.dart';
import '../../shared/util/artists.dart';
import '../../shared/util/format.dart';
import 'detail_nav.dart';

/// Кого уже искали за этот запуск: «площадка|имя» → найденный артист (null —
/// искали и не нашли). Шторку открывают по одному и тому же треку не раз, и
/// каждый раз ходить в сеть за теми же именами незачем. Промахи по ошибке сети
/// сюда НЕ попадают — их стоит повторить.
final Map<String, Artist?> _memo = {};

/// Открыть артиста играющего трека: одного — сразу, нескольких — через выбор.
///
/// Ничего не делает, если артист один и точного id у трека нет: искать по имени
/// там, где выбирать не из чего, значит уводить наугад.
Future<void> openTrackArtist(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  final names = parseArtists(track.artist);
  if (names.length < 2) {
    final id = track.artistId;
    if (id == null) return;
    return openArtist(
      context,
      id,
      // Шапка страницы рисуется сразу, не дожидаясь сети: имя и аватарку
      // артиста трек уже везёт с собой.
      initial: Artist(
        id: id,
        name: track.artist,
        source: track.source,
        avatar: track.artistAvatar,
        verified: track.artistVerified,
      ),
    );
  }

  final picked = await showBloomSheetChild<Artist>(
    context: context,
    backdrop: track.cover,
    header: SheetLineHeader(
      cover: track.cover,
      title: track.name,
      subtitle: track.artist,
    ),
    child: _ArtistPicker(track: track, names: names),
  );
  // Страницу открываем ПОСЛЕ шторки и от контекста экрана: контекст самой
  // шторки к этому моменту уже отвязан от дерева.
  if (picked == null || !context.mounted) return;
  await openArtist(context, picked.id, initial: picked);
}

/// Список артистов трека: аватар, имя, подписчики. Аватары и id подтягиваются
/// по одному, каждый своим запросом — строка появляется сразу, картинка встаёт
/// на место, когда придёт.
class _ArtistPicker extends ConsumerStatefulWidget {
  const _ArtistPicker({required this.track, required this.names});

  final Track track;
  final List<String> names;

  @override
  ConsumerState<_ArtistPicker> createState() => _ArtistPickerState();
}

class _ArtistPickerState extends ConsumerState<_ArtistPicker> {
  /// Имени нет в карте — ещё ищем; null — искали и не нашли.
  final Map<String, Artist?> _found = {};

  @override
  void initState() {
    super.initState();
    unawaited(_resolve());
  }

  Future<void> _resolve() async {
    final provider = ref.read(registryProvider).byId(widget.track.source.id);
    // Площадки нет (трек из библиотеки, провайдер выключен) — искать негде:
    // в списке останутся имена без аватарок и без перехода.
    if (provider == null) {
      if (mounted) {
        setState(() {
          for (final name in widget.names) {
            _found[name] = null;
          }
        });
      }
      return;
    }
    // Одинаковые имена в строке («A & A») ищем один раз.
    await Future.wait([
      for (final name in widget.names.toSet()) _one(provider, name),
    ]);
  }

  Future<void> _one(MusicProvider provider, String name) async {
    final key = '${widget.track.source.id}|${name.toLowerCase()}';
    Artist? artist;
    if (_memo.containsKey(key)) {
      artist = _memo[key];
    } else {
      try {
        artist = await findArtistByName(provider, name);
        _memo[key] = artist;
      } catch (_) {
        // Сети нет или площадка отказала: строка останется без перехода, но в
        // память промах не пишем — со связью он повторится удачнее.
      }
    }
    if (!mounted) return;
    setState(() => _found[name] = artist);
  }

  @override
  Widget build(BuildContext context) {
    return SheetPanel(
      children: [
        for (final (i, name) in widget.names.indexed) ...[
          if (i > 0) sheetDivider(),
          _row(name),
        ],
      ],
    );
  }

  Widget _row(String name) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final pending = !_found.containsKey(name);
    final artist = _found[name];
    final followers = artist?.followers;

    final String? note = followers != null
        ? '${compactCount(followers)} подписчиков'
        : (pending || artist != null ? null : 'Не нашли у площадки');

    return InkWell(
      // Пока ищем и когда не нашли — идти некуда: строка просто не нажимается.
      onTap: artist == null ? null : () => Navigator.of(context).pop(artist),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Cover(url: artist?.avatar, size: 44, circle: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    // Нашли — показываем имя аккаунта, к которому уйдём: оно
                    // может отличаться от куска строки трека.
                    artist?.name ?? name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.titleMedium?.copyWith(
                      color: artist == null && !pending ? t.muted : t.text,
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (pending)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: t.muted,
                ),
              )
            else if (artist != null)
              Icon(Icons.chevron_right, size: 20, color: t.muted),
          ],
        ),
      ),
    );
  }
}
