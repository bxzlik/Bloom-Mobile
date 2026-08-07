/// Регистрация площадок. Аналог `bootstrap`-вызовов в десктопном `App.tsx`:
/// единственное место, где ядро узнаёт о конкретных провайдерах.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/registry.dart';
import '../providers/soundcloud/sc_provider.dart';

final registryProvider = Provider<ProviderRegistry>((ref) {
  return ProviderRegistry()..register(const SoundCloudProvider());
});

/// Выбранная в поиске площадка ([kAllProviders] — искать во всех).
final activeProviderIdProvider = StateProvider<String>((ref) => kAllProviders);
