/// Гейт онбординга первого запуска — порт десктопного `onboardingStore.ts`.
///
/// На ПК флаг живёт в `localStorage['bloom_onboarded']`, у нас — ключом
/// `onboarded` в общем `bloom.json`. Значения `false` в файле не бывает: пройден
/// — лежит `true`, не пройден — ключа нет вовсе (так же, как в `localStorage`).
///
/// Роутеру нужен ответ ДО того, как соберётся первый маршрут, а `redirect`
/// контейнера Riverpod не видит — поэтому рядом со стором живёт голый флаг
/// [onboardingPending]. Его выставляет сам контроллер, а `main()` читает
/// провайдер до первого кадра, как `ymAuthProvider`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

const String _key = 'onboarded';

/// Онбординг ещё не пройден — роутер уводит любой маршрут на `/onboarding`.
///
/// Пока провайдер не прочитан, тут `false`: не показать онбординг хуже, чем
/// показать его поверх готового приложения, но лучше, чем запереть пользователя
/// на пустом экране, если стор почему-то не поднялся.
bool onboardingPending = false;

final onboardedProvider = NotifierProvider<OnboardingController, bool>(
  OnboardingController.new,
);

class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    final done = ref.read(jsonStoreProvider).read(_key) == true;
    onboardingPending = !done;
    return done;
  }

  /// Отметить пройденным. Экран после этого сам уходит на главную.
  void finish() {
    ref.read(jsonStoreProvider).write(_key, true);
    onboardingPending = false;
    state = true;
  }

  /// Показать заново — то же, что `showOnboarding()` в консоли на ПК.
  /// Строка, которая это зовёт, есть только в отладочной сборке.
  void reset() {
    ref.read(jsonStoreProvider).write(_key, null);
    onboardingPending = true;
    state = false;
  }
}
