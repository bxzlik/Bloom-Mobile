/// Настройки → «Хранилище»: сколько места занимают офлайн-копии треков и
/// кнопка всё это стереть.
///
/// Порт десктопной секции `StorageSection` в той её части, которая на телефоне
/// имеет смысл: кешей текстов песен и кастомизации у нас пока нет, а вот
/// скачанные треки растут незаметно и посмотреть их объём нужно.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../offline/offline_store.dart';

class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    // Считаем по текущему индексу: он же меняется при каждом скачивании и
    // удалении, поэтому цифры на экране не отстают от жизни.
    final files = ref.watch(offlineProvider).files;
    final offline = ref.read(offlineProvider.notifier);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          SubPageHeader(
            title: 'Хранилище',
            onBack: () => context.go('/settings'),
          ),
          const SizedBox(height: 22),
          FutureBuilder<({int bytes, int count})>(
            // Ключ по составу кеша: без него FutureBuilder не пересчитает
            // размер после очистки и покажет прежние мегабайты.
            key: ValueKey(files.length),
            future: offline.stats(),
            builder: (context, snap) {
              final stats = snap.data;
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.pill,
                  borderRadius: BorderRadius.circular(t.radius),
                ),
                child: Row(
                  children: [
                    Icon(SolarIconsOutline.database, size: 22, color: t.iconFg),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Офлайн-кеш треков', style: theme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            stats == null
                                ? 'Считаю…'
                                : '${stats.count} треков · ${_size(stats.bytes)}',
                            style: theme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Скачанные треки играют без сети и не тратят трафик. '
            'Лежат внутри приложения — другим плеерам не видны и '
            'удаляются вместе с Bloom.',
            style: theme.bodySmall,
          ),
          const SizedBox(height: 20),
          _ClearButton(enabled: files.isNotEmpty),
        ],
      ),
    );
  }
}

class _ClearButton extends ConsumerWidget {
  const _ClearButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;

    return Material(
      color: t.pill,
      borderRadius: BorderRadius.circular(t.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? () => _confirm(context, ref) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(
                SolarIconsOutline.trashBinMinimalistic,
                size: 20,
                color: enabled ? t.sysFavIco : t.muted,
              ),
              const SizedBox(width: 14),
              Text(
                'Очистить офлайн-кеш',
                style: theme.titleSmall?.copyWith(
                  color: enabled ? t.sysFavIco : t.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Спрашиваем, как `confirm()` на десктопе: сами треки останутся в
  /// библиотеке, но заиграют только с сетью — это стоит сказать заранее.
  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.blockColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radius),
          side: BorderSide(color: t.ovlLine),
        ),
        title: Text('Очистить офлайн-кеш?', style: theme.titleLarge),
        content: Text(
          'Скачанные копии будут удалены, и эти треки перестанут играть без '
          'сети. Из библиотеки и плейлистов они никуда не денутся.',
          style: theme.bodyMedium?.copyWith(color: t.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Отмена', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Очистить', style: TextStyle(color: t.sysFavIco)),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final deleted = await ref.read(offlineProvider.notifier).clearAll();
    messenger.showSnackBar(
      SnackBar(content: Text('Офлайн-кеш очищен, удалено файлов: $deleted')),
    );
  }
}

/// Размер по-человечески: килобайты для мелочи, дальше мегабайты и гигабайты.
String _size(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} КБ';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} МБ';
  return '${(mb / 1024).toStringAsFixed(2)} ГБ';
}
