/// Полноэкранный плеер. Раскладка — по референсу: шапка (свернуть / «Играет
/// из» / меню), большая обложка с ♡ и ⊕ поверх неё, название и артист по
/// центру, прогресс, транспорт отдельным блоком, под ним ряд инструментов.
///
/// Вид (цвета, плёнки, радиус) — токены десктопного Bloom.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/entities/entities.dart';
import '../../../core/store/library_store.dart';
import '../../../features/customization/custom_store.dart';
import '../../../features/customization/ui/image_thumb.dart';
import '../../../features/settings/swipe_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/marquee_text.dart';
import '../../../shared/ui/track_actions.dart';
import '../../../shared/ui/track_flick.dart';
import '../../../shared/ui/track_swipes.dart';
import '../../../shared/util/artists.dart';
import '../../../shared/util/format.dart';
import '../../detail/artists_sheet.dart';
import '../../lyrics/lyrics_store.dart';
import '../../lyrics/lyrics_style_store.dart';
import '../../lyrics/ui/lyrics_view.dart';
import '../player_controller.dart';
import '../player_style_store.dart';
import '../player_view_store.dart';
import '../sleep_timer_store.dart';
import '../slider_style_store.dart';
import '../speed_store.dart';
import '../track_anim_store.dart';
import 'player_sheet.dart';
import 'queue_sheet.dart';
import 'sleep_sheet.dart';
import 'slider_shapes.dart';
import 'source_pill.dart';
import 'speed_sheet.dart';
import 'track_swap.dart';
import 'vinyl_disc.dart';

/// Радиус обложки в плеере — заметно круглее блоков (как в референсе).
const double _coverRadius = 20;

/// Просвет между пилюлей источника и круглыми кнопками шапки.
const double _headerGap = 8;

/// Что уходит в буфер по тапу на название: «Название — Артист», как на ПК
/// (`TitleCopyOnClick`: `title + ' — ' + artist`). Артиста нет — одно название,
/// иначе в буфере оставалось бы висящее тире.
String trackCopyText(Track track) {
  final artist = track.artist.trim();
  return artist.isEmpty ? track.name : '${track.name} — $artist';
}

/// Содержимое плеера во весь экран.
///
/// Не экран и не маршрут: его строит панель ([PlayerSheet]) внутри растущей
/// карточки и обрезает своим окном, пока та не дошла до краёв. Отсюда два
/// следствия. Раскладка всегда считается по ПОЛНОМУ экрану, сколько бы от неё
/// сейчас ни было видно, — иначе на середине разворота она сжималась бы и в
/// конце прыгала. А закрывается плеер не `pop`, а [collapsePlayerSheet]: своего
/// маршрута у него нет.
///
/// `Scaffold` тут нужен не ради раскладки, а ради тостов: `ScaffoldMessenger`
/// показывает их на последнем собранном `Scaffold`, и без своего они выезжали
/// бы на каркасе — то есть ПОД панелью.
class FullPlayerBody extends ConsumerStatefulWidget {
  const FullPlayerBody({super.key});

  @override
  ConsumerState<FullPlayerBody> createState() => _FullPlayerBodyState();
}

class _FullPlayerBodyState extends ConsumerState<FullPlayerBody> {
  @override
  void initState() {
    super.initState();
    // Текст просим сразу на открытии плеера, даже если панель закрыта: от
    // того, нашёлся ли он, зависит САМА кнопка «Т» — на треке без текста её
    // быть не должно (порт `useLyricsBtnVisible` с ПК).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(lyricsProvider.notifier)
          .ensureFor(ref.read(playbackProvider).track);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final track = state.track;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    final lyricsMode = ref.watch(lyricsStyleProvider).mode;

    // Опустевшую очередь ловит панель, а не мы: играть больше нечего — значит
    // нет и карточки, из которой она растёт (см. `PlayerSheet`).
    ref.listen(playbackProvider, (prev, next) {
      // Текст тянем на КАЖДОЙ смене трека, как на ПК (`loadPlay` →
      // `requestLyrics`), а не только при открытой панели: иначе неоткуда
      // узнать, прятать ли кнопку «Т».
      if (prev?.track?.id != next.track?.id) {
        ref.read(lyricsProvider.notifier).ensureFor(next.track);
      }
    });

    // У нового трека текста не нашлось — панель закрываем сами (порт
    // `useLyricsBridge` с ПК). Ловим именно ПЕРЕХОД в «пусто»: на загрузке
    // панель не трогаем, иначе она мигала бы на каждой смене трека.
    ref.listen(lyricsProvider, (prev, next) {
      if (next.status != LyricsStatus.empty ||
          prev?.status == LyricsStatus.empty) {
        return;
      }
      ref.read(lyricsOpenProvider.notifier).state = false;
    });

    final swipes = ref.watch(swipeProvider).of(SwipeZone.player);

    return Scaffold(
      backgroundColor: t.bg,
      // Тяги вниз здесь нет: панель ловит её сама, снаружи содержимого — иначе
      // жест пришлось бы заводить дважды и они спорили бы за палец.
      //
      // Горизонтальный жест ловится со всего экрана, а едут от него обложка и
      // подписи: тянуть плеер целиком незачем — шапка и транспорт к треку не
      // относятся. Своя ловушка прогресса ниже перебивает этот жест, как и
      // положено ближнему детектору.
      body: TrackFlick(
        onLeft: track == null || swipes.left == SwipeAction.none
            ? null
            : () => runSwipeAction(
                context,
                ref,
                swipes.left,
                track: track,
                fromFlick: true,
              ),
        onRight: track == null || swipes.right == SwipeAction.none
            ? null
            : () => runSwipeAction(
                context,
                ref,
                swipes.right,
                track: track,
                fromFlick: true,
              ),
        builder: (context, shift) => SafeArea(
          // Низ — не `SafeArea`, а [bottomEdgeInset]: ряд инструментов
          // обязан кончаться там же, где кромка таб-бара под списком,
          // иначе открытие плеера выглядит как прыжок раскладки. Заодно
          // на iOS полный вырез под home indicator (34) поднял бы весь низ
          // заметно выше, чем на андроиде.
          bottom: false,
          child: track == null
              ? const SizedBox.shrink()
              : Padding(
                  // Сверху воздух: шапка не должна липнуть к статус-бару.
                  padding: EdgeInsets.fromLTRB(
                    16,
                    14,
                    16,
                    bottomEdgeInset(context),
                  ),
                  child: Column(
                    children: [
                      _Header(track: track, state: state),
                      const SizedBox(height: 16),
                      // Обложка по центру свободного места — или текст на её
                      // месте, если выбран вид «вместо обложки». В виде
                      // «поверх» обложка остаётся, а текст ложится на неё
                      // самой карточкой (см. `_Cover`).
                      // Именно `Expanded`, а не `Flexible`: панель текста —
                      // скролл, и по свободным ограничениям он берёт высоту
                      // по СОДЕРЖИМОМУ. Пока текст грузится, содержимое —
                      // одна строчка «Загрузка текста…», колонка схлопывалась
                      // и весь низ экрана уезжал вверх (поймал он). Обложке
                      // это ничего не меняет: её `Center` и раньше занимал
                      // всё свободное место.
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 260),
                          child: lyricsOpen && lyricsMode == LyricsMode.replace
                              ? const _LyricsPane(key: ValueKey('lyrics'))
                              : Center(
                                  key: const ValueKey('cover'),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: FlickSlide(
                                      shift: shift,
                                      child: _Cover(
                                        state: state,
                                        lyricsOpen:
                                            lyricsOpen &&
                                            lyricsMode == LyricsMode.overlay,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      // Отступы вокруг названия одинаковые: оно должно стоять
                      // ровно посередине между обложкой и прогрессом. Снизу
                      // те же ~24 набегают из полей вокруг имени артиста, этой
                      // восьмёрки и верхней половины ловушки прогресса
                      // (`_Progress.slack`).
                      const SizedBox(height: 24),
                      // Подписи отзываются вдвое слабее обложки: они уже
                      // самой карточки, и на одном с ней ходу успевали бы
                      // улететь за край раньше неё.
                      FlickSlide(
                        shift: shift,
                        amplitude: 0.5,
                        child: _TitleBlock(state: state),
                      ),
                      const SizedBox(height: 8),
                      const _Progress(),
                      const SizedBox(height: 16),
                      const _Transport(),
                      const SizedBox(height: 12),
                      _Tools(queueCount: state.queue.length),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.track, required this.state});

  /// Текущий трек — он уходит в меню под тремя точками.
  final Track track;

  /// Состояние плеера: пилюле нужны источник очереди и флаг перемешки.
  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        CircleIconButton(
          icon: SolarIconsOutline.altArrowDown,
          iconSize: 23,
          // Не `pop`: плеер — слой каркаса, а не маршрут (см. `PlayerSheet`).
          onTap: collapsePlayerSheet,
        ),
        // Пилюля источника — та же плёнка и та же высота, что у круглых кнопок
        // по краям: шапка читается одной ровной строкой, а не ступенькой. Имя
        // источника бывает длинным, поэтому она забирает весь остаток ширины и
        // ужимается по содержимому уже внутри. Просветы по бокам обязательны:
        // без них длинное имя раздувает пилюлю впритык к кружкам, и все три
        // плёнки слипаются в одну полосу.
        const SizedBox(width: _headerGap),
        Expanded(
          child: SourcePill(source: state.source, shuffle: state.shuffle),
        ),
        const SizedBox(width: _headerGap),
        CircleIconButton(
          icon: SolarIconsOutline.menuDots,
          onTap: () => showTrackActions(context, ref, track),
        ),
      ],
    );
  }
}

/// Текст на месте обложки — вид «вместо обложки».
///
/// Занимает ВСЁ свободное место колонки, а не квадрат обложки: строк на экран
/// влезает заметно больше, и ради этого вид и заводился.
class _LyricsPane extends StatelessWidget {
  const _LyricsPane({super.key});

  @override
  Widget build(BuildContext context) => const LyricsView(
    padding: EdgeInsets.fromLTRB(8, 24, 8, 24),
    // Своя раскладка: крупнее и по левому краю — коробка тут во всю ширину
    // экрана, а не квадрат обложки (см. `LyricsLayout`).
    layout: LyricsLayout.replace,
  );
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.state, this.lyricsOpen = false});

  final PlaybackState state;

  /// Панель текста поверх обложки открыта — вид «поверх обложки».
  final bool lyricsOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = state.track!;
    final isFav = ref.watch(libraryProvider).isFav(track.id);
    final anim = ref.watch(trackAnimProvider).of(TrackAnimSurface.player);
    // Пластинка (`playerStyle: 'vinyl'` с ПК): круглая обложка, вращение и
    // тёмная этикетка по центру.
    final vinyl = ref.watch(playerStyleProvider).isVinyl;
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.biggest.shortestSide;
        // Круг — тот же радиус, доведённый до половины стороны: всё, что
        // обрезается рамкой обложки (сама картинка, панель текста), становится
        // круглым разом.
        final radius = vinyl ? side / 2 : _coverRadius;
        // Крутим ТОЛЬКО пока идёт звук — десктопное `vinyl-paused`
        // (`animation-play-state:paused`). Состояние берём у самого плеера, а
        // не у `PlaybackState`: там его нет, а пауза из шторки и с гарнитуры
        // обязана останавливать диск так же, как кнопка на экране.
        final player = ref.watch(audioPlayerProvider);
        return Stack(
          children: [
            // Слои смены трека клипует сама рамка обложки, а картинки внутри
            // идут БЕЗ своего радиуса: иначе уезжающая показывала бы
            // скруглённый угол посреди кадра. Кнопки стоят рядом со слоями, а
            // не внутри, — ♡ и ⊕ никуда не едут (на ПК у них свой z-index).
            SizedBox(
              width: side,
              height: side,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: VinylSpin(
                  // Вращается вся стопка слоёв смены трека, а не одна текущая
                  // картинка: иначе приезжающая обложка встала бы ровно, а
                  // уезжающая продолжала крутиться — два разных движения в
                  // одном кадре.
                  //
                  // Начальное состояние берём у плеера (`playing`), дальше за
                  // ним следит поток: он отдаёт значение не сразу, а первый
                  // кадр диск уже обязан либо крутиться, либо стоять.
                  enabled: vinyl,
                  spinning: player.playing,
                  playing: player.playingStream,
                  child: TrackSwap(
                    id: track.id,
                    kind: anim.cover,
                    child: Cover(
                      // Своя обложка из «Кастомизации» важнее обложки трека —
                      // десктопный `coverOverride`.
                      url:
                          ref.watch(customSrcProvider(CustomCtx.cover)) ??
                          track.cover,
                      size: side,
                      radius: 0,
                    ),
                  ),
                ),
              ),
            ),
            // Этикетка — порт `.ps-cover.vinyl-mode::after`. Стоит НАД
            // обложкой, но под панелью текста и кнопками (на ПК у неё
            // z-index 3, у них 4) и, само собой, не крутится вместе с диском.
            if (vinyl)
              Positioned(
                left: 0,
                top: 0,
                width: side,
                height: side,
                child: Center(child: VinylLabel(size: side * VinylLabel.share)),
              ),
            // Панель текста поверх обложки — порт `.lyrics-panel` с ПК: та же
            // подложка (цвет блока, 96%) и то же появление (прозрачность плюс
            // лёгкий наплыв). Рисуется ВСЕГДА, видимость даёт прозрачность:
            // иначе анимации не из чего играть. Кнопки ♡ и ⊕ стоят ПОСЛЕ неё —
            // остаются нажимаемыми поверх текста, как на ПК.
            Positioned(
              left: 0,
              top: 0,
              width: side,
              height: side,
              child: IgnorePointer(
                ignoring: !lyricsOpen,
                child: AnimatedOpacity(
                  opacity: lyricsOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: AnimatedScale(
                    scale: lyricsOpen ? 1 : 0.97,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(radius),
                      child: ColoredBox(
                        color: context.bloom.blockColor.withValues(alpha: 0.96),
                        child: LyricsView(
                          active: lyricsOpen,
                          // В круге текст обязан отступить от краёв заметно
                          // сильнее, иначе строки упираются в дугу (на ПК ровно
                          // это и делает `.vinyl-mode #lyricsPanel` — 52 px на
                          // диске 380, наши 14%).
                          padding: vinyl
                              ? EdgeInsets.all(side * 0.14)
                              : const EdgeInsets.fromLTRB(14, 28, 14, 28),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: _CoverButton(
                icon: isFav ? SolarIconsBold.heart : SolarIconsOutline.heart,
                color: isFav ? const Color(0xFFFF5578) : Colors.white,
                onTap: () =>
                    ref.read(libraryProvider.notifier).toggleFav(track),
              ),
            ),
            // Именно addCircle, а не plus: в solar_icons 0.1.0 `plus` и `minus`
            // сидят на одном коде 0xec4a и рисуются знаком «±» из
            // калькуляторной группы. В референсе тут и так ⊕.
            Positioned(
              right: 10,
              bottom: 10,
              child: _CoverButton(
                icon: SolarIconsOutline.addCircle,
                iconSize: 24,
                onTap: () => showAddToPlaylistSheet(context, ref, track),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Кнопка НА ОБЛОЖКЕ: подложка честно чёрная, штрих белый — под ней всегда
/// картинка, а не поверхность темы. Тонкая светлая рамка нужна, чтобы кружок
/// читался и на почти чёрной обложке, где одной заливки не видно.
class _CoverButton extends StatelessWidget {
  const _CoverButton({
    required this.icon,
    this.iconSize = 22,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final double iconSize;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: CircleIconButton(
        icon: icon,
        iconSize: iconSize,
        size: 48,
        background: Colors.black.withValues(alpha: 0.45),
        color: color ?? Colors.white,
        onTap: onTap,
      ),
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.state});

  final PlaybackState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = state.track!;
    final theme = Theme.of(context).textTheme;

    // По имени артиста уходим на его страницу — как из меню трека; артистов в
    // строке несколько — сперва шторка с выбором. На месте имени может стоять
    // ошибка воспроизведения: тогда строка просто текст. Одиночного артиста
    // без точного id открывать тоже нечем.
    final canOpen =
        state.error == null &&
        (track.artistId != null || parseArtists(track.artist).length > 1);

    // Куда прижаты название с артистом — настройка «Выравнивание заголовка»
    // (порт десктопного `titleAlign`, там это классы `.title-left/.title-right`
    // на `#playerContent`).
    final align = ref.watch(titleAlignProvider);

    final subtitle = Text(
      state.error ?? track.artist,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align.text,
      // Крупнее общей подписи (13): в плеере под названием стоит одна
      // строка, и она должна читаться с руки.
      style: theme.bodyMedium?.copyWith(
        fontSize: 16,
        color: state.error != null ? t.sysFavIco : null,
      ),
    );

    // Ловушка под палец шире самой строки — но только со СВОБОДНОЙ стороны:
    // прижатый заголовок обязан начинаться там же, где полоса прогресса и время
    // под ней, а лишние 20 px по краю утаскивали бы его внутрь. По центру
    // отступ остаётся с обеих сторон: там он ничего не двигает, только держит
    // строку от краёв.
    final pad = switch (align) {
      TitleAlign.left => const EdgeInsets.only(right: 20),
      TitleAlign.center => const EdgeInsets.symmetric(horizontal: 20),
      TitleAlign.right => const EdgeInsets.only(left: 20),
    };

    // Слои подписи занимают всю ширину колонки — иначе слайд считался бы от
    // ширины самого текста и короткое название ехало бы заметно меньше
    // длинного. Куда встают сами строки внутри — дело колонки: строка, которая
    // влезла, шириной равна тексту, и одним `textAlign` её не подвинуть.
    return SizedBox(
      width: double.infinity,
      child: TrackSwap(
        id: track.id,
        kind: ref.watch(trackAnimProvider).of(TrackAnimSurface.player).text,
        child: Column(
          crossAxisAlignment: align.cross,
          children: [
            // Тап по названию копирует «Название — Артист» (порт
            // `TitleCopyOnClick` с ПК). Ловушка шире самой строки — по бокам, а
            // не по высоте: сверху и снизу отступы выверены, лишние пиксели
            // сдвинули бы весь блок.
            GestureDetector(
              onTap: () => _copy(context, track),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad,
                // Название бежит, если не влезло, — порт `MarqueeTitle` с ПК.
                // На ходу строка идёт от левого края, в покое — по настройке.
                child: MarqueeText(
                  track.name,
                  align: align.text,
                  style: theme.headlineSmall,
                ),
              ),
            ),
            // Отступ до имени даёт сама ловушка под палец: одной строкой текста
            // в 19 px по центру экрана попасть тяжело.
            GestureDetector(
              onTap: canOpen
                  ? () => openTrackArtist(context, ref, track)
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: pad + const EdgeInsets.symmetric(vertical: 7),
                child: subtitle,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// «Название — Артист» в буфер, как на ПК.
  Future<void> _copy(BuildContext context, Track track) async {
    if (track.name.isEmpty) return;
    final l = context.l;
    try {
      await Clipboard.setData(ClipboardData(text: trackCopyText(track)));
      if (context.mounted) {
        showToast(context, l.playerCopied, kind: ToastKind.success);
      }
    } catch (_) {
      if (context.mounted) {
        showToast(context, l.playerCopyError, kind: ToastKind.error);
      }
    }
  }
}

class _Progress extends ConsumerStatefulWidget {
  const _Progress();

  /// Толщина дорожки обычного типа и высота ловушки под палец.
  ///
  /// Слайдер без кружка и без ореола ужимается по высоте до самой дорожки, а в
  /// 5 px пальцем не попасть — перемотать получалось, только ткнув точно в
  /// полоску. Растягиваем его на [hit]: дорожку он рисует по центру своей
  /// высоты, а нажатие ловит всей площадью.
  ///
  /// Ловушка одна на все типы слайдера, хотя дорожки у них разной толщины
  /// (`sliderTrackHeight`, самая высокая — волна в 28): иначе смена типа
  /// двигала бы под собой времена и весь низ плеера.
  static const double trackHeight = 5;

  /// Пустота, которая при этом остаётся над и под дорожкой внутри ловушки.
  ///
  /// Ловушка симметричная, а вот воздух вокруг дорожки — нет: снизу к пустоте
  /// прибавляется ещё и верхний отступ строки времён (у `bodyMedium` над
  /// цифрами есть свой межстрочный запас), и провал под полоской выходит явно
  /// шире, чем над ней. Поэтому [slack] держим по нижней стороне, а недостачу
  /// сверху добирает `SizedBox` перед прогрессом.
  static const double slack = 12;

  static const double hit = trackHeight + slack * 2;

  @override
  ConsumerState<_Progress> createState() => _ProgressState();
}

class _ProgressState extends ConsumerState<_Progress> {
  /// Позиция под пальцем, пока тянут (мс). Пока она не null — дорожка и время
  /// слева живут от неё, а не от плеера.
  ///
  /// Иначе `Slider` (он управляемый) рисует то, что пришло из стрима, и
  /// заливка отпрыгивает назад к фактической позиции — резинка. Перематываем
  /// один раз, на отпускании: seek по сетевому стриму дорогой, а на каждый
  /// кадр перетаскивания их набегают десятки.
  double? _drag;

  Future<void> _commit(double v) async {
    await ref
        .read(playbackProvider.notifier)
        .seek(Duration(milliseconds: v.round()));
    // Отпускаем только после самой перемотки: до неё стрим отдаёт ещё старую
    // позицию, и полоска моргнула бы назад.
    if (mounted) setState(() => _drag = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final head =
        ref.watch(playheadProvider).value ??
        (position: Duration.zero, total: Duration.zero);

    // Картинка ползунка декодируется асинхронно: пока её нет (или её не
    // выбирали), дорожка живёт без пуговки, как и раньше.
    final thumb = ref.watch(sliderThumbProvider).value;
    final style = ref.watch(sliderStyleProvider);
    // Узор волны — свой на каждый трек, как на ПК (`regenWave` на смену
    // трека); id и есть зерно.
    final seed = ref.watch(playbackProvider.select((s) => s.track?.id)) ?? '';

    final max = head.total.inMilliseconds.toDouble();
    final live = max <= 0
        ? 0.0
        : head.position.inMilliseconds
              .clamp(0, head.total.inMilliseconds)
              .toDouble();
    final value = (_drag ?? live).clamp(0.0, max <= 0 ? 0.0 : max);

    return Column(
      children: [
        SizedBox(
          height: _Progress.hit,
          child: SliderTheme(
            // Вид дорожки и пуговки — целиком из типа слайдера (настройка
            // «Плеер → Слайдер»). У обычного типа это ровно то, что было:
            // дорожка в 5 (толще общей тройки — это главный орган управления
            // экрана, а не строка настройки) и без кружка, если в
            // «Кастомизации» не выбрали картинку ползунка.
            data: bloomSliderTheme(
              SliderTheme.of(context),
              style: style,
              tokens: context.bloom,
              thumbImage: thumb,
              waveSeed: seed.hashCode,
            ),
            child: Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: max <= 0 ? null : _commit,
            ),
          ),
        ),
        // Времена стоят сразу под ловушкой: весь воздух до дорожки они
        // получают из её нижней половины (`_Progress.slack`).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Тем же цветом, что артист под названием (`bodyMedium`).
              Text(
                mmss(Duration(milliseconds: value.round())),
                style: theme.bodyMedium,
              ),
              Text(mmss(head.total), style: theme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

/// Блок-контейнер: плёнка + рамка + радиус темы.
class _Block extends StatelessWidget {
  const _Block({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: t.ovlBg,
        border: Border.all(color: t.ovlLine),
        // Круглее общего блока: у транспорта углы мягче, чем у карточек.
        borderRadius: BorderRadius.circular(t.radius * 1.8),
      ),
      child: child,
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final state = ref.watch(playbackProvider);
    final ctrl = ref.read(playbackProvider.notifier);
    final player = ref.watch(audioPlayerProvider);

    // Режим повтора различаем бейджем, а не подменой иконки (как на ПК): сама
    // кнопка всегда repeat, сверху справа — «список» для всей очереди и «1» для
    // одного трека.
    final repeatMark = switch (state.repeat) {
      PlayerRepeat.all => Icon(
        SolarIconsOutline.list,
        size: 9,
        color: t.accentText,
      ),
      PlayerRepeat.one => Text(
        '1',
        style: TextStyle(
          fontSize: 8,
          // Цифра оптически сидит выше центра — прижимаем высотой строки.
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: t.accentText,
        ),
      ),
      _ => null,
    };

    return _Block(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _FlatIcon(
            icon: SolarIconsOutline.repeat,
            size: 24,
            active: state.repeat != PlayerRepeat.off,
            onTap: ctrl.cycleRepeat,
            mark: repeatMark,
          ),
          _FlatIcon(
            icon: SolarIconsBold.skipPrevious,
            size: 30,
            onTap: ctrl.prev,
          ),
          SizedBox(
            width: 68,
            height: 68,
            // На загрузке круг ОСТАЁТСЯ на месте, спиннер рисуется внутри него:
            // иначе транспорт на каждом переходе трека визуально схлопывается.
            child: state.loading
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: t.accentText,
                        ),
                      ),
                    ),
                  )
                : StreamBuilder<bool>(
                    stream: player.playingStream,
                    initialData: player.playing,
                    builder: (context, snap) => Material(
                      color: t.accent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: ctrl.toggle,
                        child: Icon(
                          snap.data == true
                              ? SolarIconsBold.pause
                              : SolarIconsBold.play,
                          size: 28,
                          color: t.accentText,
                        ),
                      ),
                    ),
                  ),
          ),
          _FlatIcon(icon: SolarIconsBold.skipNext, size: 30, onTap: ctrl.next),
          _FlatIcon(
            icon: SolarIconsOutline.shuffle,
            size: 24,
            active: state.shuffle,
            onTap: ctrl.toggleShuffle,
          ),
        ],
      ),
    );
  }
}

/// Кнопка таймера сна. Отдельным виджетом, а не строчкой в [_Tools]: пока
/// таймер идёт, состояние тикает раз в секунду, и перерисовывать из-за этого
/// весь ряд инструментов незачем.
///
/// Идущий таймер показывает остаток ВМЕСТО луны — тем же приёмом, что кнопка
/// скорости показывает `1.25×`.
class _SleepButton extends ConsumerWidget {
  const _SleepButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sleep = ref.watch(sleepTimerProvider);
    // Метка нужна своя: остаток вместо иконки скринридер прочёл бы как голое
    // «23:14», без единого слова о том, что это вообще такое.
    return Semantics(
      button: true,
      label: context.l.playerSleep,
      child: _FlatIcon(
        icon: sleep.mode == SleepMode.endOfTrack
            ? SolarIconsBold.moonSleep
            : SolarIconsOutline.moonSleep,
        size: 26,
        label: sleep.mode == SleepMode.timer
            ? sleepLabel(sleep.remaining)
            : null,
        active: sleep.active,
        onTap: () => showSleepSheet(context),
      ),
    );
  }
}

class _FlatIcon extends StatelessWidget {
  const _FlatIcon({
    required this.icon,
    this.onTap,
    this.size = 22,
    this.active = false,
    this.badge,
    this.mark,
    this.label,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool active;
  final int? badge;

  /// Мини-бейдж в кружке акцента поверх иконки (перенос .cc-badge с ПК): им
  /// различаем режимы кнопки, чтобы не подменять саму иконку.
  final Widget? mark;

  /// Надпись ВМЕСТО иконки — перенос `.cc-cap` с ПК: кнопка скорости при
  /// значении не 1× показывает само значение, а не спидометр.
  final String? label;

  /// Ширина коробки надписи. Фиксированная, а не по тексту: иначе ряд
  /// инструментов расходился бы на каждой смене скорости. Длинное значение
  /// (`1.35×`) внутри неё поджимается [FittedBox].
  static const double _labelWidth = 34;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = active ? t.accent : t.iconFg;
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (label == null)
              Icon(icon, size: size, color: color)
            else
              SizedBox(
                width: _labelWidth,
                height: size,
                child: FittedBox(
                  child: Text(
                    label!,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1,
                      color: color,
                    ),
                  ),
                ),
              ),
            if (badge != null)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$badge',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: t.accentText,
                    ),
                  ),
                ),
              ),
            if (mark != null)
              Positioned(
                right: -4,
                top: -3,
                child: Container(
                  width: 14,
                  height: 14,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: mark,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tools extends ConsumerWidget {
  const _Tools({required this.queueCount});

  final int queueCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Скорость: пока она 1×, кнопка — обычный спидометр; иначе на её месте
    // само значение, как `cc-cap` в десктопном транспорте.
    final rate = ref.watch(speedProvider).rate;
    final lyricsOpen = ref.watch(lyricsOpenProvider);
    // Кнопки «Т» нет, пока текст не нашёлся, — как на ПК
    // (`useLyricsBtnVisible`). Открытую панель кнопка переживает в любом
    // случае: иначе её было бы нечем закрыть.
    final lyricsFound = ref.watch(lyricsProvider).status == LyricsStatus.ready;

    return _Block(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (lyricsFound || lyricsOpen)
            _FlatIcon(
              icon: SolarIconsOutline.text,
              size: 26,
              active: lyricsOpen,
              onTap: () =>
                  ref.read(lyricsOpenProvider.notifier).state = !lyricsOpen,
            ),
          const _FlatIcon(icon: SolarIconsOutline.tuning, size: 26),
          const _SleepButton(),
          _FlatIcon(
            icon: SolarIconsOutline.speedometerMiddle,
            size: 26,
            label: rate == 1 ? null : speedLabel(rate),
            active: rate != 1,
            onTap: () => showSpeedSheet(context),
          ),
          _FlatIcon(
            icon: SolarIconsOutline.playlistMinimalistic,
            size: 26,
            badge: queueCount > 0 ? queueCount : null,
            onTap: queueCount > 0 ? () => showQueueSheet(context) : null,
          ),
        ],
      ),
    );
  }
}
