/// Настройки внешнего вида и площадок.
///
/// Как на десктопе: тема — это ТРИ цвета пресета, а радиус и акцент живут
/// отдельно и при смене темы не сбрасываются (`themeStore.ts`: «радиус и шрифт
/// в тему не входят намеренно»).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/tokens.dart';
import '../../providers/soundcloud/soundcloud.dart' as sc;
import 'library_store.dart' show jsonStoreProvider;

/// Встроенные пресеты в порядке показа — те же три цвета, что в
/// `THEME_PRESETS` на десктопе.
class ThemePreset {
  final String id;
  final String name;
  final Color bg;
  final Color blockColor;
  final Color accent;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
  });

  BloomTokens tokens({Color? accentOverride, double radius = 14}) =>
      BloomTokens.from(
        bg: bg,
        blockColor: blockColor,
        accent: accentOverride ?? accent,
        radius: radius,
      );
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(
    id: 'dark',
    name: 'Dark',
    bg: Color(0xFF0A0A0A),
    blockColor: Color(0xFF0A0A0A),
    accent: Color(0xFFFFFFFF),
  ),
  ThemePreset(
    id: 'amoled',
    name: 'AMOLED',
    bg: Color(0xFF000000),
    blockColor: Color(0xFF000000),
    accent: Color(0xFFFFFFFF),
  ),
  ThemePreset(
    id: 'midnight',
    name: 'Midnight',
    bg: Color(0xFF101828),
    blockColor: Color(0xFF101828),
    accent: Color(0xFF4D9FFF),
  ),
  ThemePreset(
    id: 'nord',
    name: 'Nord',
    bg: Color(0xFF3B4252),
    blockColor: Color(0xFF3B4252),
    accent: Color(0xFF88C0D0),
  ),
  ThemePreset(
    id: 'warm',
    name: 'Warm',
    bg: Color(0xFF1C1610),
    blockColor: Color(0xFF1C1610),
    accent: Color(0xFFD4875A),
  ),
  ThemePreset(
    id: 'light',
    name: 'Light',
    bg: Color(0xFFE8E8E8),
    blockColor: Color(0xFFE8E8E8),
    accent: Color(0xFF333333),
  ),
];

/// Набор акцентов для быстрого выбора. Первый — «как в теме».
const List<Color> kAccentSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF4D9FFF),
  Color(0xFF88C0D0),
  Color(0xFFD4875A),
  Color(0xFFFF5578),
  Color(0xFFFFB400),
  Color(0xFF7C5CFF),
  Color(0xFF4FD87A),
];

class SettingsState {
  final String themeId;

  /// Переопределение акцента; null — берётся из пресета.
  final Color? accent;
  final double radius;

  /// Ручной client_id SoundCloud (пусто — авто-подбор).
  final String? scClientId;

  /// Бейджи источника в цвете акцента. По умолчанию выключено — бейджи в
  /// фирменных цветах площадок (то же поведение и дефолт, что на десктопе).
  final bool accentBadges;

  const SettingsState({
    this.themeId = 'dark',
    this.accent,
    this.radius = 14,
    this.scClientId,
    this.accentBadges = false,
  });

  ThemePreset get preset => kThemePresets.firstWhere(
    (p) => p.id == themeId,
    orElse: () => kThemePresets.first,
  );

  BloomTokens get tokens =>
      preset.tokens(accentOverride: accent, radius: radius);

  SettingsState copyWith({
    String? themeId,
    Color? accent,
    bool clearAccent = false,
    double? radius,
    String? scClientId,
    bool clearClientId = false,
    bool? accentBadges,
  }) => SettingsState(
    themeId: themeId ?? this.themeId,
    accent: clearAccent ? null : (accent ?? this.accent),
    radius: radius ?? this.radius,
    scClientId: clearClientId ? null : (scClientId ?? this.scClientId),
    accentBadges: accentBadges ?? this.accentBadges,
  );
}

final settingsProvider = NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final raw = ref.read(jsonStoreProvider).readMap('settings');
    final accent = raw['accent'];
    final clientId = raw['scClientId'];
    final state = SettingsState(
      themeId: raw['themeId'] as String? ?? 'dark',
      accent: accent is num ? Color(accent.toInt()) : null,
      radius: (raw['radius'] as num?)?.toDouble() ?? 14,
      scClientId: clientId is String && clientId.isNotEmpty ? clientId : null,
      accentBadges: raw['accentBadges'] as bool? ?? false,
    );
    // Провайдер SoundCloud держит client_id в модульном состоянии — при старте
    // ему надо отдать сохранённый, иначе ручной ключ забудется до перезапуска.
    sc.setManualClientId(state.scClientId);
    return state;
  }

  void _save() {
    ref.read(jsonStoreProvider).write('settings', {
      'themeId': state.themeId,
      if (state.accent != null) 'accent': state.accent!.toARGB32(),
      'radius': state.radius,
      if (state.scClientId != null) 'scClientId': state.scClientId,
      'accentBadges': state.accentBadges,
    });
  }

  /// Смена темы НЕ трогает акцент и радиус — это независимые настройки вида.
  void setTheme(String id) {
    state = state.copyWith(themeId: id);
    _save();
  }

  void setAccent(Color? accent) {
    state = accent == null
        ? state.copyWith(clearAccent: true)
        : state.copyWith(accent: accent);
    _save();
  }

  void setRadius(double radius) {
    state = state.copyWith(radius: radius);
    _save();
  }

  void setAccentBadges(bool value) {
    state = state.copyWith(accentBadges: value);
    _save();
  }

  void setScClientId(String? id) {
    final v = id?.trim();
    final norm = (v == null || v.isEmpty) ? null : v;
    state = norm == null
        ? state.copyWith(clearClientId: true)
        : state.copyWith(scClientId: norm);
    sc.setManualClientId(norm);
    _save();
  }
}
