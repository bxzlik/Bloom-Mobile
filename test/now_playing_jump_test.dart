/// Пилюля «Сейчас играет» над трек-листом: когда она всплывает и куда ведёт.
///
/// Проверяем то, что ломается тихо. Строки играющего трека в дереве может не
/// быть вовсе (список ленивый), поэтому её место считается арифметикой — и
/// ошибка там не видна ни в каком кадре: пилюля просто висит на видимом треке
/// либо не приходит, когда нужна. Плюс срез видимой части: сверху её режет
/// прилипшая шапка, снизу — миниплеер, и строка под ними не «видна».
library;

import 'package:bloom/app/theme/bloom_theme.dart';
import 'package:bloom/app/theme/tokens.dart';
import 'package:bloom/core/entities/entities.dart';
import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/features/library/ui/now_playing_jump.dart';
import 'package:bloom/features/player/player_controller.dart';
import 'package:bloom/l10n/app_localizations.dart';
import 'package:bloom/shared/ui/entity_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/glyphs.dart';
import 'package:bloom/core/db/db.dart';
import 'package:bloom/shared/ui/bloom_icon.dart';

/// Шапка списка и её сжатый вид — числа взяты «как в жизни», лишь бы считались.
const double _hero = 300;
const double _collapsed = 90;
const double _padTop = 10;

/// Нижние бары каркаса: миниплеер с таб-баром закрывают низ списка.
const double _bars = 130;

/// Высота вьюпорта в тесте.
const double _viewport = 640;

Track _track(String id) => Track(
  id: id,
  name: 'Трек $id',
  artist: 'Артист $id',
  duration: const Duration(minutes: 3),
  source: MusicSource.soundcloud,
);

/// Верх строки [i] в координатах прокрутки — та же арифметика, что у экрана.
double _rowTop(int i) => _hero + _padTop + i * kTrackRowHeight;

class _FakePlayback extends PlaybackController {
  _FakePlayback(this.initial);

  final PlaybackState initial;

  @override
  PlaybackState build() => initial;
}

void main() {
  group('направление', () {
    int dir(double rowTop, double offset) => nowPlayingJumpDir(
      rowTop: rowTop,
      offset: offset,
      viewport: _viewport,
      topInset: _collapsed,
      bottomInset: _bars,
    );

    test('строка на виду — пилюли нет', () {
      // Список не прокручен, строка стоит сразу под шапкой.
      expect(dir(_rowTop(0), 0), 0);
    });

    test('уехала вниз — стрелка вниз', () {
      // Последняя видимая строка кончается на 640 − 130 = 510.
      expect(dir(_rowTop(20), 0), 1);
    });

    test('уехала вверх — стрелка вверх', () {
      expect(dir(_rowTop(0), 2000), -1);
    });

    test('запас в полторы строки не даёт пилюле мигать на границе', () {
      // Строка ушла под миниплеер, но всего на строку — это ещё не «уехала».
      final bottom = _viewport - _bars;
      expect(dir(bottom + kTrackRowHeight, 0), 0);
      expect(dir(bottom + kJumpShowGap + 1, 0), 1);
    });

    test('строка под прилипшей шапкой считается уехавшей вверх', () {
      // Верх видимой части — не 0, а нижняя кромка сжатой шапки: строка,
      // спрятанная под ней, не видна, сколько бы её ни было в раскладке.
      expect(dir(0, _collapsed + kJumpShowGap + 1), -1);
    });

    test('трека в списке нет — пилюли нет', () {
      expect(
        nowPlayingJumpDir(
          rowTop: null,
          offset: 4000,
          viewport: _viewport,
          topInset: _collapsed,
          bottomInset: _bars,
        ),
        0,
      );
    });

    test('до раскладки вьюпорта нет — молчим, а не показываем', () {
      expect(
        nowPlayingJumpDir(
          rowTop: _rowTop(30),
          offset: 0,
          viewport: 0,
          topInset: _collapsed,
          bottomInset: _bars,
        ),
        0,
      );
    });
  });

  group('цель прокрутки', () {
    test('строка встаёт под шапкой, с просветом над собой', () {
      expect(
        nowPlayingJumpTarget(
          rowTop: _rowTop(30),
          topInset: _collapsed,
          min: 0,
          max: 10000,
        ),
        _rowTop(30) - _collapsed - kJumpScrollMargin,
      );
    });

    test('выше начала списка не уезжаем', () {
      // Шапка ниже сжатой да просвет — у самых первых строк вычитать столько
      // неоткуда, и цель ушла бы в минус.
      expect(
        nowPlayingJumpTarget(
          rowTop: _collapsed,
          topInset: _collapsed,
          min: 0,
          max: 10000,
        ),
        0,
      );
    });

    test('за конец списка не уезжаем', () {
      expect(
        nowPlayingJumpTarget(
          rowTop: _rowTop(300),
          topInset: _collapsed,
          min: 0,
          max: 500,
        ),
        500,
      );
    });
  });

  group('пилюля', () {
    late ScrollController scroll;

    /// Список на 60 строк с шапкой и пилюлей поверх; играет [playingIndex],
    /// `null` — играет трек не из этого списка.
    Future<void> pump(WidgetTester tester, {int? playingIndex = 30}) async {
      scroll = ScrollController();
      addTearDown(scroll.dispose);
      final tracks = [for (var i = 0; i < 60; i++) _track('t$i')];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jsonStoreProvider.overrideWithValue(JsonStore.memory({})),
            dbProvider.overrideWithValue(BloomDb.memory()),
            playbackProvider.overrideWith(
              () => _FakePlayback(
                PlaybackState(
                  queue: [
                    playingIndex == null
                        ? _track('чужой')
                        : tracks[playingIndex],
                  ],
                  index: 0,
                ),
              ),
            ),
            playingProvider.overrideWith((ref) => Stream.value(true)),
          ],
          child: MaterialApp(
            theme: buildBloomTheme(BloomThemes.dark),
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(400, _viewport),
                padding: EdgeInsets.only(bottom: _bars),
              ),
              child: Scaffold(
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomScrollView(
                      controller: scroll,
                      slivers: [
                        const SliverToBoxAdapter(
                          child: SizedBox(height: _hero),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.only(top: _padTop),
                          sliver: SliverList.builder(
                            itemCount: tracks.length,
                            itemBuilder: (context, i) => SizedBox(
                              height: kTrackRowHeight,
                              child: Text(tracks[i].name),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 16,
                      bottom: _bars + 12,
                      child: NowPlayingJump(
                        controller: scroll,
                        rowTopOf: (id) {
                          final i = tracks.indexWhere((t) => t.id == id);
                          return i < 0 ? null : _rowTop(i);
                        },
                        topInset: _collapsed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      // Не `pumpAndSettle`: внутри пилюли эквалайзер, и его анимация вечная.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    /// Видна ли пилюля — она не снимается с дерева, а гаснет.
    bool visible(WidgetTester tester) =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity ==
        1;

    testWidgets('всплывает, когда играющий трек уехал за край', (tester) async {
      await pump(tester);
      expect(visible(tester), isTrue);
      expect(find.text('Сейчас играет'), findsOneWidget);
      expect(findGlyph(Bi.arrowDown), findsOneWidget);
    });

    testWidgets('тап возвращает список к строке', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Сейчас играет'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        scroll.offset,
        moreOrLessEquals(
          _rowTop(30) - _collapsed - kJumpScrollMargin,
          epsilon: 1,
        ),
      );
      // Доехали — пилюля ушла.
      await tester.pump(const Duration(milliseconds: 300));
      expect(visible(tester), isFalse);
    });

    testWidgets('прокрутили ниже трека — стрелка разворачивается', (
      tester,
    ) async {
      await pump(tester);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(visible(tester), isTrue);
      expect(findGlyph(Bi.arrowUp), findsOneWidget);
    });

    testWidgets('играет трек не из этого списка — пилюли нет', (tester) async {
      await pump(tester, playingIndex: null);
      expect(visible(tester), isFalse);
    });
  });
}
