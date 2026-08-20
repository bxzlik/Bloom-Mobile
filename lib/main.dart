import 'dart:async' show unawaited;
import 'dart:ui' show PlatformDispatcher;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme/bloom_theme.dart';
import 'core/l10n/l10n.dart';
import 'core/log/bloom_log.dart';
import 'core/store/cover_store.dart';
import 'core/store/json_store.dart';
import 'core/store/library_store.dart';
import 'core/store/settings_store.dart';
import 'core/store/stats_store.dart';
import 'features/customization/ui/app_background.dart';
import 'features/library/local_tracks.dart';
import 'features/library/pl_auto_store.dart';
import 'features/lyrics/lyrics_cache.dart';
import 'features/lyrics/lyrics_store.dart';
import 'features/offline/offline_store.dart';
import 'features/onboarding/onboarding_store.dart';
import 'features/player/audio_handler.dart';
import 'features/player/player_controller.dart';
import 'features/player/resume_store.dart';
import 'features/settings/auto_accent.dart';
import 'features/wrapped/play_log.dart';
import 'providers/yandex/ym_auth.dart';
import 'shared/ui/bloom_toast.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Только портрет. Вся вёрстка считана под узкий экран, и в ландшафте она
  // разъезжается — с этим замком приложение, открытое с телефона на боку,
  // само разворачивается обратно. На Android то же самое стоит в манифесте
  // (там разворот происходит ещё до старта движка), здесь — ради iOS и на
  // случай, если система всё же отдаст активити лежащей.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Журнал работы поднимаем первым — чтобы в него попало и то, что случится с
  // остальными хранилищами (`Настройки → Система → Логи`).
  await BloomLog.instance.open();
  _catchUnhandled();
  logInfo('app', 'запуск');
  // Хранилище читаем ДО первого кадра: иначе библиотека и тема моргнут
  // пустыми, а экраны придётся городить с состояниями загрузки.
  final store = await JsonStore.open();
  // Журнал прослушиваний «Итогов» — СВОЙ файл: `bloom.json` переписывается
  // целиком, и десятки тысяч событий гонялись бы через кодировщик на каждый
  // лайк (см. шапку `play_log.dart`).
  final plays = await JsonStore.open(name: 'plays.json');
  await initCoverStore();
  await initOfflineStore();
  await initLocalTracks();
  // Кеш текстов песен — свой каталог с файлами, а не запись в `bloom.json`:
  // текст весит килобайтами, и класть его в файл библиотеки значило бы
  // переписывать её целиком на каждую найденную песню.
  final lyricsCache = await openLyricsCache();

  // Канал уведомлений заводится ДО первого кадра, поэтому `context.l` тут ещё
  // неоткуда взять — переводы грузим напрямую из делегата. Язык тот же, что
  // потом увидит приложение: сохранённый, а если не выбирали — системный.
  //
  // Название канала Android запоминает при создании и позже само не меняет:
  // после смены языка в настройках оно обновится со следующего запуска.
  final saved = readSavedLocale(store.readMap('settings'));
  final l10n = await AppLocalizations.delegate.load(
    saved ??
        basicLocaleListResolution(
          PlatformDispatcher.instance.locales,
          AppLocalizations.supportedLocales,
        ),
  );

  final handler = await AudioService.init(
    builder: BloomAudioHandler.new,
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.bxzlik.bloom.playback',
      androidNotificationChannelName: l10n.notifChannelName,
      androidNotificationChannelDescription: l10n.notifChannelDescription,
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
      playLogStoreProvider.overrideWithValue(plays),
      audioHandlerProvider.overrideWithValue(handler),
      lyricsCacheProvider.overrideWithValue(lyricsCache),
    ],
  );
  container.read(playbackProvider);
  // Пройден ли онбординг — ДО первого маршрута: `redirect` роутера смотрит на
  // флаг, который выставляет этот провайдер, и опоздание показало бы главную
  // на долю секунды раньше мастера.
  container.read(onboardedProvider);
  // Токен Яндекса поднимаем сразу: пока стор не создан, площадка считается
  // выключенной и первый же поиск прошёл бы мимо неё.
  container.read(ymAuthProvider);
  // Мост авто-акцента живёт столько же, сколько процесс: цвет должен ехать за
  // обложкой всегда, а не только пока открыт экран «Интерфейс».
  container.read(autoAccentProvider);
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

  // Восстановление прошлой сессии — после первого кадра: резолв стрима идёт в
  // сеть и просит разрешение на уведомления, и держать ради этого пустой экран
  // незачем.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => _restoreSession(container),
  );
}

/// Необработанные ошибки — в журнал работы.
///
/// Обе двери: `FlutterError.onError` ловит падения в дереве виджетов,
/// `PlatformDispatcher.onError` — всё остальное (оборванные `Future`).
/// Поведение по умолчанию сохраняем: ошибка как печаталась в консоль, так и
/// печатается, журнал только запоминает её.
void _catchUnhandled() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('flutter', details.exceptionAsString(), details.stack?.toString());
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('dart', '$error', stack);
    return false; // false — пусть платформа обработает её как обычно
  };
}

/// Вернуть трек, очередь и позицию прошлой сессии — «Настройки → Аудио».
///
/// Выключено по умолчанию: телефон приложение убивает постоянно, и молча
/// поднимать очередь на каждом запуске мы не вправе. Карточка «Продолжить» на
/// главной работает и без этой настройки — просто по нажатию.
void _restoreSession(ProviderContainer container) {
  final settings = container.read(settingsProvider);
  if (!settings.restoreQueue) return;
  final data = container.read(resumeProvider);
  if (data == null) return;
  logInfo(
    'player',
    'восстанавливаю сессию: ${data.track.name} '
        '(${settings.autoplay ? 'играем' : 'на паузе'})',
  );
  unawaited(
    container
        .read(playbackProvider.notifier)
        .resumeSession(data, autoplay: settings.autoplay),
  );
}

class BloomApp extends ConsumerWidget {
  const BloomApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(settingsProvider).tokens;
    // Картинка фона живёт ПОД интерфейсом, и заливку снимают ровно те, кто
    // обязан её пропустить: страницы роутера, каркас и страницы артиста и
    // сета (см. `pageBackground`). Полноэкранный плеер и шторки поверх него
    // остаются сплошными — фон в плеере пользователь видеть не хочет.
    final bgOn = ref.watch(backgroundOnProvider);
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
      // `locale: null` — язык берётся у системы и матчится с supportedLocales,
      // где английский стоит первым и потому работает запасным. Как только
      // язык выбран руками, отдаём его явно.
      locale: ref.watch(settingsProvider).locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Свой ключ мессенджера: тосты бывают и без экрана — авто-обновление
      // плейлистов ходит по таймеру.
      scaffoldMessengerKey: bloomMessengerKey,
      theme: buildBloomTheme(tokens, transparentPages: bgOn),
      // Фон — под навигатором: он один на всё приложение и не должен ни
      // перерисовываться на каждом переходе, ни ехать вместе со страницей.
      builder: (_, child) => AppBackground(child: child ?? const SizedBox()),
      routerConfig: bloomRouter,
    );
  }
}
