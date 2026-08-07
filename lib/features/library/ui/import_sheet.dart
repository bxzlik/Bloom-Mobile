/// Импорт по ссылке — порт десктопного `importFromUrl`.
///
/// Ссылка разбирается реестром (`resolveUrlAny`), поэтому экран не знает, чья
/// она: заработает для YTM и Яндекса сразу, как только те появятся.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/library_store.dart';

/// Открыть лист импорта.
Future<void> showImportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImportSheet(),
    );

class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet();

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) _controller.text = text;
  }

  Future<void> _import() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
    });

    try {
      final found = await ref.read(registryProvider).resolveUrlAny(url);
      if (found == null) {
        _finish('Ссылку не удалось разобрать', failed: true);
        return;
      }
      final lib = ref.read(libraryProvider.notifier);

      switch (found.resolved) {
        case ResolvedSet(:final playlist):
          final content = playlist.isAlbum
              ? await found.provider.getAlbum(playlist.id)
              : await found.provider.getPlaylist(playlist.id);
          final tracks = content?.tracks ?? const <Track>[];
          if (tracks.isEmpty) {
            _finish(
              'В этом ${playlist.isAlbum ? 'альбоме' : 'плейлисте'} нет треков',
              failed: true,
            );
            return;
          }
          lib.createPlaylist(
            playlist.title,
            tracks: tracks,
            cover: playlist.cover,
            sourceUrl: playlist.sourceUrl ?? url,
            isAlbum: playlist.isAlbum,
          );
          _finish('Добавлено: ${playlist.title} — ${tracks.length} треков');

        case ResolvedArtist(:final artist):
          final on = lib.toggleFollow(artist);
          _finish(on ? 'Подписка на ${artist.name}' : 'Подписка снята');

        case ResolvedTrack(:final track):
          lib.addTracks([track]);
          _finish('Трек добавлен: ${track.name}');

        case ResolvedProfile(:final profile):
          for (final pl in profile.playlists) {
            lib.createPlaylist(
              pl.title,
              cover: pl.cover,
              sourceUrl: pl.sourceUrl,
              isAlbum: pl.isAlbum,
            );
          }
          lib.addTracks(profile.likes);
          _finish(
            'Профиль импортирован: ${profile.playlists.length} плейлистов',
          );
      }
    } catch (e) {
      _finish(e.toString(), failed: true);
    }
  }

  void _finish(String message, {bool failed = false}) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
      _failed = failed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: t.blockColor,
          border: Border.all(color: t.ovlLine),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(t.radius * 1.4),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Text('Импорт по ссылке', style: theme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Плейлист, альбом, трек или профиль. Площадка определяется сама.',
                style: theme.bodySmall,
              ),
              const SizedBox(height: 16),
              Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: t.pill,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        cursorColor: t.accent,
                        style: theme.titleSmall,
                        onSubmitted: (_) => _import(),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'https://soundcloud.com/…',
                          hintStyle: theme.bodyMedium?.copyWith(color: t.muted),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _paste,
                      child: Icon(
                        SolarIconsOutline.clipboardText,
                        size: 18,
                        color: t.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: theme.bodyMedium?.copyWith(
                    color: _failed ? t.sysFavIco : t.text2,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 46,
                child: Material(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _busy ? null : _import,
                    child: Center(
                      child: _busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: t.accentText,
                              ),
                            )
                          : Text(
                              'Импортировать',
                              style: theme.titleMedium?.copyWith(
                                color: t.accentText,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Перетянуть треки заново во все импортированные плейлисты.
Future<void> refreshImported(BuildContext context, WidgetRef ref) async {
  final lib = ref.read(libraryProvider);
  final targets = lib.playlists.where((p) => p.sourceUrl != null).toList();
  final messenger = ScaffoldMessenger.of(context);

  if (targets.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Импортированных плейлистов нет')),
    );
    return;
  }

  messenger.showSnackBar(
    SnackBar(content: Text('Обновляю ${targets.length}…')),
  );

  final registry = ref.read(registryProvider);
  final controller = ref.read(libraryProvider.notifier);
  var updated = 0;
  for (final pl in targets) {
    try {
      final found = await registry.resolveUrlAny(pl.sourceUrl!);
      if (found == null) continue;
      if (found.resolved case ResolvedSet(playlist: final p)) {
        final content = p.isAlbum
            ? await found.provider.getAlbum(p.id)
            : await found.provider.getPlaylist(p.id);
        final tracks = content?.tracks ?? const <Track>[];
        if (tracks.isEmpty) continue;
        controller.replacePlaylistTracks(pl.id, tracks);
        updated++;
      }
    } catch (_) {
      // Один недоступный плейлист не должен прерывать остальные.
    }
  }

  messenger.showSnackBar(
    SnackBar(content: Text('Обновлено: $updated из ${targets.length}')),
  );
}
