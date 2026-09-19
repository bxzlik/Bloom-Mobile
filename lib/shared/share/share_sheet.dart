/// Шторка «Поделиться» — порт десктопной `ShareCardModal`.
///
/// На ПК это модалка: превью карточки и две кнопки — «Сохранить PNG» и
/// «Копировать ссылку». Здесь та же пара, но первая кнопка отдаёт картинку
/// СИСТЕМНОЙ шторке (`ACTION_SEND` / `UIActivityViewController`): оттуда
/// карточка уходит в чат или в сторис одним касанием, а «Сохранить в галерею»
/// лежит в той же шторке. Сохранять файл ради того, чтобы человек потом нёс его
/// руками, на телефоне незачем — тот же выбор, что у постера «Итогов».
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:solar_icons/solar_icons.dart';

import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/store/cover_store.dart';
import '../../features/settings/cover_accent.dart';
import '../ui/bloom_sheet.dart';
import '../ui/bloom_toast.dart';
import 'share_card.dart';
import 'share_image.dart';
import 'share_link.dart';

/// Открыть шторку «Поделиться» для трека, артиста, альбома или плейлиста.
Future<void> showShareSheet(BuildContext context, ShareTarget target) =>
    showBloomSheetChild<void>(
      context: context,
      backdrop: target.cover,
      child: _ShareBody(target: target),
    );

/// Заголовок шторки по типу сущности — порт `labels` из десктопной модалки.
String shareTitle(AppLocalizations l, ShareKind kind) => switch (kind) {
  ShareKind.artist => l.shareArtist,
  ShareKind.album => l.shareAlbum,
  ShareKind.playlist => l.sharePlaylist,
  ShareKind.track => l.shareTrack,
};

/// Обложка покрупнее для карточки: в списках у нас едет `t300x300`, а на
/// карточке она занимает всю ширину и заметно мылит. Порт `loadCoverBlob` с ПК —
/// там та же подмена и тот же откат на исходный размер, если крупной нет.
String _hiRes(String url) => url
    .replaceAll('-large.', '-t500x500.')
    .replaceAll('-small.', '-t500x500.')
    .replaceAll('-t300x300.', '-t500x500.');

class _ShareBody extends StatefulWidget {
  const _ShareBody({required this.target});

  final ShareTarget target;

  @override
  State<_ShareBody> createState() => _ShareBodyState();
}

class _ShareBodyState extends State<_ShareBody> {
  final GlobalKey _shot = GlobalKey();

  ImageProvider? _cover;
  ImageProvider? _logo;

  /// Тон фона карточки: считается по той обложке, что в неё попала. Пока её
  /// нет — нейтральный, иначе карточка моргнула бы цветом.
  Color _tone = kShareToneFallback;

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
    // Потолок превью: карточка выше, чем шире, и во всю ширину экрана она
    // вытеснила бы кнопки за нижний край шторки.
    final maxPreview = MediaQuery.of(context).size.height * 0.5;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            shareTitle(l, widget.target.kind),
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
                child: ShareCard(
                  title: widget.target.title,
                  artist: widget.target.artist,
                  cover: _cover,
                  logo: _logo,
                  tone: _tone,
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

  /// Догружаем знак и обложку ДО снимка: в него попадает ровно то, что
  /// отрисовано, и недогруженная картинка стала бы дыркой в карточке.
  Future<void> _resolve() async {
    await _load(const AssetImage('assets/brand/bloom_mark.png'), asLogo: true);
    final raw = widget.target.cover;
    if (raw != null && raw.isNotEmpty) {
      for (final image in _candidates(raw)) {
        if (await _load(image)) {
          await _applyTone(image);
          break;
        }
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  /// Тон фона по обложке. Промах не беда: останется нейтральный.
  Future<void> _applyTone(ImageProvider image) async {
    final hsl = await extractProviderHsl(image);
    if (hsl == null || !mounted) return;
    setState(() => _tone = shareToneFromHsl(hsl));
  }

  /// Что пробуем как обложку: сперва крупный размер, потом исходный. Своя
  /// обложка с диска — одна попытка, подменять в ней нечего.
  List<ImageProvider> _candidates(String raw) {
    if (!raw.startsWith('http')) {
      final local = coverImage(raw);
      return local == null ? const [] : [local];
    }
    final hi = _hiRes(raw);
    return [if (hi != raw) NetworkImage(hi), NetworkImage(raw)];
  }

  /// `true` — картинка в кеше и её можно рисовать. Промах не роняет шторку:
  /// карточка переживёт и пустую обложку, и отсутствующий знак.
  Future<bool> _load(ImageProvider image, {bool asLogo = false}) async {
    if (!mounted) return false;
    var ok = true;
    await precacheImage(image, context, onError: (_, _) => ok = false);
    if (!ok || !mounted) return false;
    setState(() {
      if (asLogo) {
        _logo = image;
      } else {
        _cover = image;
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
    Clipboard.setData(ClipboardData(text: widget.target.url));
    Navigator.of(context).pop();
    messenger.toast(l10n.commonLinkCopied, kind: ToastKind.success);
  }

  /// Имя файла видно человеку в системной шторке и в галерее, поэтому в нём
  /// название сущности — но только то, что годится в имя файла на любой ФС.
  String _filename() {
    final slug = widget.target.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final short = slug.length > 40 ? slug.substring(0, 40) : slug;
    return short.isEmpty ? 'bloom-share.png' : 'bloom-$short.png';
  }
}

/// Кнопка под карточкой — порт `.sc-card-btn`: обе одной ширины в ряд, у
/// главной заливка чуть плотнее.
///
/// Публичная: тем же рядом кнопок живёт шторка «Поделиться профилем».
class ShareActionButton extends StatelessWidget {
  const ShareActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  /// Идёт работа либо карточка ещё не готова: нажатие не проходит, на месте
  /// значка кружок.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final panel = sheetPanelColor(context);
    final color = busy ? t.muted : t.text;

    return Material(
      color: primary
          ? Color.alphaBlend(Colors.white.withValues(alpha: 0.10), panel)
          : panel,
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 17, color: color),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(fontSize: 14, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
