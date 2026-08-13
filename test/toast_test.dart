/// Тосты: отмена, истечение и живой тост «работа → итог».
///
/// Проверяем именно поведение, а не пиксели: кто и когда получает `fn` и
/// `onExpire`, и что живой тост не пересоздаётся, а меняется на месте.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/shared/ui/bloom_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bloom/core/l10n/l10n.dart';

/// Экран-подложка: тост показывается через мессенджер, поэтому нужен Scaffold.
Future<ScaffoldMessengerState> _pumpHost(WidgetTester tester) async {
  late ScaffoldMessengerState messenger;
  await tester.pumpWidget(
    MaterialApp(
      // Язык прибит гвоздями: иначе проверки текста зависели бы от локали
      // машины, на которой гоняют тесты.
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            messenger = ScaffoldMessenger.of(context);
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return messenger;
}

void main() {
  testWidgets('обычный тост показывает текст и гаснет сам', (tester) async {
    final messenger = await _pumpHost(tester);
    messenger.toast('Трек удалён');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Трек удалён'), findsOneWidget);

    // 2с жизни + анимация ухода.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Трек удалён'), findsNothing);
  });

  testWidgets('«Отменить» зовёт fn и не даёт сработать onExpire', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    var undone = false;
    var expired = false;
    messenger.toast(
      'Плейлист удалён',
      action: ToastAction(
        fn: () => undone = true,
        onExpire: () => expired = true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(expired, isFalse, reason: 'отменили — удалять уже нечего');
  });

  testWidgets('тост с действием догорел — срабатывает onExpire', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    var undone = false;
    var expired = false;
    messenger.toast(
      'Плейлист удалён',
      action: ToastAction(
        fn: () => undone = true,
        onExpire: () => expired = true,
      ),
    );
    await tester.pump();
    // С кнопкой тост живёт 5с — ждём с запасом.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(expired, isTrue, reason: 'решение осталось в силе');
    expect(undone, isFalse);
  });

  testWidgets('живой тост меняется на месте, а не вторым тостом', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    final toast = messenger.busyToast('Сохранение для офлайна…');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Сохранение для офлайна…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    toast.finish('Доступно офлайн: Song');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Старого текста уже нет — карточка та же, поменялось её содержимое.
    expect(find.text('Сохранение для офлайна…'), findsNothing);
    expect(find.text('Доступно офлайн: Song'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Доступно офлайн: Song'), findsNothing);
  });

  testWidgets('тосты становятся в очередь, а не наезжают друг на друга', (
    tester,
  ) async {
    final messenger = await _pumpHost(tester);
    messenger.toast('Первый');
    messenger.toast('Второй');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Первый'), findsOneWidget);
    expect(find.text('Второй'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Второй'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
