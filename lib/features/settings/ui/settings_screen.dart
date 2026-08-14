/// Настройки.
///
/// Состав разделов — ПОРТ десктопного `SettingsNav.tsx` (`GROUPS`), названия
/// групп и пунктов взяты из `dict.ts` дословно. Из макета сюда пришла только
/// раскладка: капсовые заголовки групп и тёмные контейнеры со строками
/// «иконка — текст — шеврон».
///
/// Не перенесены разделы, которых на телефоне физически не бывает: «Оверлей»
/// (окно поверх других окон), «Горячие клавиши» (глобальные, на уровне ОС),
/// «Discord RPC», «Эффективность», «Страницы» и «Вкладки». Вместо них в
/// «Основное» добавлены «Свайпы» — жесты есть только на телефоне. Иконки — те
/// же Solar, что на десктопе; исключение «Система»: там монитор, здесь
/// смартфон.
///
/// Работают «Свайпы», «Интерфейс», «Хранилище», «SoundCloud» и «Яндекс.Музыка».
/// Остальные честно говорят, что ещё не сделаны.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/entities/entities.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/platform_logo.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListView(
        // Заголовка экрана нет: вкладка и так подписана иконкой в таб-баре,
        // а первая группа начинается со своего капсового заголовка. Снизу к
        // полю добавлены бары каркаса — они плавают над списком.
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + bottomBarsInset(context)),
        children: [
          SettingsGroup(
            title: context.l.setGroupMain,
            rows: [
              SettingsRow(
                icon: SolarIconsOutline.smartphone,
                title: context.l.setSystem,
              ),
              SettingsRow(
                icon: SolarIconsOutline.tuning,
                title: context.l.setAudio,
              ),
              SettingsRow(
                icon: SolarIconsOutline.database,
                title: context.l.setStorage,
                onTap: () => context.go('/settings/storage'),
              ),
              SettingsRow(
                icon: SolarIconsOutline.transferHorizontal,
                title: context.l.setSwipes,
                onTap: () => context.go('/settings/swipes'),
              ),
            ],
          ),
          SettingsGroup(
            title: context.l.setGroupAppearance,
            rows: [
              SettingsRow(
                icon: SolarIconsOutline.musicNote,
                title: context.l.setPlayer,
              ),
              SettingsRow(
                icon: SolarIconsOutline.sidebar,
                title: context.l.setInterface,
                onTap: () => context.go('/settings/appearance'),
              ),
              SettingsRow(
                icon: SolarIconsOutline.album,
                title: context.l.setCustomization,
              ),
            ],
          ),
          SettingsGroup(
            title: context.l.setGroupIntegrations,
            rows: [
              SettingsRow(
                title: 'SoundCloud',
                leading: const PlatformLogo(MusicSource.soundcloud, size: 20),
                onTap: () => context.go('/settings/soundcloud'),
              ),
              SettingsRow(
                title: context.l.sourceYandex,
                leading: const PlatformLogo(MusicSource.yandex, size: 20),
                onTap: () => context.go('/settings/yandex'),
              ),
              SettingsRow(
                title: 'YouTube Music',
                leading: const PlatformLogo(MusicSource.ytmusic, size: 20),
                onTap: () => context.go('/settings/ytmusic'),
              ),
              SettingsRow(
                title: 'Last.fm',
                leading: const ServiceLogo(Service.lastfm, size: 20),
              ),
              SettingsRow(
                title: 'Genius',
                leading: const ServiceLogo(Service.genius, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<SettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
          // Ярче общего `labelSmall`: в списке без описаний капсовый заголовок
          // остался единственным ориентиром, приглушённый `muted` его терял.
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: t.text2),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.pill,
            borderRadius: BorderRadius.circular(t.radius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Padding(
                    // 14 паддинга + 24 иконки + 14 зазора: линия начинается
                    // ровно под текстом строки.
                    padding: const EdgeInsets.only(left: 52),
                    // Половина от обычной рамки: строки уже сгруппированы
                    // контейнером, разделителю достаточно едва намекать.
                    child: Divider(
                      height: 1,
                      color: t.ovlLine.withValues(alpha: t.ovlLine.a * 0.5),
                    ),
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.leading,
    required this.title,
    this.onTap,
  });

  final IconData? icon;
  final Widget? leading;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final ready = onTap != null;
    return InkWell(
      onTap: onTap ?? () => _showStub(context, title),
      child: Padding(
        // 20 по вертикали + 20 строки текста = 60 на строку.
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child:
                  leading ??
                  Icon(icon, size: 20, color: ready ? t.iconFg : t.muted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: ready
                    ? theme.titleMedium
                    : theme.titleMedium?.copyWith(color: t.text2),
              ),
            ),
            Icon(SolarIconsOutline.altArrowRight, size: 16, color: t.text2),
          ],
        ),
      ),
    );
  }
}

void _showStub(BuildContext context, String title) =>
    showToast(context, context.l.setStub(title), kind: ToastKind.warn);
