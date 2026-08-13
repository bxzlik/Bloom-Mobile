/// Шапка страницы артиста и страницы альбома/плейлиста.
///
/// Раскладка из референса: картинка во всю ширину, поверх неё сверху круглые
/// «назад» и «…», внизу по центру — название, подпись и ряд действий. Картинка
/// растворяется в фоне страницы, поэтому граница между шапкой и списком не
/// видна.
///
/// Это слайвер, а не обычный блок: при прокрутке ряд круглых кнопок остаётся
/// приклеенным к верху экрана ([StickyHero]).
///
/// Отдельно от hero трек-листа библиотеки: там левое выравнивание, свои кнопки
/// (сортировка, поиск по списку) и коллаж 2×2 вместо одной обложки.
library;

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/store/cover_store.dart';
import 'atoms.dart';
import 'bloom_mark.dart';
import 'cover_hero.dart';
import 'sticky_hero.dart';

class DetailHero extends StatelessWidget {
  const DetailHero({
    super.key,
    required this.image,
    required this.title,
    required this.subtitle,
    required this.actions,
    this.owner,
    this.onMenu,
    this.flight,
  });

  /// Картинка фона: аватар артиста или обложка сета. Баннер профиля площадки
  /// сюда НЕ идёт — на десктопе шапка артиста тоже строится на аватарке
  /// (`heroCover = artist.avatar`), а `bannerUrl` только разбирается в модель.
  final String? image;

  final String title;

  /// Владелец сета — отдельной строкой между названием и статистикой.
  final String? owner;

  /// Статистика: подписчики, число треков, год.
  final String subtitle;

  /// Ряд кнопок под подписью («Воспроизвести» + круглые).
  final Widget actions;

  /// Меню «…» справа сверху; `null` — кнопки нет.
  final VoidCallback? onMenu;

  /// Обложка карточки, с которой сюда пришли: она перелетает в [image].
  /// `null` — пришли не с карточки (у карточки не было обложки, переход из
  /// шторки), и шапка просто проявляется вместе со страницей.
  final CoverFlight? flight;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    // Картинка квадратная, но на вытянутом экране её нельзя пускать во всю
    // ширину: до кнопок пришлось бы листать. Поэтому ещё и потолок по высоте.
    final height = size.width * 0.92 < size.height * 0.5
        ? size.width * 0.92
        : size.height * 0.5;

    return StickyHero(
      height: height + 72,
      flying: flight != null,
      // Картинка идёт и под рядом действий, а кончается скруглённым краем:
      // граница со списком видна, а не размазана в фон.
      background: HeroCover(
        child: CoverHero(
          tag: flight?.tag,
          shape: BorderRadius.vertical(bottom: Radius.circular(t.radius * 1.5)),
          child: _Background(url: image, previous: flight?.image),
        ),
      ),
      barHeight: kHeaderControl,
      bar: Row(
        children: [
          GlassIconButton(
            icon: SolarIconsOutline.arrowLeft,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          if (onMenu != null)
            GlassIconButton(icon: SolarIconsOutline.menuDots, onTap: onMenu),
        ],
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineSmall?.copyWith(fontSize: 28),
          ),
          if (owner case final name? when name.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.titleMedium?.copyWith(color: t.text2),
            ),
          ],
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: theme.bodyMedium,
            ),
          ],
          const SizedBox(height: 14),
          actions,
        ],
      ),
    );
  }
}

/// Фон шапки: картинка либо приглушённый знак bloom на плёнке — как у пустой
/// обложки в [Cover], чтобы «нет картинки» выглядело одинаково везде.
class _Background extends StatelessWidget {
  const _Background({required this.url, this.previous});

  final String? url;

  /// Обложка карточки, с которой прилетели. Площадка ту же картинку отдаёт
  /// другой ссылкой (крупнее), и ответ сети приходит посреди перелёта — без
  /// подмены шапка на полкадра мигнула бы заглушкой ровно в момент посадки.
  final String? previous;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    Widget empty() => ColoredBox(
      color: t.ovlBg,
      child: Center(child: BloomMark(size: 96, color: t.text, opacity: 0.16)),
    );

    final earlier = coverImage(previous);
    Widget waiting() => earlier == null
        ? empty()
        : Image(
            image: earlier,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => empty(),
          );

    final image = coverImage(url);
    if (image == null) return waiting();
    return Image(
      image: image,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => waiting(),
      frameBuilder: (context, child, frame, wasSync) =>
          wasSync || frame != null ? child : waiting(),
    );
  }
}

/// Ряд действий шапки: широкая кнопка «Воспроизвести» и круглые рядом.
class HeroActions extends StatelessWidget {
  const HeroActions({
    super.key,
    required this.onPlay,
    required this.trailing,
    this.label = 'Воспроизвести',
  });

  /// `null` — играть нечего (страница ещё грузится или треков нет).
  final VoidCallback? onPlay;

  /// Круглые кнопки справа от «Воспроизвести».
  final List<Widget> trailing;

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final enabled = onPlay != null;
    return Row(
      children: [
        Expanded(
          child: Material(
            color: enabled ? t.accent : t.pill,
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPlay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(SolarIconsBold.play, size: 18, color: t.accentText),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: t.accentText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        for (final w in trailing) ...[const SizedBox(width: 10), w],
      ],
    );
  }
}
