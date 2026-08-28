/// Центр уведомлений: сам стор (порядок, лимит, прочитанность) и его вид —
/// колокольчик с бейджем плюс шторка-история.
///
/// Время берём подменными часами (`notifClockProvider`): у карточки в шапке
/// стоит час события, и на настоящих часах такой тест зависел бы от минуты
/// прогона.
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart';
import 'package:bloom/features/notifications/notif_store.dart';
import 'package:bloom/features/notifications/ui/notif_bell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solar_icons/solar_icons.dart';

final _at = DateTime(2026, 8, 20, 14, 2);

ProviderContainer _container({DateTime? now}) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(JsonStore.memory()),
      notifClockProvider.overrideWithValue(() => now ?? _at),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildBloomTheme(BloomThemes.dark),
      home: Scaffold(body: Center(child: child)),
    ),
  ),
);

void main() {
  group('стор', () {
    test('свежее сверху и непрочитанное', () {
      final c = _container();
      c.read(notifCenterProvider.notifier)
        ..add(
          kind: NotifKind.success,
          title: NotifTitle.offlineReady,
          body: 'Первый',
        )
        ..add(
          kind: NotifKind.error,
          title: NotifTitle.downloadError,
          body: 'Второй',
        );

      final items = c.read(notifCenterProvider);
      expect(items.map((n) => n.body), ['Второй', 'Первый']);
      expect(items.every((n) => !n.read), isTrue);
      expect(c.read(notifUnreadProvider), 2);
      expect(items.first.ts, _at);
      // id не должны повторяться даже на одних и тех же часах: время у обоих
      // событий одинаковое, различает их только счётчик.
      expect(items[0].id, isNot(items[1].id));
    });

    test('история обрезается по kNotifMax', () {
      final c = _container();
      final notifs = c.read(notifCenterProvider.notifier);
      for (var i = 0; i < kNotifMax + 10; i++) {
        notifs.add(
          kind: NotifKind.info,
          title: NotifTitle.trackUnavailable,
          body: 'n$i',
        );
      }

      final items = c.read(notifCenterProvider);
      expect(items.length, kNotifMax);
      // Отваливается ХВОСТ: самое старое, а не самое свежее.
      expect(items.first.body, 'n${kNotifMax + 9}');
      expect(items.last.body, 'n10');
    });

    test('markAllRead гасит счётчик и повторно список не трогает', () {
      final c = _container();
      final notifs = c.read(notifCenterProvider.notifier)
        ..add(kind: NotifKind.info, title: NotifTitle.offlineReady)
        ..markAllRead();

      expect(c.read(notifUnreadProvider), 0);
      expect(c.read(notifCenterProvider).single.read, isTrue);

      // Нечего обновлять — ссылка на список остаётся прежней (лишняя
      // перерисовка шапки на каждом открытии шторки никому не нужна).
      final before = c.read(notifCenterProvider);
      notifs.markAllRead();
      expect(identical(c.read(notifCenterProvider), before), isTrue);
    });

    test('clear чистит всё', () {
      final c = _container();
      c.read(notifCenterProvider.notifier)
        ..add(kind: NotifKind.info, title: NotifTitle.offlineReady)
        ..clear();
      expect(c.read(notifCenterProvider), isEmpty);
      expect(c.read(notifUnreadProvider), 0);
    });
  });

  group('колокольчик', () {
    testWidgets('без непрочитанных бейджа нет', (tester) async {
      final c = _container();
      await _pump(tester, c, const NotifBell());

      expect(find.byIcon(SolarIconsOutline.bell), findsOneWidget);
      expect(find.textContaining(RegExp(r'^\d')), findsNothing);
    });

    testWidgets('бейдж считает непрочитанные и сворачивается в 9+', (
      tester,
    ) async {
      final c = _container();
      final notifs = c.read(notifCenterProvider.notifier);
      notifs.add(kind: NotifKind.success, title: NotifTitle.trackDownloaded);
      await _pump(tester, c, const NotifBell());
      expect(find.text('1'), findsOneWidget);

      for (var i = 0; i < 11; i++) {
        notifs.add(kind: NotifKind.info, title: NotifTitle.offlineReady);
      }
      await tester.pump();
      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('тап открывает историю и гасит бейдж', (tester) async {
      final c = _container();
      c
          .read(notifCenterProvider.notifier)
          .add(
            kind: NotifKind.success,
            title: NotifTitle.offlineReady,
            body: 'Nirvana — Lithium',
          );
      await _pump(tester, c, const NotifBell());

      await tester.tap(find.byIcon(SolarIconsOutline.bell));
      await tester.pumpAndSettle();

      // Заголовок события, тело и время — всё из карточки.
      expect(find.text('Трек доступен офлайн'), findsOneWidget);
      expect(find.text('Nirvana — Lithium'), findsOneWidget);
      expect(find.text('14:02'), findsOneWidget);
      // Бейдж гаснет открытием, как на ПК.
      expect(c.read(notifUnreadProvider), 0);
    });
  });

  group('шторка', () {
    testWidgets('пустая история: подпись на месте, чистить нечего', (
      tester,
    ) async {
      final c = _container();
      await _pump(tester, c, const NotifBell());
      await tester.tap(find.byIcon(SolarIconsOutline.bell));
      await tester.pumpAndSettle();

      expect(find.text('Уведомлений пока нет'), findsOneWidget);
      final clear = tester.widget<InkWell>(
        find.ancestor(
          of: find.byIcon(SolarIconsOutline.trashBinMinimalistic),
          matching: find.byType(InkWell),
        ),
      );
      expect(clear.onTap, isNull);
    });

    testWidgets('очистка убирает список на месте', (tester) async {
      final c = _container();
      c
          .read(notifCenterProvider.notifier)
          .add(
            kind: NotifKind.error,
            title: NotifTitle.trackUnavailable,
            body: 'Песня',
          );
      await _pump(tester, c, const NotifBell());
      await tester.tap(find.byIcon(SolarIconsOutline.bell));
      await tester.pumpAndSettle();

      expect(find.text('Недоступный трек'), findsOneWidget);
      await tester.tap(find.byIcon(SolarIconsOutline.trashBinMinimalistic));
      await tester.pumpAndSettle();

      expect(find.text('Недоступный трек'), findsNothing);
      expect(find.text('Уведомлений пока нет'), findsOneWidget);
    });

    testWidgets('перевод есть у каждого вида заголовка', (tester) async {
      final c = _container();
      final notifs = c.read(notifCenterProvider.notifier);
      for (final title in NotifTitle.values) {
        notifs.add(kind: NotifKind.info, title: title);
      }
      await _pump(tester, c, const NotifBell());
      await tester.tap(find.byIcon(SolarIconsOutline.bell));
      await tester.pumpAndSettle();

      // Ни одного «сырого» имени из enum — значит все ключи на месте.
      for (final title in NotifTitle.values) {
        expect(find.text(title.name), findsNothing);
      }
      expect(find.text('Трек скачан'), findsOneWidget);
      expect(find.text('Ошибка скачивания'), findsOneWidget);
      expect(find.text('Трек доступен офлайн'), findsOneWidget);
      expect(find.text('Не удалось скачать офлайн'), findsOneWidget);
      expect(find.text('Недоступный трек'), findsOneWidget);
    });
  });
}
