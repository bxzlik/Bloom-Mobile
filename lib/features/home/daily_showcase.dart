/// Суточная витрина главной — общее у «Для вас» и «Похожие на»: кэш на день,
/// тихие повторы и сброс. Порт поведения `ForYouSection`/`SimilarToSection`.
///
/// Подборка живёт сутки: пересобирать её на каждый заход значит терять трек,
/// который человек заметил, но не успел открыть. Кэш держит сами треки, а не
/// id — площадочный трек после перезапуска иначе было бы нечем заиграть.
///
/// Пока данных нет, витрины нет вовсе (ни скелетона, ни «не удалось
/// загрузить»): пустое место честнее мигающей заглушки. Пустой результат не
/// кэшируется и тихо повторяется — почти всегда это сеть или ещё не вошедший
/// Яндекс, а не «похожих нет».
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/json_store.dart' show jsonStoreProvider;
import '../../providers/yandex/ym_auth.dart';

/// Паузы перед тихими повторами сборки (после последней — сдаёмся до
/// следующего запуска или входа в Яндекс).
const List<Duration> kShowcaseRetries = [
  Duration(milliseconds: 1500),
  Duration(seconds: 4),
];

/// Локальный день (не UTC): подборка меняется по календарю человека.
String showcaseDay(DateTime now) => '${now.year}-${now.month}-${now.day}';

abstract class DailyShowcase<T extends Object> extends Notifier<T?> {
  /// Ключ кэша в `bloom.json`.
  String get storeKey;

  /// Версия ЛОГИКИ отбора. Поменял правила — поднимай, иначе до полуночи висит
  /// выдача, собранная по старым. Отдельно от ключа, чтобы в `bloom.json` не
  /// копились брошенные записи прошлых версий.
  int get version => 1;

  /// Собрать витрину. `null` — показывать нечего (будет повтор).
  Future<T?> fetch();

  Object? encode(T value);
  T? decode(Object? raw);

  /// Идущая сборка — её же отдаёт повторный [load], и её можно дождаться.
  Future<void>? _pending;

  /// Поколение сборки: сброс посреди запроса не должен дать старому ответу
  /// лечь поверх новой витрины.
  int _gen = 0;

  /// Провайдер закрыт — ответ сети писать уже некуда (`state` бросил бы).
  bool _disposed = false;

  bool _stale(int gen) => _disposed || gen != _gen;

  @override
  T? build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // Яндекс добавляет площадку уже по ходу сеанса — пустую витрину стоит
    // попробовать ещё раз, как только он вошёл.
    ref.listen(ymAuthProvider.select((s) => s.authed), (_, _) {
      if (state == null) unawaited(load());
    });
    final cached = _readCache();
    if (cached == null) scheduleMicrotask(() => unawaited(load()));
    return cached;
  }

  T? _readCache() {
    final raw = ref.read(jsonStoreProvider).read(storeKey);
    if (raw is! Map || raw['day'] != showcaseDay(DateTime.now())) return null;
    if ((raw['v'] ?? 1) != version) return null;
    try {
      return decode(raw['data']);
    } on Object {
      return null;
    }
  }

  /// Собрать с тихими повторами. Уже идущая сборка второй не запускает — её же
  /// и возвращает.
  Future<void> load() {
    final running = _pending;
    if (running != null) return running;
    late final Future<void> job;
    job = _load().whenComplete(() {
      // После сброса здесь уже новая сборка — её не трогаем.
      if (identical(_pending, job)) _pending = null;
    });
    return _pending = job;
  }

  /// Дождаться идущей сборки, если она есть. Нужно соседней витрине, которая
  /// сверяется с этой: утром обе собираются разом, и без ожидания сверяться
  /// было бы не с чем.
  Future<void> settled() => _pending ?? Future<void>.value();

  Future<void> _load() async {
    final gen = ++_gen;
    for (var attempt = 0; ; attempt++) {
      T? value;
      try {
        value = await fetch();
      } on Object {
        // Витрина просто не появится — главная от этого не ломается.
        value = null;
      }
      if (_stale(gen)) return;
      if (value != null) {
        state = value;
        ref.read(jsonStoreProvider).write(storeKey, {
          'day': showcaseDay(DateTime.now()),
          'v': version,
          'data': encode(value),
        });
        return;
      }
      if (attempt >= kShowcaseRetries.length) return;
      await Future<void>.delayed(kShowcaseRetries[attempt]);
      if (_stale(gen)) return;
    }
  }

  /// Забыть витрину и собрать заново — часть «Очистить статистику»: сиды взяты
  /// из стёртого топа, и жить подборке до полуночи незачем.
  void reset() {
    _gen++;
    _pending = null;
    ref.read(jsonStoreProvider).removeAll([storeKey]);
    state = null;
    unawaited(load());
  }
}
