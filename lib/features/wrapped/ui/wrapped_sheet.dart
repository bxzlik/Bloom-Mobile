/// «Итоги» шторкой — порт десктопного `WrappedModal.tsx`.
///
/// На ПК это панель ~496 точек по центру окна; здесь — нижняя шторка поверх
/// текущего экрана. Полноэкранной истории (прежний `wrapped_stories.dart`)
/// больше нет: страница остаётся видна за затемнением, а закрывается всё
/// свайпом вниз, тапом мимо и кнопкой «Закрыть» на последнем слайде.
///
/// Механика сторис при этом сохранена целиком: полоски сверху заполняются сами
/// и по ним же можно перескочить на слайд, слайд авто-переключается, удержание
/// ставит на паузу, тап по левой и правой зоне листает. Сверху к этому
/// добавлена явная кнопка «Далее» — по ней листает тот, кто ждать не хочет.
///
/// Экрана выбора периода нет: шторка всегда открывается на конкретном периоде,
/// потому что каждый вход знает свой (подменённая карточка статистики и кнопка
/// в шторке статистики — месяц, плашка — год; см. `periods.dart`).
///
/// Высота шторки не прыгает при смене слайда: тело едет [AnimatedSize] — это
/// замена десктопному замеру через `ResizeObserver`.
///
/// Ручки тюнинга: [kWrSlideMs] (длительность слайда), [kWrBodyMin] (минимальная
/// высота тела), [kWrBlobSize] / [kWrBlobOpacity] (размер и плотность круга),
/// [kWrNumSize] (кегль огромных чисел).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/providers.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/l10n/source_label.dart';
import '../../../core/providers/artist_lookup.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';
import '../../detail/detail_nav.dart';
import '../../player/play_source.dart';
import '../../player/player_controller.dart';
import '../../profile/artist_avatars.dart';
import '../../settings/cover_accent.dart';
import '../periods.dart';
import '../wrapped_data.dart';
import '../wrapped_format.dart';
import '../wrapped_store.dart';
import 'wrapped_poster.dart';

/// Сколько висит один слайд.
const int kWrSlideMs = 6000;

/// Пол высоты тела — долей экрана и абсолютным минимумом.
///
/// Короткий слайд не должен схлопывать шторку в полоску, а следующий за ним —
/// распахивать её рывком; плюс сама шторка обязана быть крупной (по референсу
/// это две трети экрана вместе с ручкой, полосками и кнопками). Доля, а не
/// одно число: на разных диагоналях «две трети» — разные точки.
const double kWrBodyFill = 0.5;
const double kWrBodyMin = 300;

/// Высота кнопки под контентом и просвет между двумя.
///
/// Заданы числом, а не набраны отступами, потому что блок кнопок ВСЕГДА ростом
/// в две штуки: на последнем слайде «Далее» уходит, но место за собой
/// оставляет. Иначе шторка на постере либо становится ниже, либо дёргается —
/// кнопка пропадает мгновенно, а тело добирает её высоту анимацией.
const double kWrCtaHeight = 46;
const double kWrCtaGap = 8;

/// Круг за контентом: диаметр, плотность и коридор насыщенности, в который
/// зажимается доминанта обложки. Края у круга честные (без размытия, как на
/// референсе), поэтому светлота ниже, чем у акцента — иначе пятно кричит
/// громче самих цифр.
const double kWrBlobSize = 300;
const double kWrBlobOpacity = 0.30;
const double kWrBlobSatMin = 0.40;
const double kWrBlobSatMax = 0.78;
const double kWrBlobLight = 0.40;

/// Кегль огромных чисел — главного приёма всех слайдов.
const double kWrNumSize = 64;

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

/// Открыть итоги периода. Период известен заранее — его называет сам вход.
Future<void> showWrappedSheet(
  BuildContext context, {
  required PeriodKind period,
  required WrappedData data,
}) => showBloomModal<void>(
  context: context,
  builder: (_) => _WrappedSheet(period: period, data: data),
);

/// Название периода — оно же подпись у входа и заголовок постера.
String periodTitle(AppLocalizations l, PeriodKind kind) => switch (kind) {
  PeriodKind.month => l.wrMonth,
  PeriodKind.year => l.wrYear,
};

/// Обложка трека итогов: снимок из журнала → библиотека.
///
/// Снимок может быть пустым (трек играл до появления журнала снимков либо
/// пришёл без обложки), поэтому фолбэк обязателен.
String? coverOfWrappedTrack(WrappedTrack track, LibraryState lib) =>
    track.cover ?? lib.tracks[track.id]?.cover;

class _WrappedSheet extends ConsumerStatefulWidget {
  const _WrappedSheet({required this.period, required this.data});

  final PeriodKind period;
  final WrappedData data;

  @override
  ConsumerState<_WrappedSheet> createState() => _WrappedSheetState();
}

class _WrappedSheetState extends ConsumerState<_WrappedSheet>
    with SingleTickerProviderStateMixin {
  int _idx = 0;

  /// Цвет круга под контентом: доминанта обложки топ-трека. `null` — обложки
  /// нет либо она не прочиталась, и круг красится акцентом темы.
  Color? _blob;

  late final AnimationController _bar =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: kWrSlideMs),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _go(1);
      });

  late final List<_SlideId> _slides = [
    _SlideId.intro,
    _SlideId.time,
    _SlideId.counts,
    _SlideId.tracks,
    if (widget.data.topArtists.isNotEmpty) _SlideId.artists,
    if (widget.data.sources.isNotEmpty) _SlideId.sources,
    if (widget.data.newArtists.isNotEmpty) _SlideId.discover,
    if (widget.data.activeDays > 0) _SlideId.habits,
    _SlideId.share,
  ];

  /// Постер не крутится сам — на нём кнопка, ждём действия человека.
  bool get _timed => _slides[_idx] != _SlideId.share;

  @override
  void initState() {
    super.initState();
    // Открыли — значит посмотрели: карточка статистики возвращается на место,
    // метка «Новое» с плашки года гаснет.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(wrappedPrefsProvider.notifier).markSeen(widget.data.range);
      }
    });
    _bar.forward();
    _loadBlob();
  }

  @override
  void dispose() {
    _bar.dispose();
    super.dispose();
  }

  Future<void> _loadBlob() async {
    final lib = ref.read(libraryProvider);
    String? cover;
    for (final tr in widget.data.topTracks) {
      cover = coverOfWrappedTrack(tr, lib);
      if (cover != null && cover.isNotEmpty) break;
    }
    final hsl = await extractCoverHsl(cover);
    if (!mounted || hsl == null) return;
    setState(() {
      _blob = HSLColor.fromAHSL(
        1,
        hsl.h,
        hsl.s.clamp(kWrBlobSatMin, kWrBlobSatMax),
        kWrBlobLight,
      ).toColor();
    });
  }

  void _go(int delta) {
    final next = _idx + delta;
    // С первого слайда назад некуда — экрана выбора периода нет.
    if (next < 0) return;
    if (next >= _slides.length) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _idx = next);
    _restartBar();
  }

  void _jump(int index) {
    if (index == _idx) return;
    setState(() => _idx = index);
    _restartBar();
  }

  void _restartBar() {
    _bar
      ..stop()
      ..value = 0;
    if (_timed) _bar.forward();
  }

  void _pause() {
    if (_bar.isAnimating) _bar.stop();
  }

  void _resume() {
    if (_timed && !_bar.isAnimating && _bar.value < 1) _bar.forward();
  }

  /// Запустить топ периода с выбранного трека — как строка в библиотеке.
  ///
  /// Журнал переживает перезапуски, а трека может уже не быть в библиотеке,
  /// поэтому всё, что она не помнит, поднимается заглушкой из снимка: площадке
  /// хватает id, чтобы дотянуть сырьё для стрима (см. `_media` в провайдерах).
  /// Что поднять не удалось (пропавший свой файл), в очередь не попадает; если
  /// это и был выбранный трек — тап просто ничего не делает.
  void _play(WrappedTrack tapped) {
    final lib = ref.read(libraryProvider);
    final queue = <Track>[];
    var start = -1;
    for (final tr in widget.data.topTracks) {
      final track = _playable(tr, lib);
      if (track == null) continue;
      if (tr.id == tapped.id) start = queue.length;
      queue.add(track);
    }
    if (start < 0) return;
    ref
        .read(playbackProvider.notifier)
        .playQueue(
          queue,
          start,
          source: PlainSource(
            id: 'wrapped:${widget.period.id}',
            label: periodTitle(context.l, widget.period),
            icon: PlainSourceIcon.chart,
          ),
        );
    Navigator.of(context).maybePop();
  }

  Track? _playable(WrappedTrack tr, LibraryState lib) {
    final known = lib.tracks[tr.id];
    if (known != null) return known;
    // У своего файла нет ни ссылки, ни пути — заглушкой его не поднять.
    if (tr.source == MusicSource.local) return null;
    return Track(
      id: tr.id,
      name: tr.name,
      artist: tr.artist,
      // В снимке лежит СУММА времени по всем прослушиваниям — длительность
      // самого трека получается делением.
      duration: Duration(seconds: tr.plays > 0 ? tr.seconds ~/ tr.plays : 0),
      source: tr.source,
      cover: tr.cover,
    );
  }

  /// Уйти на страницу артиста. Шторку закрываем сами: страница ложится в
  /// навигатор вкладки, и шторка перекрыла бы то, куда только что ушли.
  Future<void> _openArtist(WrappedArtist artist) async {
    // Слушали только свои файлы — идти некуда.
    if (artist.source == MusicSource.local) return;
    final navigator = Navigator.of(context);
    Artist? found;
    try {
      // Ищем у ТОЙ площадке, где его слушали чаще: аккаунт с тем же именем на
      // соседней — другой человек.
      final provider = ref.read(registryProvider).byId(artist.source.id);
      found = provider == null
          ? null
          : await findArtistCached(provider, artist.name);
    } catch (_) {
      // Сети нет или площадка отказала — ответ тот же, что и «не нашли».
    }
    if (!mounted) return;
    if (found == null) {
      showToast(context, context.l.artistNotFound);
      return;
    }
    navigator.maybePop();
    if (!mounted) return;
    await openArtist(context, found.id, initial: found);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final media = MediaQuery.of(context);
    final cur = _slides[_idx];
    final last = _idx == _slides.length - 1;

    // У слайда площадок круг берёт брендовый цвет главной площадки (SoundCloud
    // даёт тот самый рыжий), у остальных — доминанту обложки топ-трека.
    final blob =
        (cur == _SlideId.sources && widget.data.sources.isNotEmpty
            ? platformColor[widget.data.sources.first.source]
            : _blob) ??
        _blob ??
        t.accent;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(t.radius * 1.7),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: SheetSurface(child: SizedBox.expand()),
            ),
            // Круг за контентом — единственный цвет шторки. Уезжает от слайда к
            // слайду, поэтому и цвет, и положение едут анимацией.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedAlign(
                  alignment: _blobAlign(cur),
                  duration: const Duration(milliseconds: 550),
                  curve: Curves.easeOutCubic,
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(end: blob),
                    duration: const Duration(milliseconds: 400),
                    builder: (_, color, _) => Container(
                      width: kWrBlobSize,
                      height: kWrBlobSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (color ?? blob).withValues(
                          alpha: cur == _SlideId.share
                              ? kWrBlobOpacity * 0.75
                              : kWrBlobOpacity,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(),
                  // Полоски — они же навигация: по любой можно ткнуть и
                  // перескочить на этот слайд.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
                    child: Row(
                      children: [
                        for (var i = 0; i < _slides.length; i++) ...[
                          if (i > 0) const SizedBox(width: 5),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _jump(i),
                              child: Padding(
                                // Полоска 3 точки, а палец толще — область
                                // попадания растягиваем вверх и вниз.
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: _Bar(
                                  // Слайд без таймера показываем сразу полным.
                                  value: i < _idx || (i == _idx && !_timed)
                                      ? const AlwaysStoppedAnimation(1.0)
                                      : i == _idx
                                      ? _bar
                                      : const AlwaysStoppedAnimation(0.0),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: _onTap,
                        // Удержание — пауза, как в сторис. Кнопки и строки
                        // внутри слайда выигрывают арену у этого детектора, так
                        // что тап по ним листанием не считается.
                        onLongPressStart: (_) => _pause(),
                        onLongPressEnd: (_) => _resume(),
                        onLongPressCancel: _resume,
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 340),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: math.max(
                                kWrBodyMin,
                                media.size.height * kWrBodyFill,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                              child: KeyedSubtree(
                                key: ValueKey('${widget.period.id}:$_idx'),
                                child: _Slide(
                                  id: cur,
                                  data: widget.data,
                                  blob: blob,
                                  onPlay: _play,
                                  onArtist: _openArtist,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Кнопки внизу шторки: залитая «Далее» и под ней «Закрыть» с
                  // рамкой — выйти можно с любого слайда, не только с
                  // последнего. На постере листать уже некуда: «Далее» уходит,
                  // а «Закрыть» остаётся ровно на своём месте и САМА становится
                  // залитой — она там единственная, и быть тихой ей не перед
                  // кем. Блок при этом ростом в две кнопки ВСЕГДА (см.
                  // [kWrCtaHeight]).
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: SizedBox(
                      height: kWrCtaHeight * 2 + kWrCtaGap,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        // Без растяжки кнопки обтягивают собственный текст: в
                        // `Column` дети получают свободные ограничения по
                        // ширине, и пилюля схлопывается в кружок вокруг слова.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!last) ...[
                            _CtaButton(label: l.wrNext, onTap: () => _go(1)),
                            const SizedBox(height: kWrCtaGap),
                          ],
                          _CtaButton(
                            label: l.wrClose,
                            quiet: !last,
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onTap(TapUpDetails e) {
    final width = MediaQuery.sizeOf(context).width;
    _go(e.localPosition.dx < width * 0.33 ? -1 : 1);
  }
}

/// Куда уезжает круг на каждом слайде — порт правил `[data-slide]` из
/// `wrapped.css`. Значения за пределами [-1, 1] выводят его за край шторки,
/// как на референсе, а обрезает его сама шторка.
Alignment _blobAlign(_SlideId id) => switch (id) {
  _SlideId.intro => const Alignment(-1.15, -0.95),
  _SlideId.time => const Alignment(-0.75, -0.55),
  _SlideId.counts => const Alignment(0.35, -0.9),
  _SlideId.tracks => const Alignment(-0.95, -0.3),
  _SlideId.artists => const Alignment(0.1, -0.9),
  _SlideId.sources => const Alignment(0.6, -0.5),
  _SlideId.discover => const Alignment(-1.2, -0.6),
  _SlideId.habits => const Alignment(0.5, -1),
  _SlideId.share => const Alignment(0.1, -0.8),
};

class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final Animation<double> value;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            ColoredBox(
              color: t.text.withValues(alpha: 0.18),
              child: const SizedBox.expand(),
            ),
            AnimatedBuilder(
              animation: value,
              builder: (_, _) => FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: value.value.clamp(0.0, 1.0),
                child: ColoredBox(
                  color: t.text,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Кнопка под контентом. Главная залита цветом текста темы, как `.wrm-btn` на
/// ПК: на цветном круге это единственная плашка, которая обязана читаться при
/// любой обложке. Тихая — прозрачная с волосяной рамкой: выход не должен спорить
/// за внимание с продолжением, но и растворяться в фоне ему нельзя.
///
/// Скругление — общее [BloomTokens.radius], а не пилюля: так на референсе.
class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.onTap,
    this.quiet = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Material(
      color: quiet ? Colors.transparent : t.text,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: quiet ? BorderSide(color: t.ovlLine) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: kWrCtaHeight,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: quiet ? t.text2 : t.bg,
                fontSize: 14,
                fontWeight: quiet ? FontWeight.w600 : FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Слайды ─────────────────────────────────────────────────────────────────

class _Slide extends StatelessWidget {
  const _Slide({
    required this.id,
    required this.data,
    required this.blob,
    required this.onPlay,
    required this.onArtist,
  });

  final _SlideId id;
  final WrappedData data;
  final Color blob;
  final void Function(WrappedTrack) onPlay;
  final void Function(WrappedArtist) onArtist;

  @override
  Widget build(BuildContext context) => switch (id) {
    _SlideId.intro => _IntroSlide(data: data),
    _SlideId.time => _TimeSlide(data: data),
    _SlideId.counts => _CountsSlide(data: data),
    _SlideId.tracks => _TracksSlide(data: data, onPlay: onPlay),
    _SlideId.artists => _ArtistsSlide(data: data, onArtist: onArtist),
    _SlideId.sources => _SourcesSlide(data: data),
    _SlideId.discover => _DiscoverSlide(data: data, onArtist: onArtist),
    _SlideId.habits => _HabitsSlide(data: data),
    _SlideId.share => _ShareSlide(data: data, blob: blob),
  };
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
          delayMs: 60,
          child: _Title(switch (data.range.kind) {
            PeriodKind.month => l.wrIntroMonth,
            PeriodKind.year => l.wrIntroYear,
          }, size: 34),
        ),
        const SizedBox(height: 10),
        _FadeUp(delayMs: 120, child: _Sub(l.wrIntroSub)),
        if (joke != null) ...[
          const SizedBox(height: 16),
          _FadeUp(delayMs: 200, child: _Joke(joke)),
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
    final locale = Localizations.localeOf(context).languageCode;
    final parts = splitListenTime(l, data.seconds);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FadeUp(child: _Title(l.wrTimeKicker, size: 24)),
        const SizedBox(height: 18),
        if (parts.isEmpty)
          _FadeUp(delayMs: 140, child: _Title(l.wrTimeLessThanMin, size: 34))
        else
          for (final (i, part) in parts.indexed)
            _FadeUp(
              delayMs: 140 + i * 90,
              child: _Num(n: fmtCount(locale, part.n), word: part.word),
            ),
        const SizedBox(height: 12),
        _FadeUp(delayMs: 320, child: _Sub(l.wrTimeSub(data.plays))),
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
    final rows = <(int, String)>[
      (data.plays, l.wrPlaysWord(data.plays)),
      (data.uniqueTracks, l.wrTracksWord(data.uniqueTracks)),
      (data.uniqueArtists, l.wrArtistsWord(data.uniqueArtists)),
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FadeUp(child: _Title(l.wrCountsTitle, size: 24)),
        const SizedBox(height: 18),
        for (final (i, row) in rows.indexed)
          _FadeUp(
            delayMs: 140 + i * 90,
            child: _Num(
              n: fmtCount(locale, row.$1),
              word: row.$2,
              size: kWrNumSize * 0.72,
            ),
          ),
        if (data.newTracksCount > 0) ...[
          const SizedBox(height: 12),
          _FadeUp(
            delayMs: 420,
            child: _Sub(l.wrCountsNewTracks(data.newTracksCount)),
          ),
        ],
      ],
    );
  }
}

class _TracksSlide extends ConsumerWidget {
  const _TracksSlide({required this.data, required this.onPlay});

  final WrappedData data;
  final void Function(WrappedTrack) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final lib = ref.watch(libraryProvider);
    final top = data.topTracks;
    if (top.isEmpty) return const SizedBox.shrink();
    final first = top.first;

    // Кикера («На повторе») тут нет намеренно: обложка с числом сама говорит,
    // о чём слайд, а надпись только отжимала героя вниз.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(
          delayMs: 90,
          child: _TrackHero(
            track: first,
            cover: coverOfWrappedTrack(first, lib),
            plays: fmtCount(locale, first.plays),
            word: l.wrTimesWord(first.plays),
            onTap: () => onPlay(first),
          ),
        ),
        if (top.length > 1) ...[
          const SizedBox(height: 14),
          for (final (i, tr) in top.skip(1).indexed)
            _FadeUp(
              delayMs: 200 + i * 70,
              child: _TrackRow(
                track: tr,
                cover: coverOfWrappedTrack(tr, lib),
                value: fmtCount(locale, tr.plays),
                onTap: () => onPlay(tr),
              ),
            ),
        ],
      ],
    );
  }
}

/// Трек №1: крупная обложка, огромное число повторов и подписи под ним.
///
/// Обложка чуть завалена — как фотокарточка, брошенная на шторку. Тени под ней
/// нет намеренно: она лежит на цветном круге, и мягкое тёмное пятно читалось бы
/// грязью, а не объёмом.
class _TrackHero extends StatelessWidget {
  const _TrackHero({
    required this.track,
    required this.cover,
    required this.plays,
    required this.word,
    required this.onTap,
  });

  final WrappedTrack track;
  final String? cover;
  final String plays;
  final String word;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: -0.07,
            child: Cover(url: cover, size: 132, radius: 12),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _Num(n: plays, word: word, size: 52, gap: 7),
                const SizedBox(height: 8),
                Text(
                  track.name.isEmpty ? l.commonTrack : track.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.16,
                  ),
                ),
                if (track.artist.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.muted, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Строка топ-трека. Номера места здесь НЕТ, а счётчик — голое число: у трека
/// место читается по обложке и порядку, а «6 прослушиваний» в каждой строке
/// забивало бы её длиннее самого названия (у артистов иначе — там номер нужен,
/// см. [_ArtistRow]).
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.cover,
    required this.value,
    required this.onTap,
  });

  final WrappedTrack track;
  final String? cover;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Cover(url: cover, size: 42, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.name.isEmpty ? l.commonTrack : track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (track.artist.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: t.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: TextStyle(
                color: t.text2,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistsSlide extends ConsumerStatefulWidget {
  const _ArtistsSlide({required this.data, required this.onArtist});

  final WrappedData data;
  final void Function(WrappedArtist) onArtist;

  @override
  ConsumerState<_ArtistsSlide> createState() => _ArtistsSlideState();
}

class _ArtistsSlideState extends ConsumerState<_ArtistsSlide> {
  @override
  void initState() {
    super.initState();
    // Аватары догружаются фоном — тот же кеш, что у топа в профиле. Нет
    // ответа — останется обложка лучшего трека артиста.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(artistAvatarsProvider.notifier).ensure([
        for (final a in widget.data.topArtists)
          (name: a.name, source: a.source),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final avatars = ref.watch(artistAvatarsProvider);
    final top = widget.data.topArtists;
    if (top.isEmpty) return const SizedBox.shrink();

    String? avatar(WrappedArtist a) =>
        avatars[artistAvatarKey(a.source, a.name)] ?? a.cover;

    final first = top.first;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Герой — артист №1 по центру, как на референсе.
        _FadeUp(
          delayMs: 80,
          child: _ArtistHero(
            artist: first,
            avatar: avatar(first),
            plays: l.wrTimesN(first.plays),
            onTap: () => widget.onArtist(first),
          ),
        ),
        if (top.length > 1) ...[
          const SizedBox(height: 12),
          for (final (i, a) in top.skip(1).indexed)
            _FadeUp(
              delayMs: 200 + i * 70,
              child: _ArtistRow(
                artist: a,
                n: i + 2,
                avatar: avatar(a),
                value: l.wrTimesN(a.plays),
                onTap: () => widget.onArtist(a),
              ),
            ),
        ],
        const SizedBox(height: 14),
        _FadeUp(
          delayMs: 460,
          child: Center(
            child: _Note(l.wrArtistsTotalN(widget.data.uniqueArtists)),
          ),
        ),
      ],
    );
  }
}

class _ArtistHero extends StatelessWidget {
  const _ArtistHero({
    required this.artist,
    required this.avatar,
    required this.plays,
    required this.onTap,
  });

  final WrappedArtist artist;
  final String? avatar;
  final String plays;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Cover(url: avatar, size: 112, circle: true),
          const SizedBox(height: 13),
          Text(
            artist.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: 27,
              fontWeight: FontWeight.w900,
              height: 1.08,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(plays, style: TextStyle(color: t.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ArtistRow extends StatelessWidget {
  const _ArtistRow({
    required this.artist,
    required this.n,
    required this.avatar,
    required this.value,
    required this.onTap,
  });

  final WrappedArtist artist;
  final int n;
  final String? avatar;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                n.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: t.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Cover(url: avatar, size: 38, circle: true),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                artist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(value, style: TextStyle(color: t.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _SourcesSlide extends StatelessWidget {
  const _SourcesSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final l = context.l;
    final locale = Localizations.localeOf(context).languageCode;
    final sources = data.sources;
    if (sources.isEmpty) return const SizedBox.shrink();
    final top = sources.first;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FadeUp(child: Center(child: _Kicker(l.wrSourcesKicker))),
        const SizedBox(height: 14),
        // Герой — главная площадка: её знак крупно и число прослушиваний.
        _FadeUp(
          delayMs: 90,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              top.source == MusicSource.local
                  ? Icon(SolarIconsOutline.folder, size: 44, color: t.text)
                  : PlatformLogo(top.source, size: 46),
              const SizedBox(height: 12),
              _Num(
                n: fmtCount(locale, top.plays),
                word: l.wrPlaysWord(top.plays),
                size: 52,
                center: true,
              ),
              const SizedBox(height: 2),
              Text(
                top.source.label10n(l),
                style: TextStyle(color: t.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (sources.length > 1) ...[
          const SizedBox(height: 18),
          for (final (i, src) in sources.skip(1).indexed)
            _FadeUp(
              delayMs: 240 + i * 80,
              child: _SourceRow(
                source: src,
                share: data.plays == 0
                    ? 0
                    : (src.plays / data.plays * 100).round(),
                fill: top.plays == 0 ? 0 : src.plays / top.plays,
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
    final t = context.bloom;
    final l = context.l;
    final color = platformColor[source.source] ?? t.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (source.source != MusicSource.local)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PlatformLogo(source.source, size: 14),
                ),
              Expanded(
                child: Text(
                  source.source.label10n(l),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.text2,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '$share%',
                style: TextStyle(
                  color: t.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 5,
              child: Stack(
                children: [
                  ColoredBox(
                    color: t.text.withValues(alpha: 0.12),
                    child: const SizedBox.expand(),
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
        ],
      ),
    );
  }
}

class _DiscoverSlide extends ConsumerStatefulWidget {
  const _DiscoverSlide({required this.data, required this.onArtist});

  final WrappedData data;
  final void Function(WrappedArtist) onArtist;

  @override
  ConsumerState<_DiscoverSlide> createState() => _DiscoverSlideState();
}

class _DiscoverSlideState extends ConsumerState<_DiscoverSlide> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(artistAvatarsProvider.notifier).ensure([
        for (final a in widget.data.newArtists)
          (name: a.name, source: a.source),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final avatars = ref.watch(artistAvatarsProvider);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FadeUp(child: _Kicker(l.wrDiscoverKicker)),
        const SizedBox(height: 10),
        _FadeUp(
          delayMs: 70,
          child: _Title(
            l.wrDiscoverTitle(widget.data.newArtistsCount),
            size: 30,
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final (i, a) in widget.data.newArtists.indexed)
              _FadeUp(
                delayMs: 160 + i * 80,
                child: _ArtistChip(
                  name: a.name,
                  avatar: avatars[artistAvatarKey(a.source, a.name)] ?? a.cover,
                  onTap: () => widget.onArtist(a),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ArtistChip extends StatelessWidget {
  const _ArtistChip({
    required this.name,
    required this.avatar,
    required this.onTap,
  });

  final String name;
  final String? avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 13, 6),
        decoration: BoxDecoration(
          color: t.text.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Cover(url: avatar, size: 24, circle: true),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  const _HabitsSlide({required this.data});

  final WrappedData data;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
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
        const SizedBox(height: 8),
        _FadeUp(
          delayMs: 70,
          child: _Title(night ? l.wrHabitsNight : l.wrHabitsDay, size: 24),
        ),
        const SizedBox(height: 16),
        _FadeUp(
          delayMs: 150,
          child: SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var h = 0; h < 24; h++) ...[
                  if (h > 0) const SizedBox(width: 2),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (data.hours[h] / max).clamp(0.03, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: h == data.peakHour
                              ? t.text
                              : t.text.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 5),
        _FadeUp(
          delayMs: 190,
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
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _FadeUp(
                delayMs: 250,
                child: _Fact(
                  label: l.wrHabitsPeak,
                  value: fmtHourRange(l, data.peakHour),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FadeUp(
                delayMs: 300,
                child: _Fact(
                  label: l.wrHabitsStreak,
                  value: l.wrDaysN(data.streak),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (record != null) ...[
              Expanded(
                child: _FadeUp(
                  delayMs: 350,
                  child: _Fact(
                    label: l.wrHabitsRecord,
                    value: l.wrHabitsRecordValue(
                      l.wrTracksN(record.plays),
                      DateFormat('d MMMM', locale).format(record.date),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _FadeUp(
                delayMs: 400,
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

class _ShareSlide extends StatelessWidget {
  const _ShareSlide({required this.data, required this.blob});

  final WrappedData data;
  final Color blob;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _FadeUp(child: _Kicker(l.wrShareKicker)),
        const SizedBox(height: 14),
        // Постер и кнопка «Поделиться» живут в самой карточке — она же снимает
        // себя в PNG (см. `wrapped_poster.dart`).
        _FadeUp(
          delayMs: 100,
          child: SizedBox(
            height: 400,
            child: WrappedPosterCard(data: data, accent: blob),
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
    style: TextStyle(
      color: context.bloom.muted,
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.9,
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
      color: context.bloom.text,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.08,
      letterSpacing: -0.9,
    ),
  );
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: context.bloom.muted, fontSize: 13.5, height: 1.4),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: context.bloom.muted.withValues(alpha: 0.75),
      fontSize: 12.5,
    ),
  );
}

class _Joke extends StatelessWidget {
  const _Joke(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
      decoration: BoxDecoration(
        color: t.text.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(color: t.text2, fontSize: 13, height: 1.4),
      ),
    );
  }
}

/// Огромное число с мелкой подписью сбоку — главный приём всех слайдов.
class _Num extends StatelessWidget {
  const _Num({
    required this.n,
    required this.word,
    this.size = kWrNumSize,
    this.gap = 10,
    this.center = false,
  });

  final String n;
  final String word;
  final double size;
  final double gap;

  /// Число с подписью по центру — на слайде площадок.
  final bool center;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Row(
      mainAxisSize: center ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            n,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: size,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -size * 0.05,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        SizedBox(width: gap),
        Flexible(
          child: Text(
            word,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.muted,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
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
    style: TextStyle(
      color: context.bloom.muted.withValues(alpha: 0.7),
      fontSize: 10.5,
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.text.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.muted,
              fontSize: 10.5,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.text,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Появление элемента слайда со сдвигом снизу — десктопное `.wrm-in`
/// (`animation-delay` задавался инлайном, здесь тем же параметром).
class _FadeUp extends StatefulWidget {
  const _FadeUp({required this.child, this.delayMs = 0});

  final Widget child;
  final int delayMs;

  @override
  State<_FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<_FadeUp> with SingleTickerProviderStateMixin {
  static const int _durationMs = 450;

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
          offset: Offset(0, 12 * (1 - curve.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
