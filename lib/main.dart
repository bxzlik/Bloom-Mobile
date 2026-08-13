import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme/bloom_theme.dart';
import 'core/store/cover_store.dart';
import 'core/store/json_store.dart';
import 'core/store/library_store.dart';
import 'core/store/settings_store.dart';
import 'core/store/stats_store.dart';
import 'features/library/pl_auto_store.dart';
import 'features/offline/offline_store.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'shared/ui/bloom_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Только портрет. Вся вёрстка считана под узкий экран, и в ландшафте она
  // разъезжается — с этим замком приложение, открытое с телефона на боку,
  // само разворачивается обратно. На Android то же самое стоит в манифесте
  // (там разворот происходит ещё до старта движка), здесь — ради iOS и на
  // случай, если система всё же отдаст активити лежащей.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Хранилище читаем ДО первого кадра: иначе библиотека и тема моргнут
  // пустыми, а экраны придётся городить с состояниями загрузки.
  final store = await JsonStore.open();
  await initCoverStore();
  await initOfflineStore();
  final handler = await AudioService.init(
    builder: BloomAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.bxzlik.bloom.playback',
      androidNotificationChannelName: 'Воспроизведение',
      androidNotificationChannelDescription:
          'Управление музыкой в шторке и на экране блокировки',
      // Пара «ongoing + stopForegroundOnPause» — единственная рабочая: шторку
      // нельзя смахнуть, пока играет, но на паузе она снова смахивается.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      androidNotificationIcon: 'drawable/ic_stat_bloom',
    ),
  );

  // Контейнер создаём руками, чтобы дёрнуть playbackProvider ДО первого кадра:
  // контроллер должен подписаться на хендлер сразу, иначе кнопки в шторке до
  // открытия плеера ведут в никуда.
  final container = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store),
      audioHandlerProvider.overrideWithValue(handler),
    ],
  );
  container.read(playbackProvider);
  // Счётчик времени в приложении — с первой же секунды, как `startUsageTracking`
  // на десктопе. Живёт до конца процесса, снимать его некому и незачем.
  UsageTracker(container.read(statsProvider.notifier)).start();
  // Расписание авто-обновления плейлистов — как `startPlAutoScheduler` на ПК.
  // Таймер живёт столько же, сколько процесс: разбудить закрытое приложение
  // нечем, зато при следующем запуске просроченный период виден по `lastRun`.
  container.read(plAutoProvider.notifier).startScheduler();

  runApp(
    UncontrolledProviderScope(container: container, child: const BloomApp()),
  );
}

class BloomApp extends ConsumerWidget {
  const BloomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(settingsProvider).tokens;
    // Системные бары красим под тему — иначе на светлой теме белые иконки
    // статус-бара исчезают.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: tokens.isLight
            ? Brightness.dark
            : Brightness.light,
        systemNavigationBarColor: tokens.bg,
        systemNavigationBarIconBrightness: tokens.isLight
            ? Brightness.dark
            : Brightness.light,
      ),
    );

    return MaterialApp.router(
      title: 'Bloom',
      debugShowCheckedModeBanner: false,
      // Свой ключ мессенджера: тосты бывают и без экрана — авто-обновление
      // плейлистов ходит по таймеру.
      scaffoldMessengerKey: bloomMessengerKey,
      theme: buildBloomTheme(tokens),
      routerConfig: bloomRouter,
    );
  }
}
