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

  /// Своя тема — её можно удалить, встроенную нельзя.
  final bool custom;

  const ThemePreset({
    required this.id,
    required this.name,
    required this.bg,
    required this.blockColor,
    required this.accent,
    this.custom = false,
  });

  BloomTokens tokens({Color? accentOverride, double radius = 14}) =>
      BloomTokens.from(
        bg: bg,
        blockColor: blockColor,
        accent: accentOverride ?? accent,
        radius: radius,
      );

  /// Своя тема в хранилище — те же три цвета, что на десктопе: вторичные всё
  /// равно считаются формулами (`DERIVED_SECONDARY`), хранить их незачем.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bg': bg.toARGB32(),
    'blockColor': blockColor.toARGB32(),
    'accent': accent.toARGB32(),
  };

  /// Тема из хранилища; `null` — запись битая (руками правили файл).
  static ThemePreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    final bg = raw['bg'];
    final blockColor = raw['blockColor'];
    final accent = raw['accent'];
    if (id is! String || name is! String) return null;
    if (bg is! num || blockColor is! num || accent is! num) return null;
    return ThemePreset(
      id: id,
      name: name,
      bg: Color(bg.toInt()),
      blockColor: Color(blockColor.toInt()),
      accent: Color(accent.toInt()),
      custom: true,
    );
  }
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

/// Границы и дефолт яркости авто-акцента — те же числа, что в десктопном
/// `coverAccent.ts`: центр коридора светлоты, вокруг которого зажимается цвет
/// обложки.
const double kAutoAccentLMin = 0.1;
const double kAutoAccentLMax = 0.6;
const double kAutoAccentLDefault = 0.375;

double clampAutoAccentL(double v) => v.clamp(kAutoAccentLMin, kAutoAccentLMax);

/// Вид таб-бара каркаса. Настройка чисто телефонная: на десктопе навигация
/// живёт в сайдбаре, и порта у неё нет.
///
/// Отличаются только рамка и поля вокруг ряда иконок — сам ряд, его высота и
/// оживление глифов у всех стилей общие.
enum NavBarStyle {
  /// Во всю ширину, прижат к низу, тонкая линия сверху — как было всегда.
  bar,

  /// То же место, но панель отбита сверху скруглением: под её углами видно
  /// список.
  rounded,

  /// Карточка с полями по краям, приподнятая над низом, — пара к миниплееру.
  floating,

  /// Та же плавающая панель, но с углами в половину высоты — капсула.
  pill,
}

/// Стиль из сырых настроек. Неизвестное имя (настройки от новой сборки) — это
/// не повод падать: возвращаем обычный бар.
NavBarStyle readNavStyle(Object? raw) {
  for (final style in NavBarStyle.values) {
    if (style.name == raw) return style;
  }
  return NavBarStyle.bar;
}

/// Что Bloom делает с файлом, добавленным плюсом во «Всех треках» — порт
/// десктопного `local_import_mode` (там он про папки, у нас — про одиночные
/// файлы, папок на телефоне мы не смотрим).
enum LocalImportMode {
  /// Файл остаётся там, где лежит; Bloom помнит выданное системой разрешение
  /// на чтение. Дефолт, как и на ПК.
  inPlace,

  /// Файл копируется внутрь приложения — тогда трек переживает переезд и
  /// удаление оригинала, но занимает место второй раз.
  copy,
}

/// Режим из сырых настроек. Неизвестное имя — не повод падать: дефолт.
LocalImportMode readLocalImportMode(Object? raw) {
  for (final mode in LocalImportMode.values) {
    if (mode.name == raw) return mode;
  }
  return LocalImportMode.inPlace;
}

/// Языки интерфейса — те же два, что в десктопном `LOCALES` (`i18nStore.ts`).
///
/// Порядок показа: английский первым, как на ПК.
const List<Locale> kLocales = [Locale('en'), Locale('ru')];

/// Сохранённый язык из сырой карты настроек; `null` — «как в системе».
///
/// Отдельной функцией, потому что нужна и до создания контейнера: `main()`
/// собирает название канала уведомлений раньше первого кадра.
Locale? readSavedLocale(Map<String, dynamic> raw) {
  final code = raw['locale'];
  if (code is! String) return null;
  for (final locale in kLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

class SettingsState {
  final String themeId;

  /// Язык интерфейса; `null` — «как в системе».
  ///
  /// Именно null, а не подставленный при первом запуске код: тогда телефон,
  /// переключённый на другой язык, переключает и приложение, пока пользователь
  /// не выбрал язык руками. Дальше выбор уже не сбивается.
  final Locale? locale;

  /// Переопределение акцента; null — берётся из пресета.
  ///
  /// Ручного выбора акцента на телефоне нет (как и на ПК — там только пикеры
  /// внутри своей темы), так что заполняет его сейчас ровно одно — авто-акцент
  /// из обложки.
  final Color? accent;

  /// Акцент из обложки играющего трека (десктопный `autoAccent`).
  final bool autoAccent;

  /// Яркость авто-акцента: центр коридора светлоты, см. [clampAutoAccentL].
  final double autoAccentL;

  final double radius;

  /// Ручной client_id SoundCloud (пусто — авто-подбор).
  final String? scClientId;

  /// Бейджи источника в цвете акцента. По умолчанию выключено — бейджи в
  /// фирменных цветах площадок (то же поведение и дефолт, что на десктопе).
  final bool accentBadges;

  /// Вид таб-бара, см. [NavBarStyle].
  final NavBarStyle navStyle;

  /// Обложка играющего трека как фон приложения — десктопная
  /// `settings.background.coverAsBg`. Своя картинка фона (её ставят в
  /// «Кастомизации») эту настройку перебивает, как и на ПК.
  final bool coverAsBg;

  /// Что делать с добавленным своим файлом, см. [LocalImportMode].
  final LocalImportMode localImport;

  /// Свои темы — в порядке создания, после встроенных.
  final List<ThemePreset> customThemes;

  const SettingsState({
    this.themeId = 'dark',
    this.locale,
    this.accent,
    this.autoAccent = false,
    this.autoAccentL = kAutoAccentLDefault,
    this.radius = 14,
    this.scClientId,
    this.accentBadges = false,
    this.navStyle = NavBarStyle.bar,
    this.coverAsBg = false,
    this.localImport = LocalImportMode.inPlace,
    this.customThemes = const [],
  });

  /// Встроенные и свои разом — в этом порядке они и показываются.
  List<ThemePreset> get allThemes => [...kThemePresets, ...customThemes];

  ThemePreset get preset => allThemes.firstWhere(
    (p) => p.id == themeId,
    orElse: () => kThemePresets.first,
  );

  BloomTokens get tokens =>
      preset.tokens(accentOverride: accent, radius: radius);

  SettingsState copyWith({
    String? themeId,
    Locale? locale,
    bool clearLocale = false,
    Color? accent,
    bool clearAccent = false,
    bool? autoAccent,
    double? autoAccentL,
    double? radius,
    String? scClientId,
    bool clearClientId = false,
    bool? accentBadges,
    NavBarStyle? navStyle,
    bool? coverAsBg,
    LocalImportMode? localImport,
    List<ThemePreset>? customThemes,
  }) => SettingsState(
    themeId: themeId ?? this.themeId,
    locale: clearLocale ? null : (locale ?? this.locale),
    accent: clearAccent ? null : (accent ?? this.accent),
    autoAccent: autoAccent ?? this.autoAccent,
    autoAccentL: autoAccentL ?? this.autoAccentL,
    radius: radius ?? this.radius,
    scClientId: clearClientId ? null : (scClientId ?? this.scClientId),
    accentBadges: accentBadges ?? this.accentBadges,
    navStyle: navStyle ?? this.navStyle,
    coverAsBg: coverAsBg ?? this.coverAsBg,
    localImport: localImport ?? this.localImport,
    customThemes: customThemes ?? this.customThemes,
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
      locale: readSavedLocale(raw),
      accent: accent is num ? Color(accent.toInt()) : null,
      autoAccent: raw['autoAccent'] as bool? ?? false,
      autoAccentL: clampAutoAccentL(
        (raw['autoAccentL'] as num?)?.toDouble() ?? kAutoAccentLDefault,
      ),
      radius: (raw['radius'] as num?)?.toDouble() ?? 14,
      scClientId: clientId is String && clientId.isNotEmpty ? clientId : null,
      accentBadges: raw['accentBadges'] as bool? ?? false,
      navStyle: readNavStyle(raw['navStyle']),
      coverAsBg: raw['coverAsBg'] as bool? ?? false,
      localImport: readLocalImportMode(raw['localImport']),
      customThemes: [
        for (final item in (raw['customThemes'] as List?) ?? const [])
          ?ThemePreset.fromJson(item),
      ],
    );
    // Провайдер SoundCloud держит client_id в модульном состоянии — при старте
    // ему надо отдать сохранённый, иначе ручной ключ забудется до перезапуска.
    sc.setManualClientId(state.scClientId);
    return state;
  }

  void _save() {
    ref.read(jsonStoreProvider).write('settings', {
      'themeId': state.themeId,
      if (state.locale != null) 'locale': state.locale!.languageCode,
      if (state.accent != null) 'accent': state.accent!.toARGB32(),
      'autoAccent': state.autoAccent,
      'autoAccentL': state.autoAccentL,
      'radius': state.radius,
      if (state.scClientId != null) 'scClientId': state.scClientId,
      'accentBadges': state.accentBadges,
      'navStyle': state.navStyle.name,
      'coverAsBg': state.coverAsBg,
      'localImport': state.localImport.name,
      'customThemes': [for (final t in state.customThemes) t.toJson()],
    });
  }

  /// Смена темы НЕ трогает акцент и радиус — это независимые настройки вида.
  void setTheme(String id) {
    state = state.copyWith(themeId: id);
    _save();
  }

  /// Создать свою тему из трёх цветов и сразу её применить — как
  /// `createCustomTheme` на десктопе. Возвращает готовый пресет: вызывающему
  /// нужно его имя для тоста.
  ThemePreset createCustomTheme({
    required String name,
    required Color bg,
    required Color blockColor,
    required Color accent,
  }) {
    final preset = ThemePreset(
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      bg: bg,
      blockColor: blockColor,
      accent: accent,
      custom: true,
    );
    state = state.copyWith(
      customThemes: [...state.customThemes, preset],
      themeId: preset.id,
    );
    _save();
    return preset;
  }

  /// Удалить свою тему. Если она была активной — возвращаемся на первую
  /// встроенную, как на ПК: иначе приложение осталось бы с темой, которой нет.
  void deleteCustomTheme(String id) {
    final rest = [
      for (final t in state.customThemes)
        if (t.id != id) t,
    ];
    state = state.copyWith(
      customThemes: rest,
      themeId: state.themeId == id ? kThemePresets.first.id : null,
    );
    _save();
  }

  /// Выбрать язык интерфейса; `null` — вернуться к системному.
  void setLocale(Locale? locale) {
    state = locale == null
        ? state.copyWith(clearLocale: true)
        : state.copyWith(locale: locale);
    _save();
  }

  /// Включить/выключить авто-акцент. При выключении акцент сразу возвращается
  /// к цвету пресета — на десктопе там точка восстановления (`accentManual`),
  /// но ручного акцента у нас нет, восстанавливать нечего.
  void setAutoAccent(bool value) {
    state = value
        ? state.copyWith(autoAccent: true)
        : state.copyWith(autoAccent: false, clearAccent: true);
    _save();
  }

  void setAutoAccentL(double value) {
    state = state.copyWith(autoAccentL: clampAutoAccentL(value));
    _save();
  }

  /// Цвет, вытащенный из обложки. Приходит из моста авто-акцента; если тоггл
  /// уже успели выключить — молча игнорируем, иначе поздний скан вернул бы
  /// акцент обратно.
  void applyAutoAccent(Color color) {
    if (!state.autoAccent) return;
    if (state.accent?.toARGB32() == color.toARGB32()) return;
    state = state.copyWith(accent: color);
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

  void setNavStyle(NavBarStyle style) {
    state = state.copyWith(navStyle: style);
    _save();
  }

  void setCoverAsBg(bool value) {
    state = state.copyWith(coverAsBg: value);
    _save();
  }

  /// Режим добавления своих файлов. На уже добавленные треки не влияет — как и
  /// на ПК, где смена режима не трогает добавленные папки.
  void setLocalImport(LocalImportMode mode) {
    state = state.copyWith(localImport: mode);
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
