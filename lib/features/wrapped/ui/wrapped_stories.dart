/// Полноэкранная история «Итогов» — порт десктопного `WrappedStories.tsx`.
///
/// Как сторис у площадок: полоски прогресса сверху, автопереход, тап по левой
/// трети — назад, по правой — вперёд, удержание — пауза. Первый экран — выбор
/// периода (в окне показа их может быть доступно несколько, 1 января — все
/// три), дальше слайды одного периода.
///
/// **Не оверлей, а маршрут** — в отличие от ПК, где это портал в `body`. На
/// телефоне есть системное «назад», и оверлей поверх каркаса уводил бы его в
/// навигатор под собой (те же грабли, что с онбордингом). Маршрут корневой:
/// таб-бар и миниплеер истории не нужны.
///
/// Ручки тюнинга: [kWrSlideMs] (длительность слайда), [kWrHoldMs] (сколько
/// держать, чтобы поставить на паузу), [kWrHueStep] (на сколько уезжает оттенок
/// акцента за слайд), [kWrDismissVelocity] (порог свайпа вниз).
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/store/cover_store.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../profile/artist_avatars.dart';
import '../periods.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import '../wrapped_store.dart';
import 'wrapped_poster.dart';

/// Сколько висит один слайд.
const int kWrSlideMs = 6000;

/// Удержание дольше этого — пауза, короче — листание.
const int kWrHoldMs = 220;

/// На сколько градусов уезжает оттенок акцента за слайд.
const double kWrHueStep = 34;

/// Свайп вниз быстрее этого закрывает историю.
const double kWrDismissVelocity = 320;

/// Пороги, ниже которых добавляем подкол «как-то пусто» (десктопные).
const int kWrJokeTiny = 5;
const int kWrJokeSmall = 25;

/// Доля ночных прослушиваний, с которой слушатель считается ночным.
const double kWrNightShare = 0.35;

enum _SlideId {
  intro,
  time,
  counts,
  tracks,
  artists,
  sources,
  discover,
  habits,
  share,
}

/// Открыть историю. Возвращает то же, что `Navigator.push` — ждать её не надо.
Future<void> openWrappedStories(BuildContext context, WrappedReady ready) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => WrappedStories(ready: ready),
      // Тот же приезд, что у `wrIn` на ПК: чуть увеличенный кадр садится на
      // место, а не выезжает сбоку.
      transitionsBuilder: (_, animation, _, child) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.04, end: 1).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class WrappedStories extends ConsumerStatefulWidget {
  const WrappedStories({super.key, required this.ready});

  final WrappedReady ready;

  @override
  ConsumerState<WrappedStories> createState() => _WrappedStoriesState();
}

class _WrappedStoriesState extends ConsumerState<WrappedStories>
    with SingleTickerProviderStateMixin {
  /// `null` — открыт экран выбора периода.
  PeriodKind? _period;
  int _idx = 0;
  late final AnimationController _bar =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: kWrSlideMs),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _go(1);
      });

  WrappedData? get _data => _period == null ? null : widget.ready.data[_period];

  List<_SlideId> get _slides {
    final d = _data;
    if (d == null) return const [];
    return [
      _SlideId.intro,
      _SlideId.time,
      _SlideId.counts,
      _SlideId.tracks,
      if (d.topArtists.isNotEmpty) _SlideId.artists,
      if (d.sources.isNotEmpty) _SlideId.sources,
      if (d.newArtists.isNotEmpty) _SlideId.discover,
      if (d.activeDays > 0) _SlideId.habits,
      _SlideId.share,
    ];
  }

  /// Постер не крутится сам — на нём кнопка, ждём действия человека.
  bool get _timed =>
      _period != null &&
      _idx < _slides.length &&
      _slides[_idx] != _SlideId.share;

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  void _openPeriod(PeriodKind kind) {
    final data = widget.ready.data[kind];
    if (data == null) return;
    ref.read(wrappedPrefsProvider.notifier).markSeen(data.range);
    setState(() {
      _period = kind;
      _idx = 0;
    });
    _restartBar();
  }

  void _restartBar() {
    _bar.stop();
    _bar.value = 0;
    if (_timed) _bar.forward();
  }

  void _go(int delta) {
    if (_period == null) return;
    final next = _idx + delta;
    if (next < 0) {
      // Назад с первого слайда — обратно к выбору периода.
      setState(() {
        _period = null;
        _idx = 0;
      });
      _bar.stop();
      _bar.value = 0;
      return;
    }
    if (next >= _slides.length) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _idx = next);
    _restartBar();
  }

  void _pause() {
    if (_bar.isAnimating) _bar.stop();
  }

  void _resume() {
    if (_timed && !_bar.isAnimating && _bar.value < 1) _bar.forward();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final d = _data;
    final slides = _slides;
    final cur = _period == null || _idx >= slides.length ? null : slides[_idx];
    // Оттенок уезжает от слайда к слайду — на ПК это `filter:hue-rotate`.
    // Здесь крутим сам акцент: фильтра оттенка у Flutter нет, а цвет фона всё
    // равно строится из акцента формулой.
    final accent = _shiftHue(t.accent, _idx * kWrHueStep);

    return Scaffold(
      backgroundColor: const Color(0xFF080808),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(accent: accent, tracks: d?.topTracks ?? const []),
          SafeArea(
            child: Column(
              children: [
                _TopRow(
                  slides: slides.length,
                  index: _idx,
                  timed: _timed,
                  progress: _bar,
                  showBars: _period != null,
                  onClose: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: _period == null ? null : (e) => _onTap(e),
                    // Удержание — пауза, как в сторис. Порог [kWrHoldMs] —
                    // это и есть `deltaToStartPress` у детектора.
                    onLongPressStart: _period == null ? null : (_) => _pause(),
                    onLongPressEnd: _period == null ? null : (_) => _resume(),
                    onLongPressCancel: _period == null ? null : _resume,
                    onVerticalDragEnd: (e) {
                      if ((e.primaryVelocity ?? 0) > kWrDismissVelocity) {
                        Navigator.of(context).maybePop();
                      }
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: KeyedSubtree(
                        key: ValueKey('${_period?.id ?? 'pick'}:$_idx'),
                        child: _period == null
                            ? _PickSlide(
                                ready: widget.ready,
                                onPick: _openPeriod,
                              )
                            : _Slide(id: cur!, data: d!, accent: accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onTap(TapUpDetails e) {
    final width = MediaQuery.sizeOf(context).width;
    _go(e.localPosition.dx < width * 0.33 ? -1 : 1);
  }
}

/// Сдвинуть оттенок цвета на [degrees] — замена десктопному `hue-rotate`.
Color _shiftHue(Color color, double degrees) {
  if (degrees == 0) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withHue((hsl.hue + degrees) % 360).toColor();
}

// ── Фон: акцентный градиент + размытый коллаж обложек ──────────────────────

class _Backdrop extends ConsumerWidget {
  const _Backdrop({required this.accent, required this.tracks});

  final Color accent;
  final List<WrappedTrack> tracks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final covers = <String>[];
    for (final tr in tracks) {
      final cover = coverOfWrappedTrack(tr, lib);
      if (cover != null && !covers.contains(cover)) covers.add(cover);
      if (covers.length == 4) break;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Градиент едет за оттенком слайда — плавно, чтобы смена не мигала.
        TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: accent),
          duration: const Duration(milliseconds: 600),
          builder: (_, color, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    (color ?? accent).withValues(alpha: 0.55),
                    const Color(0xFF141414),
                  ),
                  Color.alphaBlend(
                    (color ?? accent).withValues(alpha: 0.18),
                    const Color(0xFF0C0C0C),
                  ),
                  const Color(0xFF080808),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        if (covers.isNotEmpty)
          Opacity(
            opacity: 0.22,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Transform.scale(
                scale: 1.2,
                child: GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: covers.length == 1 ? 1 : 2,
                  children: [
                    for (final c in covers)
                      Image(
                        image: coverImage(c)!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Обложка трека итогов: снимок из журнала → библиотека.
///
/// Снимок может быть пустым (трек играл до появления журнала снимков либо
/// пришёл без обложки), поэтому фолбэк обязателен.
String? coverOfWrappedTrack(WrappedTrack track, LibraryState lib) =>
    track.cover ?? lib.tracks[track.id]?.cover;

// ── Верхний ряд: полоски прогресса и крестик ───────────────────────────────

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.slides,
    required this.index,
    required this.timed,
    required this.progress,
    required this.showBars,
    required this.onClose,
  });

  final int slides;
  final int index;
  final bool timed;
  final Animation<double> progress;
  final bool showBars;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          // Выход — та же круглая «назад», что в шапке профиля и подстраниц
          // настроек (его правка: крестик в углу был чужим для приложения).
          GlassIconButton(icon: SolarIconsOutline.arrowLeft, onTap: onClose),
          const SizedBox(width: 10),
          Expanded(
            child: showBars
                ? Row(
                    children: [
                      for (var i = 0; i < slides; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: _Bar(
                            // Последний слайд без таймера — его полоску сразу
                            // показываем полной.
                            value: i < index || (i == index && !timed)
                                ? const AlwaysStoppedAnimation(1.0)
                                : i == index
                                ? progress
                                : const AlwaysStoppedAnimation(0.0),
                          ),
                        ),
                      ],
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final Animation<double> value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            const ColoredBox(
              color: Color(0x38FFFFFF),
              child: SizedBox.expand(),
            ),
            AnimatedBuilder(
              animation: value,
              builder: (_, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.value.clamp(0.0, 1.0),
                child: const ColoredBox(
                  color: Colors.white,
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Выбор периода ──────────────────────────────────────────────────────────

class _PickSlide extends ConsumerWidget {
  const _PickSlide({required this.ready, required this.onPick});

  final WrappedReady ready;
  final void Function(PeriodKind) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        children: [
          for (var i = 0; i < ready.periods.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Expanded(
              child: _PickCard(
                data: ready.data[ready.periods[i]]!,
                lib: lib,
                delayMs: 80 + i * 90,
                onTap: () => onPick(ready.periods[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PickCard extends StatelessWidget {
  const _PickCard({
    required this.data,
    required this.lib,
    required this.delayMs,
    required this.onTap,
  });

  final WrappedData data;
  final LibraryState lib;
  final int delayMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final covers = [
      for (final tr in data.topTracks) coverOfWrappedTrack(tr, lib),
    ];

    return _FadeUp(
      delayMs: delayMs,
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Мозаика обложек периода во всю карточку: сразу видно, о какой
              // музыке речь.
              _CoverMosaic(covers: covers),
              // Плёнка: снизу почти чёрное (текст читается на любой обложке),
              // сверху лёгкий тинт акцента.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x80000000),
                      Color(0x1A000000),
                      Color(0x9E000000),
                      Color(0xED000000),
                    ],
                    stops: [0, 0.24, 0.64, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        periodTitle(l, data.range.kind),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.12,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        periodDatesLabel(data.range, locale),
                        style: const TextStyle(
                          color: Color(0xADFFFFFF),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _PickChip(
                            icon: SolarIconsBold.play,
                            text: l.wrPlaysN(data.plays),
                          ),
                          _PickChip(
                            icon: SolarIconsOutline.musicNote3,
                            text: l.wrTracksN(data.uniqueTracks),
                          ),
                          _PickChip(
                            icon: SolarIconsOutline.user,
                            text: l.wrArtistsN(data.uniqueArtists),
                          ),
                        ],
                      ),
                    ],
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

class _CoverMosaic extends StatelessWidget {
  const _CoverMosaic({required this.covers});

  final List<String?> covers;

  @override
  Widget build(BuildContext context) {
    // Меньше четырёх РАЗНЫХ обложек — показываем одну на всю карточку: сетка
    // из копий одной картинки выглядит поломанной, а не мозаикой.
    final picked = <String>[];
    for (final c in covers) {
      if (c == null || c.isEmpty || picked.contains(c)) continue;
      picked.add(c);
      if (picked.length == 4) break;
    }
    if (picked.isEmpty) {
      return const ColoredBox(
        color: Color(0xFF141414),
        child: Center(
          child: Icon(
            SolarIconsOutline.cup,
            size: 40,
            color: Color(0x59FFFFFF),
          ),
        ),
      );
    }
    final tiles = picked.length >= 4 ? picked.take(4).toList() : [picked.first];
    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: tiles.length == 1 ? 1 : 2,
      children: [
        for (final c in tiles)
          Image(
            image: coverImage(c)!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF141414)),
          ),
      ],
    );
  }
}

class _PickChip extends StatelessWidget {
  const _PickChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: const Color(0xD1FFFFFF)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xD1FFFFFF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Название периода — оно же подпись у входа и заголовок постера.
String periodTitle(AppLocalizations l, PeriodKind kind) => switch (kind) {
  PeriodKind.week => l.wrWeek,
  PeriodKind.month => l.wrMonth,
  PeriodKind.year => l.wrYear,
};

// ── Слайды ─────────────────────────────────────────────────────────────────

class _Slide extends StatelessWidget {
  const _Slide({required this.id, required this.data, required this.accent});

  final _SlideId id;
  final WrappedData data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final body = switch (id) {
      _SlideId.intro => _IntroSlide(data: data),
      _SlideId.time => _TimeSlide(data: data),
      _SlideId.counts => _CountsSlide(data: data),
      _SlideId.tracks => _TracksSlide(data: data),
      _SlideId.artists => _ArtistsSlide(data: data),
      _SlideId.sources => _SourcesSlide(data: data),
      _SlideId.discover => _DiscoverSlide(data: data),
      _SlideId.habits => _HabitsSlide(data: data),
      _SlideId.share => _ShareSlide(data: data, accent: accent),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 24),
      child: body,
    );
  }
}

/// Подкол для скудных итогов — на ПК его просил сам пользователь.
String? _joke(AppLocalizations l, WrappedData d) {
  if (d.uniqueTracks == 1) return l.wrJokeOneTrack;
  if (d.plays < kWrJokeTiny) return l.wrJokeTiny;
  if (d.plays < kWrJokeSmall) return l.wrJokeSmall;
  return null;
}

class _IntroSlide extends StatelessWidget {
  const _IntroSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final joke = _joke(l, data);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FadeUp(child: _Kicker(periodDatesLabel(data.range, locale))),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(switch (data.range.kind) {
            PeriodKind.week => l.wrIntroWeek,
            PeriodKind.month => l.wrIntroMonth,
            PeriodKind.year => l.wrIntroYear,
          }, size: 40),
        ),
        const SizedBox(height: 10),
        _FadeUp(delayMs: 160, child: _Sub(l.wrIntroSub)),
        if (joke != null) ...[
          const SizedBox(height: 16),
          _FadeUp(delayMs: 240, child: _Joke(joke)),
        ],
      ],
    );
  }
}

class _TimeSlide extends StatelessWidget {
  const _TimeSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final joke = _joke(l, data);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FadeUp(child: _Kicker(l.wrTimeKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(fmtListenTime(l, data.seconds), size: 46),
        ),
        const SizedBox(height: 10),
        _FadeUp(delayMs: 160, child: _Sub(l.wrTimeSub(data.plays))),
        if (joke != null) ...[
          const SizedBox(height: 16),
          _FadeUp(delayMs: 240, child: _Joke(joke)),
        ],
      ],
    );
  }
}

class _CountsSlide extends StatelessWidget {
  const _CountsSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final tiles = <(int, String)>[
      (data.plays, l.wrPlaysWord(data.plays)),
      (data.uniqueTracks, l.wrTracksWord(data.uniqueTracks)),
      (data.uniqueArtists, l.wrArtistsWord(data.uniqueArtists)),
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrCountsKicker)),
        const SizedBox(height: 10),
        _FadeUp(delayMs: 80, child: _Title(l.wrCountsTitle)),
        const SizedBox(height: 18),
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _FadeUp(
            delayMs: 140 + i * 90,
            child: _CountTile(
              value: fmtCount(locale, tiles[i].$1),
              label: tiles[i].$2,
            ),
          ),
        ],
        if (data.newTracksCount > 0) ...[
          const SizedBox(height: 14),
          _FadeUp(
            delayMs: 440,
            child: Text(
              l.wrCountsNewTracks(data.newTracksCount),
              style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0x17FFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _TracksSlide extends ConsumerWidget {
  const _TracksSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final lib = ref.watch(libraryProvider);
    final top = data.topTracks;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrTracksKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(top.length > 1 ? l.wrTracksTitle : l.wrTracksTitleOne),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _FadeUp(
            delayMs: 140 + i * 80,
            child: _TopRowTile(
              index: i,
              cover: coverOfWrappedTrack(top[i], lib),
              title: top[i].name.isEmpty ? l.commonTracks : top[i].name,
              subtitle: top[i].artist,
              value: l.wrPlaysN(top[i].plays),
              // Первая строка — «номер один», она крупнее (десктопное
              // `.wr-row:first-child`).
              big: i == 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _ArtistsSlide extends ConsumerStatefulWidget {
  const _ArtistsSlide({required this.data});

  final WrappedData data;

  @override
  ConsumerState<_ArtistsSlide> createState() => _ArtistsSlideState();
}

class _ArtistsSlideState extends ConsumerState<_ArtistsSlide> {
  @override
  void initState() {
    super.initState();
    // Аватары догружаются фоном — тот же кеш, что у топа в профиле. Нет
    // ответа, значит останется обложка лучшего трека артиста.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(artistAvatarsProvider.notifier).ensure([
        for (final a in widget.data.topArtists) a.name,
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final avatars = ref.watch(artistAvatarsProvider);
    final top = widget.data.topArtists;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrArtistsKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(
            top.length > 1 ? l.wrArtistsTitle : l.wrArtistsTitleOne,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < top.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _FadeUp(
            delayMs: 140 + i * 80,
            child: _TopRowTile(
              index: i,
              cover: avatars[top[i].name.toLowerCase()] ?? top[i].cover,
              title: top[i].name,
              value: l.wrPlaysN(top[i].plays),
              round: true,
              big: i == 0,
            ),
          ),
        ],
      ],
    );
  }
}

class _TopRowTile extends StatelessWidget {
  const _TopRowTile({
    required this.index,
    required this.cover,
    required this.title,
    required this.value,
    this.subtitle,
    this.round = false,
    this.big = false,
  });

  final int index;
  final String? cover;
  final String title;
  final String? subtitle;
  final String value;
  final bool round;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final size = big ? 64.0 : 46.0;
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(
            '${index + 1}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0x73FFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Cover(url: cover, size: size, circle: round),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: big ? 18 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0x8CFFFFFF),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          value,
          style: const TextStyle(color: Color(0x8CFFFFFF), fontSize: 12),
        ),
      ],
    );
  }
}

class _SourcesSlide extends StatelessWidget {
  const _SourcesSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final max = data.sources.isEmpty ? 1 : data.sources.first.plays;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrSourcesKicker)),
        const SizedBox(height: 10),
        _FadeUp(delayMs: 80, child: _Title(l.wrSourcesTitle)),
        const SizedBox(height: 18),
        for (var i = 0; i < data.sources.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _FadeUp(
            delayMs: 140 + i * 90,
            child: _SourceRow(
              source: data.sources[i],
              share: data.plays == 0
                  ? 0
                  : (data.sources[i].plays / data.plays * 100).round(),
              fill: data.sources[i].plays / max,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.share,
    required this.fill,
  });

  final WrappedSource source;
  final int share;
  final double fill;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final color = platformColor[source.source] ?? context.bloom.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (source.source != MusicSource.local)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PlatformLogo(source.source, size: 16),
              ),
            Expanded(
              child: Text(
                source.source.label10n(l),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              '$share%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 7,
            child: Stack(
              children: [
                const ColoredBox(
                  color: Color(0x21FFFFFF),
                  child: SizedBox.expand(),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: fill.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: ColoredBox(
                      color: color,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.wrPlaysN(source.plays),
          style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 12),
        ),
      ],
    );
  }
}

class _DiscoverSlide extends ConsumerStatefulWidget {
  const _DiscoverSlide({required this.data});

  final WrappedData data;

  @override
  ConsumerState<_DiscoverSlide> createState() => _DiscoverSlideState();
}

class _DiscoverSlideState extends ConsumerState<_DiscoverSlide> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(artistAvatarsProvider.notifier).ensure([
        for (final a in widget.data.newArtists) a.name,
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final avatars = ref.watch(artistAvatarsProvider);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrDiscoverKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(l.wrDiscoverTitle(widget.data.newArtistsCount)),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < widget.data.newArtists.length; i++)
              _FadeUp(
                delayMs: 160 + i * 90,
                child: _ArtistChip(
                  name: widget.data.newArtists[i].name,
                  avatar:
                      avatars[widget.data.newArtists[i].name.toLowerCase()] ??
                      widget.data.newArtists[i].cover,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ArtistChip extends StatelessWidget {
  const _ArtistChip({required this.name, required this.avatar});

  final String name;
  final String? avatar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Cover(url: avatar, size: 26, circle: true),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  const _HabitsSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final max = data.hours.fold(1, (m, n) => n > m ? n : m);
    final night = data.nightShare >= kWrNightShare;
    final record = data.recordDay;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: _Kicker(l.wrHabitsKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 80,
          child: _Title(night ? l.wrHabitsNight : l.wrHabitsDay),
        ),
        const SizedBox(height: 18),
        _FadeUp(
          delayMs: 160,
          child: SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++) ...[
                  if (h > 0) const SizedBox(width: 3),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (data.hours[h] / max).clamp(0.03, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: h == data.peakHour
                              ? Colors.white
                              : const Color(0x47FFFFFF),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(3),
                            bottom: Radius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _FadeUp(
          delayMs: 200,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _AxisLabel('00'),
              _AxisLabel('06'),
              _AxisLabel('12'),
              _AxisLabel('18'),
              _AxisLabel('23'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _FadeUp(
                delayMs: 260,
                child: _Fact(
                  label: l.wrHabitsPeak,
                  value: fmtHourRange(l, data.peakHour),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FadeUp(
                delayMs: 320,
                child: _Fact(
                  label: l.wrHabitsStreak,
                  value: l.wrDaysN(data.streak),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            if (record != null) ...[
              Expanded(
                child: _FadeUp(
                  delayMs: 380,
                  child: _Fact(
                    label: l.wrHabitsRecord,
                    value: l.wrHabitsRecordValue(
                      l.wrTracksN(record.plays),
                      DateFormat('d MMMM', locale).format(record.date),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _FadeUp(
                delayMs: 440,
                child: _Fact(
                  label: l.wrHabitsActive,
                  value: l.wrDaysN(data.activeDays),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
      decoration: BoxDecoration(
        color: const Color(0x17FFFFFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0x8CFFFFFF),
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareSlide extends StatelessWidget {
  const _ShareSlide({required this.data, required this.accent});

  final WrappedData data;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _FadeUp(child: _Kicker(l.wrShareKicker)),
        const SizedBox(height: 14),
        Flexible(
          child: _FadeUp(
            delayMs: 120,
            child: WrappedPosterCard(data: data, accent: accent),
          ),
        ),
      ],
    );
  }
}

// ── Мелочи оформления ──────────────────────────────────────────────────────

class _Kicker extends StatelessWidget {
  const _Kicker(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: Color(0x8CFFFFFF),
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.size = 30});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: Colors.white,
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.08,
      letterSpacing: -0.5,
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(color: Color(0xA6FFFFFF), fontSize: 14),
  );
}

class _Joke extends StatelessWidget {
  const _Joke(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
    decoration: BoxDecoration(
      color: const Color(0x14FFFFFF),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xBFFFFFFF), fontSize: 13),
    ),
  );
}

/// Появление элемента слайда со сдвигом снизу — десктопное `.wr-in`
/// (`animation-delay` задавался инлайном, здесь тем же параметром).
class _FadeUp extends StatefulWidget {
  const _FadeUp({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> with SingleTickerProviderStateMixin {
  static const int _durationMs = 500;

  /// Задержка живёт ВНУТРИ контроллера ([Interval]), а не в `Future.delayed`:
  /// отдельный таймер пережил бы снятие виджета с дерева (слайды сменяются
  /// раньше, чем доигрывает каскад) — и это ловят тесты.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.delayMs + _durationMs),
  );

  @override
  void initState() {
    super.initState();
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.delayMs + _durationMs;
    final curve = CurvedAnimation(
      parent: _c,
      curve: Interval(widget.delayMs / total, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curve,
      builder: (_, child) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
