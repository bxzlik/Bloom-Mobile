/// Вход в Яндекс.Музыку: что переживает перезапуск и когда площадка вообще
/// участвует в поиске. Хранилище — в памяти, сеть не трогаем.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/providers/yandex/models.dart';
import 'package:bloom/providers/yandex/yandex.dart' as ym;
import 'package:bloom/providers/yandex/ym_auth.dart';
import 'package:bloom/providers/yandex/ym_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(JsonStore store) {
  final c = ProviderContainer(
    overrides: [jsonStoreProvider.overrideWithValue(store)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  setUp(() => ym.setToken(null));
  tearDown(() => ym.setToken(null));

  test('сохранённый токен поднимается при старте и включает площадку', () {
    final store = JsonStore.memory({
      'yandex': {'token': 'saved-token'},
    });
    final c = _container(store);

    expect(
      const YandexProvider().isEnabled,
      isFalse,
      reason: 'до чтения стора',
    );
    expect(c.read(ymAuthProvider).authed, isTrue);
    // Токен уезжает в сетевой слой, иначе первый же запрос ушёл бы без него.
    expect(ym.activeToken(), 'saved-token');
    expect(const YandexProvider().isEnabled, isTrue);
  });

  test('пустое хранилище — площадка выключена', () {
    final c = _container(JsonStore.memory());
    expect(c.read(ymAuthProvider).authed, isFalse);
    expect(ym.activeToken(), isNull);
    expect(const YandexProvider().isEnabled, isFalse);
  });

  test('выход стирает токен и с диска, и из сетевого слоя', () {
    final store = JsonStore.memory({
      'yandex': {'token': 'saved-token', 'deviceId': 'abcdef0123456789'},
    });
    final c = _container(store);
    c.read(ymAuthProvider);

    c.read(ymAuthProvider.notifier).logout();

    expect(c.read(ymAuthProvider).authed, isFalse);
    expect(ym.activeToken(), isNull);
    final raw = store.readMap('yandex');
    expect(raw['token'], isNull);
    // id устройства переживает выход: он привязан к установке, а не к аккаунту.
    expect(raw['deviceId'], 'abcdef0123456789');
  });

  test('статус подписки не проверяется, пока не вошли', () async {
    final c = _container(JsonStore.memory());
    await c.read(ymAuthProvider.notifier).refresh();
    // Сети тут нет: если бы refresh пошёл в API, тест упал бы на исключении.
    expect(c.read(ymAuthProvider).hasPlus, isNull);
    expect(c.read(ymAuthProvider).checking, isFalse);
  });

  test('отмена входа гасит поллинг и убирает код с экрана', () {
    final c = _container(JsonStore.memory());
    final notifier = c.read(ymAuthProvider.notifier);

    notifier.cancelAuth();

    final s = c.read(ymAuthProvider);
    expect(s.connecting, isFalse);
    expect(s.userCode, isNull);
    expect(s.note, isNull);
  });

  test('причина отказа доезжает до UI кодом, а не «Instance of»', () {
    expect(
      ymErrorCode(const YmException('ym.err.needPlus')),
      'ym.err.needPlus',
    );
    // Ошибка, всплывшая через toString (так она приходит из состояния стора).
    expect(ymErrorCode('YmException: ym.err.auth'), 'ym.err.auth');
  });
}
