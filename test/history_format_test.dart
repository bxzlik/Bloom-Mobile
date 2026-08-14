/// Подписи «Истории»: границы дней и формы слов.
///
/// Смысл теста — в границах: «сегодня» и «вчера» считаются по календарю, а не
/// по 24 часа, поэтому запись в 00:30 не должна утром числиться вчерашней.
library;

import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/features/library/history_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Подпись для записи [at] на момент [now] в локали [locale].
Future<String> _label(
  WidgetTester tester,
  DateTime at,
  DateTime now, {
  Locale locale = const Locale('ru'),
}) async {
  late String out;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          out = historyLabel(context, at, now: now);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return out;
}

void main() {
  testWidgets('сегодня — весь календарный день, а не последние сутки', (
    tester,
  ) async {
    final now = DateTime(2026, 3, 15, 9, 0);
    expect(await _label(tester, DateTime(2026, 3, 15, 0, 30), now), 'Сегодня');
    expect(await _label(tester, DateTime(2026, 3, 15, 8, 59), now), 'Сегодня');
  });

  testWidgets('вчера — предыдущий календарный день целиком', (tester) async {
    final now = DateTime(2026, 3, 15, 9, 0);
    expect(await _label(tester, DateTime(2026, 3, 14, 23, 50), now), 'Вчера');
    expect(await _label(tester, DateTime(2026, 3, 14, 0, 1), now), 'Вчера');
  });

  testWidgets('дни до недели — с русскими формами', (tester) async {
    final now = DateTime(2026, 3, 15, 9, 0);
    expect(await _label(tester, DateTime(2026, 3, 13, 12), now), '2 дня назад');
    expect(
      await _label(tester, DateTime(2026, 3, 10, 12), now),
      '5 дней назад',
    );
  });

  testWidgets('неделя и дальше — «Неделю назад», потом дата', (tester) async {
    final now = DateTime(2026, 3, 15, 9, 0);
    expect(await _label(tester, DateTime(2026, 3, 8, 12), now), 'Неделю назад');
    // Дальше двух недель — день и месяц без года.
    expect(await _label(tester, DateTime(2026, 2, 20, 12), now), '20 февраля');
  });

  testWidgets('английская локаль', (tester) async {
    final now = DateTime(2026, 3, 15, 9, 0);
    const en = Locale('en');
    expect(
      await _label(tester, DateTime(2026, 3, 15, 1), now, locale: en),
      'Today',
    );
    expect(
      await _label(tester, DateTime(2026, 3, 14, 1), now, locale: en),
      'Yesterday',
    );
    expect(
      await _label(tester, DateTime(2026, 3, 12, 1), now, locale: en),
      '3 days ago',
    );
  });
}
