/// «Настройки → Кастомизация → Библиотека» — сетка своих картинок.
///
/// Половина десктопного раздела «Кастомизация»: там пять карточек-контекстов,
/// галерея и пресеты живут на одном экране, здесь страница разделена надвое
/// (библиотека и пресеты) — так решил пользователь, и на телефоне иначе не
/// уместить.
///
/// Куда картинка применена, выбирается не здесь, а на её собственной странице
/// ([MediaItemScreen]): на ПК сперва выбирают карточку контекста, потом
/// картинку, а тут наоборот — сперва картинку, потом тумблеры «Фон / Обложка /
/// Слайдер». Меньше состояний и нечего забыть выбрать.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/store/cover_store.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../custom_store.dart';
import '../media_store.dart';
import 'custom_widgets.dart';

class MediaLibraryScreen extends ConsumerWidget {
  const MediaLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaLibProvider);

    return CustomizationPage(
      title: context.l.custLibrary,
      onBack: () => context.go('/settings'),
      actions: [
        WideButton(
          icon: SolarIconsOutline.link,
          label: context.l.custAddUrl,
          onTap: () => _addByUrl(context, ref),
        ),
        WideButton(
          icon: SolarIconsOutline.upload,
          label: context.l.custUpload,
          onTap: () => _upload(context, ref),
        ),
      ],
      child: items.isEmpty
          ? EmptyHint(text: context.l.custLibraryEmpty)
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                // Ландшафтная плитка: обои и есть ландшафт, а квадрат резал бы
                // их посередине ещё в списке.
                childAspectRatio: 4 / 3,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _MediaCard(item: items[i]),
            ),
    );
  }

  Future<void> _upload(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l;
    final added = await ref.read(mediaLibProvider.notifier).addFromGallery();
    if (added == 0) return; // отменили или не дали доступ — молчим
    messenger.toast(l10n.custFilesAdded(added), kind: ToastKind.success);
  }

  Future<void> _addByUrl(BuildContext context, WidgetRef ref) async {
    final url = await showBloomSheetChild<String>(
      context: context,
      child: const SheetTextField(hint: 'https://example.com/image.gif'),
    );
    if (url == null || !context.mounted) return;
    final ok = ref.read(mediaLibProvider.notifier).addUrl(url);
    showToast(
      context,
      ok ? context.l.custAdded : context.l.custBadUrl,
      kind: ok ? ToastKind.success : ToastKind.warn,
    );
  }
}

class _MediaCard extends ConsumerWidget {
  const _MediaCard({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final image = coverImage(item.src);
    final usage = ref.watch(mediaUsageProvider(item.id));
    return GestureDetector(
      onTap: () => context.go('/settings/media/${item.id}'),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(t.radius * 0.85),
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.pill),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image(
                  image: image,
                  fit: BoxFit.cover,
                  // Битая ссылка не должна ломать сетку — остаётся пустая
                  // плитка, которую видно и можно открыть, чтобы удалить.
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(
                      SolarIconsOutline.gallery,
                      size: 22,
                      color: t.muted,
                    ),
                  ),
                ),
              // Куда картинка применена — значками поверх неё. Пустой список
              // не рисуем вовсе: плитка ничем не занятой картинки чистая.
              if (usage.isNotEmpty) Center(child: _UsageBadge(usage: usage)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плашка «эта картинка стоит вот здесь»: по значку на каждый занятый
/// контекст. Стекло то же, что у бейджа площадки в строке трека, — под ней
/// картинка, и сплошная плашка темы читалась бы заплаткой.
class _UsageBadge extends StatelessWidget {
  const _UsageBadge({required this.usage});

  final List<CustomCtx> usage;

  static const Map<CustomCtx, IconData> _icons = {
    CustomCtx.bg: SolarIconsOutline.galleryWide,
    CustomCtx.cover: SolarIconsOutline.album,
    CustomCtx.slider: SolarIconsOutline.sliderMinimalisticHorizontal,
  };

  @override
  Widget build(BuildContext context) => GlassSurface(
    shape: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final ctx in usage) ...[
            if (ctx != usage.first) const SizedBox(width: 8),
            Icon(_icons[ctx], size: 15, color: Colors.white),
          ],
        ],
      ),
    ),
  );
}
