/// A profile's run inside the process: the gate (when there's one to show),
/// the profile's stores, the app over them, and closing it all again to go
/// back to the gate. iOS can't restart an app, so switching profiles happens
/// here on both platforms alike.
library;

import 'dart:async' show TimeoutException, unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/db.dart';
import '../core/l10n/l10n.dart';
import '../core/log/bloom_log.dart';
import '../core/profiles/profiles.dart';
import '../core/store/app_dirs.dart';
import '../core/store/cover_cache.dart';
import '../core/store/cover_store.dart';
import '../core/store/days_store.dart';
import '../core/store/json_store.dart';
import '../core/store/settings_store.dart';
import '../features/lastfm/lastfm_store.dart';
import '../features/library/local_tracks.dart';
import '../features/library/pl_auto_store.dart';
import '../features/lyrics/lyrics_store.dart';
import '../features/offline/offline_store.dart';
import '../features/pc/pc_store.dart';
import '../features/player/audio_handler.dart';
import '../features/player/player_controller.dart';
import '../features/player/session_store.dart';
import '../features/settings/auto_accent.dart';
import '../features/settings/user_fonts.dart';
import '../providers/yandex/ym_auth.dart';
import 'app.dart';
import 'gate.dart';
import 'router.dart';
import 'welcome.dart';

/// What's open of a profile, to close it again.
class _Run {
  _Run(this.container, this.store, this.db, this.usage);

  final ProviderContainer container;
  final JsonStore store;
  final BloomDb db;
  final UsageTracker usage;
}

_Run? _run;

/// A launch, or a return from a profile: the gate if it's needed, then the
/// profile it gives.
Future<void> enterBloom() async {
  final start = Profiles.instance.boot();
  final id = start.gate ? await _gate(start) : start.id!;
  await _openProfile(id);
}

/// The open profile closes and the gate shows: signing out, or deleting it
/// (the profile's files go once they're closed).
Future<void> leaveProfile({bool remove = false}) async {
  final run = _run;
  if (run == null) return;
  _run = null;
  logInfo('profiles', remove ? 'deleting the profile' : 'signing out');
  if (remove) {
    Profiles.instance.remove();
  } else {
    Profiles.instance.signOut();
  }

  final bg = run.container.read(settingsProvider).tokens.bg;
  // Silence first, while the controller can still note what was heard.
  final handler = run.container.read(audioHandlerProvider);
  await handler.stop();
  handler.commands = null;
  run.usage.dispose();

  // The app's tree goes before what it reads: a frame on a disposed container
  // would throw.
  runApp(_Blank(bg));
  await WidgetsBinding.instance.endOfFrame;
  run.container.dispose();
  await run.store.flush();
  run.db.close();
  coverInUse = null;
  resetRouter();
  setOpenProfile(null);

  await enterBloom();
}

/// The gate until it gives a profile to open.
Future<String> _gate(ProfilesStart start) async {
  final look = start.look;
  final store = look == null
      ? JsonStore.memory()
      : await JsonStore.peek('${Profiles.instance.dirOf(look)}/bloom.json');
  final container = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  final id = await runGate(container, start);
  runApp(_Blank(container.read(settingsProvider).tokens.bg));
  await WidgetsBinding.instance.endOfFrame;
  container.dispose();
  return id;
}

Future<void> _openProfile(String id) async {
  setOpenProfile(id);
  logInfo('boot', 'profile $id');
  // The store is read BEFORE the first frame, or the library and theme blink
  // empty and screens need loading states.
  final store = await _step('bloom.json', JsonStore.open);
  // Nothing reads these: they'd sit in the file for good.
  store.removeAll(const ['recentSearches', 'recentItems']);
  // The listener's data: library, play log, follows.
  final db = await _step('bloom.db', BloomDb.open);
  // User fonts before the first frame, or the chosen one flashes as Inter.
  await _step('fonts', () => initUserFonts(store));
  await _step('covers', initCoverStore);
  await _step('cover cache', initCoverCache);
  await _step('offline', initOfflineStore);
  await _step('own tracks', initLocalTracks);

  final handler = await _audioService(store);

  // I create the container by hand to touch playbackProvider BEFORE the first
  // frame: the controller must subscribe to the handler at once, or shade
  // buttons lead nowhere until the player opens.
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      dbProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(handler),
    ],
  );
  container.read(playbackProvider);
  // Kept lyrics past their time go at launch.
  container
      .read(lyricsCacheProvider)
      .start(container.read(lyricsPrefsProvider).keep);
  unawaited(startCoverCache(container.read(coverKeepProvider)));
  // Scrobbles left from the last run go out by themselves.
  container.read(lastfmProvider);
  // The Yandex token comes up right away: until the store exists the platform
  // counts as off and the first search would skip it.
  container.read(ymAuthProvider);
  // The auto accent bridge lives as long as the profile: the colour follows
  // the cover always, not only on one settings page.
  container.read(autoAccentProvider);
  // Today's visit and app time from the first second.
  final usage = UsageTracker(container.read(daysProvider.notifier))..start();
  // Playlist auto-update schedule. Nothing can wake a closed app, but the next
  // launch sees an overdue period by `lastRun`.
  container.read(plAutoProvider.notifier).startScheduler();
  // Sync with the paired computer: at launch, on return and now and then.
  container.read(pcProvider.notifier).start();
  // A picture from another device can be shared by two playlists or a playlist
  // and the profile, so a file goes only when nothing refers to it.
  coverInUse = (cover) {
    if (db.value(
          'SELECT 1 FROM lists WHERE cover = ? UNION ALL SELECT 1 FROM tracks WHERE cover = ? LIMIT 1',
          [cover, cover],
        ) !=
        null) {
      return true;
    }
    final card = db.getMap('profile');
    return card['avatar'] == cover || card['banner'] == cover;
  };
  _run = _Run(container, store, db, usage);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: BloomApp(firstRun: takeFirstRun(db)),
    ),
  );

  // Restoring the last session waits for the first frame: resolving a stream
  // hits the network and asks for notification permission, with no reason to
  // hold an empty screen.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Pairs with every `→` above: launch reached the screen. A log without this
    // line means stuck on the splash, and the last step with no `✓` says where.
    logInfo('boot', '✓ first frame');
    _restoreSession(container);
  });
}

/// A launch step with marks in the log: `→ name` before, `✓ name (N ms)` after.
/// All of launch happens before the first frame, so whatever hangs or throws
/// leaves the user on the splash forever, with nothing on screen to tell. An
/// unclosed `→` shows the place.
Future<T> _step<T>(String name, Future<T> Function() run) async {
  logInfo('boot', '→ $name');
  final started = DateTime.now();
  final result = await run();
  final took = DateTime.now().difference(started).inMilliseconds;
  logInfo('boot', '✓ $name ($took ms)');
  return result;
}

/// How long I wait for the audio service before starting without it. Far above
/// what a live system needs (tens of ms), and below what anyone will watch a
/// splash for.
const Duration _audioInitTimeout = Duration(seconds: 12);

/// One handler per process, shared by every profile that opens in it.
/// [AudioService.init] may answer after I gave up; its `builder` then runs
/// late, and a second [BloomAudioHandler] would mean a second `AudioPlayer`
/// playing on top.
BloomAudioHandler? _audioHandler;
bool _audioTried = false;
BloomAudioHandler _buildAudioHandler() => _audioHandler ??= BloomAudioHandler();

/// Brings up the playback service once a process: shade, lock screen,
/// background music. It has a timeout because the service outlives the app:
/// on the next launch the plugin binds to the running one and waits for
/// `onConnected`. If the system froze it (Samsung is eager), no answer ever
/// comes: `AudioService.init` neither throws nor finishes and the splash stays
/// until a reboot.
///
/// If it fails I start without it: sound plays, with no shade or background
/// playback. Far better than an app that won't open.
Future<BloomAudioHandler> _audioService(JsonStore store) async {
  if (_audioTried) return _buildAudioHandler();
  _audioTried = true;

  // The notification channel is created BEFORE the first frame, so there's no
  // `context.l` yet and I load translations from the delegate directly, in the
  // language the app will show.
  //
  // Android remembers the channel's name at creation: after a language change
  // it updates on the next launch.
  final saved = readSavedLocale(store.readMap('settings'));
  final l10n = await _step(
    'translations',
    () => AppLocalizations.delegate.load(
      saved ??
          basicLocaleListResolution(
            PlatformDispatcher.instance.locales,
            AppLocalizations.supportedLocales,
          ),
    ),
  );
  try {
    return await _step(
      'audio service',
      () => AudioService.init(
        builder: _buildAudioHandler,
        config: AudioServiceConfig(
          androidNotificationChannelId: 'com.bxzlik.bloom.playback',
          androidNotificationChannelName: l10n.notifChannelName,
          androidNotificationChannelDescription: l10n.notifChannelDescription,
          // Only the pair ongoing and stopForegroundOnPause works: the shade
          // can't be swiped while playing, but can on pause.
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'drawable/ic_stat_bloom',
        ),
      ).timeout(_audioInitTimeout),
    );
  } on TimeoutException {
    logError(
      'boot',
      'the audio service did not answer in ${_audioInitTimeout.inSeconds} s: '
          'starting without it (no notification or background play)',
    );
  } catch (e) {
    logError('boot', 'the audio service did not start: starting without it', e);
  }
  return _buildAudioHandler();
}

/// Restores the last session's track, queue and position. Off by default: the
/// system kills the app constantly, and raising the queue silently on every
/// launch isn't my call.
void _restoreSession(ProviderContainer container) {
  final settings = container.read(settingsProvider);
  if (!settings.restoreQueue) return;
  final data = container.read(sessionProvider);
  // A cleared queue doesn't come back into the player.
  if (data == null || data.cleared) return;
  logInfo(
    'player',
    'restoring the session: ${data.track.name} '
        '(${settings.autoplay ? 'playing' : 'paused'})',
  );
  unawaited(
    container
        .read(playbackProvider.notifier)
        .resumeSession(data, autoplay: settings.autoplay),
  );
}

/// Between a profile and the gate, for a frame or two: the theme's
/// background, so nothing blinks.
class _Blank extends StatelessWidget {
  const _Blank(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => ColoredBox(color: color);
}
