/// Мост авто-акцента — порт десктопного `autoAccentBridge.ts`.
///
/// Когда тоггл включён, при смене обложки играющего трека вытаскиваем из неё
/// доминантный цвет и ставим акцентом. Тон последней просканированной обложки
/// держим в поле: ползунок яркости пересчитывает акцент из него, не трогая
/// картинку заново.
///
/// Провайдер держится живым из `main()` — как мост на десктопе монтируется в
/// `App.tsx`: акцент должен ехать за треком, даже когда настройки закрыты.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/settings_store.dart';
import '../player/player_controller.dart';
import 'cover_accent.dart';

final autoAccentProvider = Provider<AutoAccentBridge>((ref) {
  final bridge = AutoAccentBridge(ref);
  ref.listen(
    playbackProvider.select((s) => s.track?.cover),
    (_, _) => bridge.rescan(),
  );
  ref.listen(settingsProvider.select((s) => s.autoAccent), (_, _) {
    bridge.rescan();
  });
  // Яркость — пересчёт из уже известного тона, скан не нужен.
  ref.listen(settingsProvider.select((s) => s.autoAccentL), (_, _) {
    bridge.reapply();
  });
  bridge.rescan();
  return bridge;
});

class AutoAccentBridge {
  AutoAccentBridge(this._ref);

  final Ref _ref;

  /// Тон последней просканированной обложки.
  CoverHsl? _last;

  /// Номер последнего скана: пока грузилась одна обложка, трек мог смениться —
  /// цвет опоздавшего скана применять нельзя.
  int _token = 0;

  Future<void> rescan() async {
    final settings = _ref.read(settingsProvider);
    final cover = _ref.read(playbackProvider).track?.cover;
    if (!settings.autoAccent || cover == null || cover.isEmpty) return;
    final my = ++_token;
    final hsl = await extractCoverHsl(cover);
    if (my != _token || hsl == null) return;
    _last = hsl;
    _apply(hsl);
  }

  /// Пересчитать акцент из уже известного тона — движение ползунка яркости.
  void reapply() {
    final hsl = _last;
    if (hsl == null) {
      rescan();
      return;
    }
    _apply(hsl);
  }

  void _apply(CoverHsl hsl) {
    final level = _ref.read(settingsProvider).autoAccentL;
    _ref
        .read(settingsProvider.notifier)
        .applyAutoAccent(accentFromHsl(hsl, level));
  }
}
