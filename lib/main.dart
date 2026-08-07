import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme/bloom_theme.dart';
import 'core/store/cover_store.dart';
import 'core/store/json_store.dart';
import 'core/store/library_store.dart';
import 'core/store/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Хранилище читаем ДО первого кадра: иначе библиотека и тема моргнут
  // пустыми, а экраны придётся городить с состояниями загрузки.
  final store = await JsonStore.open();
  await initCoverStore();
  runApp(
    ProviderScope(
      overrides: [jsonStoreProvider.overrideWithValue(store)],
      child: const BloomApp(),
    ),
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
      theme: buildBloomTheme(tokens),
      routerConfig: bloomRouter,
    );
  }
}
