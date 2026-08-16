/// Анимация смены трека — настройка, порт `trackAnim` из десктопного
/// `settings/model/playerViewStore.ts`.
///
/// Поверхностей на телефоне две (на ПК их три — там ещё полноэкранный режим,
/// которого у нас нет), и настраиваются они порознь: коробки разного размера, и
/// одна настройка на обеих заставляла бы выбирать между «красиво в плеере» и
/// «не рябит в карточке над таб-баром».
///
/// Обложка и подпись — тоже независимо, как на ПК: у них разный вес в кадре, и
/// слайд обложки при спокойном затухании текста — рабочее сочетание, а не
/// недонастройка.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Тип анимации смены трека: нет / слайд по направлению перехода / затухание.
enum TrackAnimKind { none, slide, fade }

/// Где эта анимация играет.
enum TrackAnimSurface {
  /// Полноэкранный плеер.
  player,

  /// Миниплеер — карточка над таб-баром.
  mini,
}

/// Что именно анимируется на одной поверхности.
enum TrackAnimTarget {
  /// Обложка.
  cover,

  /// Подпись: название + артист.
  text,
}

/// Настройка одной поверхности.
class TrackAnimCfg {
  const TrackAnimCfg(this.cover, this.text);

  final TrackAnimKind cover;
  final TrackAnimKind text;

  TrackAnimKind of(TrackAnimTarget target) =>
      target == TrackAnimTarget.cover ? cover : text;

  TrackAnimCfg withTarget(TrackAnimTarget target, TrackAnimKind kind) =>
      target == TrackAnimTarget.cover
      ? TrackAnimCfg(kind, text)
      : TrackAnimCfg(cover, kind);
}

/// Умолчания — те же, что на ПК: слайд везде и у всего.
const Map<TrackAnimSurface, TrackAnimCfg> kDefaultTrackAnim = {
  TrackAnimSurface.player: TrackAnimCfg(
    TrackAnimKind.slide,
    TrackAnimKind.slide,
  ),
  TrackAnimSurface.mini: TrackAnimCfg(TrackAnimKind.slide, TrackAnimKind.slide),
};

class TrackAnimSettings {
  const TrackAnimSettings({this.surfaces = kDefaultTrackAnim});

  final Map<TrackAnimSurface, TrackAnimCfg> surfaces;

  TrackAnimCfg of(TrackAnimSurface surface) =>
      surfaces[surface] ?? kDefaultTrackAnim[surface]!;

  TrackAnimSettings withSurface(TrackAnimSurface surface, TrackAnimCfg cfg) =>
      TrackAnimSettings(surfaces: {...surfaces, surface: cfg});
}

final trackAnimProvider =
    NotifierProvider<TrackAnimController, TrackAnimSettings>(
      TrackAnimController.new,
    );

class TrackAnimController extends Notifier<TrackAnimSettings> {
  @override
  TrackAnimSettings build() {
    final raw = ref.read(jsonStoreProvider).readMap('trackAnim');
    return TrackAnimSettings(
      surfaces: {
        for (final surface in TrackAnimSurface.values)
          surface: _cfgFromJson(raw[surface.name], kDefaultTrackAnim[surface]!),
      },
    );
  }

  void setKind(
    TrackAnimSurface surface,
    TrackAnimTarget target,
    TrackAnimKind kind,
  ) {
    state = state.withSurface(
      surface,
      state.of(surface).withTarget(target, kind),
    );
    _save();
  }

  void _save() => ref.read(jsonStoreProvider).write('trackAnim', {
    for (final surface in TrackAnimSurface.values)
      surface.name: {
        'cover': state.of(surface).cover.name,
        'text': state.of(surface).text.name,
      },
  });
}

/// Настройка поверхности из хранилища. Битую или незнакомую запись (правили
/// файл руками, откат на старую сборку) молча заменяем умолчанием — тип
/// анимации не повод ронять запуск.
TrackAnimCfg _cfgFromJson(Object? raw, TrackAnimCfg fallback) {
  if (raw is! Map) return fallback;
  return TrackAnimCfg(
    _kindFromJson(raw['cover'], fallback.cover),
    _kindFromJson(raw['text'], fallback.text),
  );
}

TrackAnimKind _kindFromJson(Object? raw, TrackAnimKind fallback) {
  for (final kind in TrackAnimKind.values) {
    if (kind.name == raw) return kind;
  }
  return fallback;
}
