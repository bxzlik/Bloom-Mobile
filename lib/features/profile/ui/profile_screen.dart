/// Страница профиля — порт десктопной `ProfileCard` из `AccountPage`.
///
/// Раскладка мобильная (из присланного макета): обложка полосой сверху, аватар
/// по центру на её нижней кромке, под ним ник, строка «Слушает сейчас» и
/// широкий бокс «о себе / статус». На десктопе те же части стоят в ряд слева —
/// состав их не меняется, меняется только расстановка.
///
/// Вкладки «Статистика» и «Достижения» с десктопа сюда ещё не приехали: им
/// нужны счётчики (прослушивания по трекам, дневной журнал, время в
/// приложении), которых на телефоне пока нет.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/cover_hero.dart';
import '../../player/player_controller.dart';
import '../profile_store.dart';
import 'achievements_section.dart';
import 'profile_avatar.dart';
import 'stats_section.dart';

/// Сторона аватара на странице — десктопные 120 из `.acc-ava`.
const double kProfileAvatarSize = 120;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.flight});

  /// Метка перелёта аватара с кнопки в шапке главной.
  final CoverFlight? flight;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// Метку держим у себя: `extra` живёт на ВСЮ ссылку, и стоит уйти отсюда в
  /// редактор, как страница профиля перестраивается уже без неё — аватару
  /// стало бы некуда лететь на обратном пути.
  late CoverFlight? _flight = widget.flight;

  /// 0 — «Статистика», 1 — «Достижения».
  int _tab = 0;

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
      padding: EdgeInsets.zero,
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
                  onTap: () => _copyNick(context, profile.name),
                  child: Text(
                    profile.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.headlineSmall?.copyWith(fontSize: 26),
                  ),
                ),
                const SizedBox(height: 6),
                const _NowPlaying(),
                const SizedBox(height: 12),
                _AboutBox(profile: profile),
                const SizedBox(height: 16),
                // Две вкладки под карточкой — как сегментированный ряд на
                // десктопе. Выбор живёт в состоянии страницы: на ПК он
                // персистится, чтобы бар статистики с главной открывал профиль
                // сразу на нужной, а главной у нас ещё нет.
                _Tabs(
                  index: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 14),
                if (_tab == 0)
                  const StatsSection()
                else
                  const AchievementsSection(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _copyNick(BuildContext context, String name) {
    Clipboard.setData(ClipboardData(text: name));
    showToast(context, 'Ник скопирован!', kind: ToastKind.success);
  }
}

/// Сегментированные вкладки «Статистика» / «Достижения».
class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  static const _items = [
    (icon: SolarIconsOutline.chart, label: 'Статистика'),
    (icon: SolarIconsOutline.medalStar, label: 'Достижения'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: i == index ? t.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _items[i].icon,
                        size: 15,
                        color: i == index ? t.accentText : t.text2,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _items[i].label,
                        style: theme.titleSmall?.copyWith(
                          color: i == index ? t.accentText : t.text2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Обложка полосой: своя картинка либо цвет/градиент, поверх — кнопки, на
/// нижней кромке — аватар.
class _Banner extends StatelessWidget {
  const _Banner({required this.profile, required this.flight});

  final UserProfile profile;
  final CoverFlight? flight;

  /// Высота самой полосы, без учёта системной строки.
  static const double _strip = 168;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final top = MediaQuery.paddingOf(context).top;
    final height = _strip + top;
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
                  GlassIconButton(
                    icon: SolarIconsOutline.arrowLeft,
                    onTap: () => context.go('/home'),
                  ),
                  const Spacer(),
                  GlassIconButton(
                    icon: SolarIconsOutline.pen,
                    onTap: () => context.go('/home/profile/edit'),
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

/// «Слушает сейчас: трек — артист» с полосками эквалайзера, как `.acc-since`.
class _NowPlaying extends ConsumerWidget {
  const _NowPlaying();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final track = ref.watch(playbackProvider).track;
    final player = ref.watch(audioPlayerProvider);
    if (track == null) return const SizedBox.shrink();

    return StreamBuilder<bool>(
      stream: player.playingStream,
      initialData: player.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        if (!playing) return const SizedBox.shrink();
        final artist = track.artist.isEmpty ? '' : ' — ${track.artist}';
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EqualizerBars(playing: true, scale: 0.85),
            const SizedBox(width: 7),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Слушает сейчас: ',
                      style: TextStyle(
                        color: t.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: '${track.name}$artist'),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: t.text2),
              ),
            ),
          ],
        );
      },
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: t.pill,
        borderRadius: BorderRadius.circular(t.radius * 0.85),
      ),
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
    );
  }
}
