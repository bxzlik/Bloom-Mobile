/// Страница профиля — порт десктопной `ProfileCard` из `AccountPage`.
///
/// Раскладка мобильная (из присланного макета): обложка полосой сверху, аватар
/// по центру на её нижней кромке, под ним ник и широкий бокс «о себе / статус».
/// Десктопной строки «Слушает сейчас» здесь нет — он попросил её убрать.
///
/// Десктопные вкладки «Статистика» и «Достижения» здесь не вкладки, а две
/// кнопки: содержимое открывается нижними шторками (`stats_sheet.dart` и
/// `achievements_sheet.dart`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/router.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../../shared/ui/glass.dart';
import '../../wrapped/ui/wrapped_entries.dart';
import '../../wrapped/wrapped_store.dart';
import '../achievements.dart';
import '../profile_store.dart';
import '../stats.dart';
import 'achievements_sheet.dart';
import 'profile_avatar.dart';
import 'profile_entry_card.dart';
import 'stats_sheet.dart';

/// Сторона аватара на странице — десктопные 120 из `.acc-ava`.
const double kProfileAvatarSize = 120;

/// Высота полосы обложки без системной строки. Знает не только страница:
/// предпросмотр в редакторе строит шапку по тем же меркам, и по ним же
/// кроппер режет выбранную картинку.
const double kProfileBannerStrip = 168;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.flight});

  /// Метка перелёта аватара с кнопки в шапке главной.
  final CoverFlight? flight;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with WidgetsBindingObserver {
  /// Метку держим у себя: `extra` живёт на ВСЮ ссылку, и стоит уйти отсюда в
  /// редактор, как страница профиля перестраивается уже без неё — аватару
  /// стало бы некуда лететь на обратном пути.
  late CoverFlight? _flight = widget.flight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Приложение может провисеть открытым до 1-го числа: сверяем дату по
    // возвращению из фона, иначе входы в «Итоги» дожили бы до перезапуска со
    // вчерашним периодом. На ПК ту же роль играет слушатель `focus` у окна.
    if (state == AppLifecycleState.resumed) {
      ref.read(wrappedDayProvider.notifier).refresh();
    }
  }

  @override
  void didUpdateWidget(ProfileScreen old) {
    super.didUpdateWidget(old);
    if (widget.flight != null) _flight = widget.flight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    final flight = _flight;

    return ListView(
      // Только снизу: сверху баннер уходит под статус-бар, а внизу над
      // содержимым плавают миниплеер и таб-бар.
      padding: EdgeInsets.only(bottom: bottomBarsInset(context)),
      children: [
        _Banner(profile: profile, flight: flight),
        HeroContent(
          flying: flight != null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: Column(
              children: [
                // Тап по нику копирует его — то же, что клик по `.acc-name`.
                GestureDetector(
                  onTap: () =>
                      _copyNick(context, profile.displayName(context.l)),
                  child: Text(
                    profile.displayName(context.l),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.headlineSmall?.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 14),
                _AboutBox(profile: profile),
                const SizedBox(height: 16),
                // Статистика и достижения живут в шторках, а не вкладками под
                // карточкой: на странице от них остаются две кнопки, и профиль
                // не растёт вниз на три экрана.
                const _SheetButtons(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _copyNick(BuildContext context, String name) {
    Clipboard.setData(ClipboardData(text: name));
    showToast(context, context.l.profileNickCopied, kind: ToastKind.success);
  }
}

/// Входы в шторки — две широкие карточки одного вида: статистика и достижения.
///
/// Над ними в декабре встаёт плашка «Итоги года», а сама карточка статистики
/// раз в месяц ПОДМЕНЯЕТСЯ входом в итоги месяца — ровно до первого просмотра
/// (см. `wrapped_entries.dart`). А всю первую неделю месяца уже вернувшаяся
/// карточка чередует своё число с надписью «Итоги месяца» (`monthHint`).
class _SheetButtons extends ConsumerWidget {
  const _SheetButtons();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrapped = ref.watch(wrappedEntriesProvider);
    final year = wrapped.year;
    final month = wrapped.month;

    return Column(
      children: [
        if (year != null) ...[
          WrappedYearBanner(data: year, unseen: wrapped.yearUnseen),
          const SizedBox(height: 10),
        ],
        if (month != null && wrapped.monthUnseen)
          WrappedMonthCard(data: month)
        else
          const _StatsCard(),
        const SizedBox(height: 10),
        const _AchCard(),
      ],
    );
  }
}

/// Статистика: слева сколько треков прослушано, справа сколько всего слушали,
/// у края — коллаж из обложек топа.
class _StatsCard extends ConsumerWidget {
  const _StatsCard();

  /// Время в часах с десятой долей — как на макете («11,9ч»). Меньше часа
  /// показываем минутами: «0,3ч» ни о чём не говорит.
  String _time(BuildContext context, int seconds) {
    if (seconds < 3600) return fmtDurLong(context, seconds);
    final hours = NumberFormat.decimalPatternDigits(
      locale: Localizations.localeOf(context).toString(),
      decimalDigits: 1,
    ).format(seconds / 3600);
    return context.l.statsHoursValue(hours);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final s = ref.watch(profileStatsProvider);
    final hint = ref.watch(wrappedEntriesProvider.select((e) => e.monthHint));

    return ProfileEntryCard(
      value: '${s.totalPlays}',
      icon: SolarIconsOutline.musicNote,
      side: _time(context, s.listenSec),
      // Первую неделю месяца число чередуется с «Итогами месяца». Цель нажатия
      // при этом не меняется — сами итоги открывает кнопка внизу шторки.
      alt: hint ? context.l.wrMonth : null,
      // Обложки самых слушаемых треков — тот же коллаж, что у списков без
      // своей картинки.
      tile: Cover(
        url: null,
        covers: [for (final row in s.topTracks) row.track.cover],
        size: 56,
        radius: t.radius * 0.6,
      ),
      onTap: () => showStatsSheet(context),
    );
  }
}

/// Достижения: слева сколько уровней взято, справа сколько их всего.
class _AchCard extends ConsumerWidget {
  const _AchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final list = ref.watch(achievementsProvider);
    final done = list.fold(0, (n, a) => n + a.tierReached);
    final total = list.length * kTierOrder.length;
    // Плитка горит золотом, только когда взято хоть что-то, — как медаль на
    // карточке достижения.
    final medal = done > 0 ? tierColor(AchTier.gold) : t.muted;

    return ProfileEntryCard(
      value: '$done',
      icon: SolarIconsOutline.medalStar,
      side: '$total',
      tile: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: medal.withValues(alpha: done > 0 ? 0.16 : 0.06),
          borderRadius: BorderRadius.circular(t.radius * 0.6),
        ),
        child: Icon(SolarIconsBold.medalStar, size: 28, color: medal),
      ),
      onTap: () => showAchievementsSheet(context),
    );
  }
}

/// Обложка полосой: своя картинка либо цвет/градиент, поверх — кнопки, на
/// нижней кромке — аватар.
class _Banner extends StatelessWidget {
  const _Banner({required this.profile, required this.flight});

  final UserProfile profile;
  final CoverFlight? flight;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final top = MediaQuery.paddingOf(context).top;
    final height = kProfileBannerStrip + top;
    final image = coverImage(profile.banner);

    return SizedBox(
      // Аватар свисает с кромки ровно наполовину.
      height: height + kProfileAvatarSize / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(t.radius * 1.5),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (image == null)
                    DecoratedBox(decoration: profile.bannerDecoration())
                  else
                    Image(image: image, fit: BoxFit.cover),
                  // Кнопки и часы системной строки тонут на светлом снимке —
                  // им нужна тень независимо от того, что за картинка.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.black.withValues(alpha: 0),
                        ],
                        stops: const [0, 0.45],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: top + 10,
            child: HeroContent(
              flying: flight != null,
              child: Row(
                children: [
                  // Своим табом профиль — корень ветки, и уходить с него
                  // некуда: стрелки тогда нет вовсе, как и на любой другой
                  // вкладке. Внутри главной она на месте.
                  if (Navigator.of(context).canPop())
                    GlassIconButton(
                      icon: SolarIconsOutline.arrowLeft,
                      onTap: () => context.go('/home'),
                    ),
                  const Spacer(),
                  GlassIconButton(
                    icon: SolarIconsOutline.pen,
                    onTap: () => context.go('${profileBase(context)}/edit'),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: height - kProfileAvatarSize / 2,
            child: Center(
              child: ProfileAvatar(
                profile: profile,
                size: kProfileAvatarSize,
                flightTag: flight?.tag,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Бокс «о себе / статус» — десктопный `.acc-bio-box`, но БЕЗ рамки: блок
/// держится своей заливкой, как поля в редакторе.
class _AboutBox extends StatelessWidget {
  const _AboutBox({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final bio = profile.bio.trim();
    final status = profile.status.trim();
    // Нечего показать — бокса нет вовсе, как на десктопе. Правка живёт за
    // карандашом, лезть в неё из этого блока незачем.
    if (bio.isEmpty && status.isEmpty) return const SizedBox.shrink();

    return GlassBox(
      borderRadius: BorderRadius.circular(t.radius * 0.85),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bio.isNotEmpty)
              Text(
                bio,
                style: theme.bodyMedium?.copyWith(color: t.text2, height: 1.45),
              ),
            if (status.isNotEmpty) ...[
              if (bio.isNotEmpty) const SizedBox(height: 4),
              Text(
                '"$status"',
                style: theme.bodyMedium?.copyWith(
                  color: t.muted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
