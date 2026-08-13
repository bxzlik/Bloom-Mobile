/// Регистрация площадок. Аналог `bootstrap`-вызовов в десктопном `App.tsx`:
/// единственное место, где ядро узнаёт о конкретных провайдерах.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/registry.dart';
import '../providers/soundcloud/sc_provider.dart';
import '../providers/yandex/ym_provider.dart';
import '../providers/ytmusic/ytm_provider.dart';

final registryProvider = Provider<ProviderRegistry>((ref) {
  // Яндекс регистрируется всегда, а показывается только после логина: его
  // `isEnabled` смотрит на сохранённый токен (см. `ymAuthProvider`).
  // YouTube Music включён всегда — авторизации он не требует.
  return ProviderRegistry()
    ..register(const SoundCloudProvider())
    ..register(const YtmusicProvider())
    ..register(const YandexProvider());
});

/// Выбранная в поиске площадка ([kAllProviders] — искать во всех).
final activeProviderIdProvider = StateProvider<String>((ref) => kAllProviders);
