/// Шторка «Поделиться профилем» — порт десктопной `ProfileShareModal`.
///
/// Устроена как общая шторка «Поделиться» (`shared/share/share_sheet.dart`):
/// превью карточки и две кнопки. Первая отдаёт PNG СИСТЕМНОЙ шторке, а не
/// сохраняет файл (`cover_download` с ПК): оттуда карточка уходит в чат или в
/// сторис одним касанием. Вторая кладёт в буфер ссылку `?type=profile`.
///
/// Статистика берётся из `profileStatsProvider` — то же, что показывает шторка
/// «Статистика», и то же, что десктоп считает по истории.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/share/share_card.dart' show kShareCardCapture;
import '../../../shared/share/share_image.dart';
import '../../../shared/share/share_link.dart';
import '../../../shared/share/share_sheet.dart' show ShareActionButton;
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../profile_store.dart';
import '../stats.dart';
import 'profile_share_card.dart';

/// Открыть шторку «Поделиться профилем».
///
/// Картинки фоном у неё НЕТ (его слово): обложка профиля, размытая под шторкой,
/// спорит с самой карточкой — та и так занимает всю шторку и рисует профиль
/// целиком. Шторка обычная, как у скорости и очереди.
Future<void> showProfileShareSheet(BuildContext context) {
  return showBloomSheetChild<void>(
    context: context,
    child: const _ProfileShareBody(),
  );
}

class _ProfileShareBody extends ConsumerStatefulWidget {
  const _ProfileShareBody();

  @override
  ConsumerState<_ProfileShareBody> createState() => _ProfileShareBodyState();
}

class _ProfileShareBodyState extends ConsumerState<_ProfileShareBody> {
  final GlobalKey _shot = GlobalKey();

  ImageProvider? _avatar;
  ImageProvider? _logo;

  /// Картинки долетели (или их нет вовсе) — снимок можно снимать.
  bool _ready = false;

  /// Идёт отправка: системная шторка ещё не поднялась.
  bool _busy = false;

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Не `initState`: `precacheImage` спрашивает `MediaQuery` (плотность
    // экрана), а до конца `initState` зависимости трогать нельзя.
    if (_started) return;
    _started = true;
    _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context).textTheme;
    final profile = ref.watch(profileProvider);
    // Потолок превью: карточка ниже трековой, но во всю ширину экрана она всё
    // равно вытеснила бы кнопки за нижний край шторки.
    final maxPreview = MediaQuery.of(context).size.height * 0.5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l.shareProfile,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.titleLarge?.copyWith(fontSize: 17),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPreview),
            child: FittedBox(
              fit: BoxFit.contain,
              // Снимок берётся с этой границы, а она лежит ВНУТРИ `FittedBox`:
              // раскладка ей достаётся в дизайн-боксе 380, сколько бы места ни
              // было на экране, — значит и PNG всегда одного размера.
              child: RepaintBoundary(
                key: _shot,
                child: ProfileShareCard(
                  profile: profile,
                  stats: _stats(context),
                  avatar: _avatar,
                  logo: _logo,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ShareActionButton(
                  icon: SolarIconsOutline.share,
                  label: l.shareAction,
                  primary: true,
                  busy: !_ready || _busy,
                  onTap: _send,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ShareActionButton(
                  icon: SolarIconsOutline.link,
                  label: l.commonCopyLink,
                  onTap: _copy,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Числа карточки. Время — та же строка, что в шторке «Статистика».
  ProfileCardStats _stats(BuildContext context) {
    final s = ref.watch(profileStatsProvider);
    return ProfileCardStats(
      tracks: s.libraryTracks,
      plays: s.totalPlays,
      time: fmtDurLong(context, s.listenSec),
      favArtist: s.favArtist,
    );
  }

  /// Догружаем знак и аватар ДО снимка: в него попадает ровно то, что
  /// отрисовано, и недогруженная картинка стала бы дыркой в карточке.
  Future<void> _resolve() async {
    await _load(const AssetImage('assets/brand/bloom_mark.png'), asLogo: true);
    final avatar = coverImage(ref.read(profileProvider).avatar);
    if (avatar != null) await _load(avatar);
    if (mounted) setState(() => _ready = true);
  }

  /// Промах не роняет шторку: карточка переживёт и пустой аватар (на его месте
  /// градиент с буквой), и отсутствующий знак.
  Future<bool> _load(ImageProvider image, {bool asLogo = false}) async {
    if (!mounted) return false;
    var ok = true;
    await precacheImage(image, context, onError: (_, _) => ok = false);
    if (!ok || !mounted) return false;
    setState(() {
      if (asLogo) {
        _logo = image;
      } else {
        _avatar = image;
      }
    });
    return true;
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l;
    setState(() => _busy = true);
    var ok = false;
    try {
      final png = await captureShareCard(_shot, pixelRatio: kShareCardCapture);
      if (png != null) {
        ok = await shareImageBytes(png, filename: _filename());
      }
    } catch (_) {
      // Снимок не удался — ниже покажем тост, ронять шторку незачем.
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    if (!ok) messenger.toast(l10n.shareFail, kind: ToastKind.error);
  }

  void _copy() {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l;
    final profile = ref.read(profileProvider);
    final stats = _stats(context);
    Clipboard.setData(
      ClipboardData(
        text: buildProfileShareUrl(
          name: profile.displayName(l10n),
          tracks: stats.tracks,
          plays: stats.plays,
          time: stats.time,
          favArtist: stats.favArtist,
          bio: profile.bio.trim(),
          avatar: profile.avatar,
        ),
      ),
    );
    Navigator.of(context).pop();
    messenger.toast(l10n.commonLinkCopied, kind: ToastKind.success);
  }

  /// Имя файла видно человеку в системной шторке и в галерее — десктопное
  /// «<ник> — Bloom», но только теми знаками, что годятся в имя файла.
  String _filename() {
    final slug = ref
        .read(profileProvider)
        .displayName(context.l)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40) : slug;
    return short.isEmpty ? 'bloom-profile.png' : 'bloom-$short.png';
  }
}
