/// Авторизация Яндекс.Музыки (OAuth device-flow) — порт десктопного
/// `features/yandex/model/authStore.ts`.
///
/// `authed` — синхронный флаг, по нему `YandexProvider.isEnabled` решает,
/// показывать ли площадку в поиске и переключателе. Токен лежит в `bloom.json`
/// под ключом `yandex` (на десктопе — в конфиге приложения, тоже открытым
/// текстом) и отдаётся сетевому слою через `ym.setToken`.
///
/// Device-flow: [YmAuthController.startAuth] получает код, открывает страницу
/// подтверждения и поллит токен с гонка-токеном `_pollGen` — logout или
/// повторный старт отменяют прошлый цикл.
///
/// Текстов здесь нет: состояние несёт типизированную причину ([YmAuthNote]), а
/// фразу собирает экран настроек — сторы не возвращают готовые строки.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;
import 'models.dart';
import 'yandex.dart' as ym;
import 'ym_provider.dart' show clearYmStreamCache;

enum YmAuthNoteKind {
  /// Запрашиваем код устройства.
  gettingCode,

  /// Код показан, ждём подтверждения в браузере.
  waiting,

  /// Код протух — «Подключить» заново.
  codeExpired,

  /// Отказ площадки; [YmAuthNote.errorCode] — код `ym.err.*` или текст от неё.
  error,
}

class YmAuthNote {
  final YmAuthNoteKind kind;
  final String? errorCode;
  const YmAuthNote(this.kind, [this.errorCode]);
}

class YmAuthState {
  /// Есть сохранённый токен.
  final bool authed;

  /// Активен ли Яндекс Плюс. null — ещё не проверяли/неизвестно.
  final bool? hasPlus;

  /// Идёт проверка статуса.
  final bool checking;

  /// Идёт device-flow (код получен/показан).
  final bool connecting;
  final String? userCode;
  final String? verifyUrl;
  final YmAuthNote? note;

  const YmAuthState({
    this.authed = false,
    this.hasPlus,
    this.checking = false,
    this.connecting = false,
    this.userCode,
    this.verifyUrl,
    this.note,
  });

  YmAuthState copyWith({
    bool? authed,
    bool? hasPlus,
    bool clearPlus = false,
    bool? checking,
    bool? connecting,
    String? userCode,
    String? verifyUrl,
    bool clearCode = false,
    YmAuthNote? note,
    bool clearNote = false,
  }) => YmAuthState(
    authed: authed ?? this.authed,
    hasPlus: clearPlus ? null : (hasPlus ?? this.hasPlus),
    checking: checking ?? this.checking,
    connecting: connecting ?? this.connecting,
    userCode: clearCode ? null : (userCode ?? this.userCode),
    verifyUrl: clearCode ? null : (verifyUrl ?? this.verifyUrl),
    note: clearNote ? null : (note ?? this.note),
  );
}

final ymAuthProvider = NotifierProvider<YmAuthController, YmAuthState>(
  YmAuthController.new,
);

class YmAuthController extends Notifier<YmAuthState> {
  /// Гонка-токен поллинга: при logout/повторном старте старый цикл отменяется.
  int _pollGen = 0;

  @override
  YmAuthState build() {
    final raw = ref.read(jsonStoreProvider).readMap('yandex');
    final token = raw['token'];
    // Сетевой слой держит токен в модульном состоянии — при старте ему надо
    // отдать сохранённый, иначе провайдер останется выключенным до логина.
    ym.setToken(token is String ? token : null);
    return YmAuthState(authed: ym.activeToken() != null);
  }

  /// Стабильный между запусками id устройства. На десктопе он выводится из
  /// пути LocalAppData; здесь такого якоря нет, поэтому заводим случайный один
  /// раз и храним рядом с токеном. Яндекс его не валидирует, важна только
  /// стабильность.
  String _deviceId() {
    final store = ref.read(jsonStoreProvider);
    final raw = store.readMap('yandex');
    final saved = raw['deviceId'];
    if (saved is String && saved.length >= 16) return saved;
    final rnd = Random.secure();
    final id = [
      for (var i = 0; i < 8; i++)
        rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    store.write('yandex', {...raw, 'deviceId': id});
    return id;
  }

  void _saveToken(String? token) {
    final store = ref.read(jsonStoreProvider);
    final next = {...store.readMap('yandex')};
    if (token == null) {
      next.remove('token');
    } else {
      next['token'] = token;
    }
    store.write('yandex', next);
    ym.setToken(token);
  }

  /// Перечитать статус подписки. Ошибку не считаем разлогином: 401 бывает и от
  /// сбоя, а молча выкинуть пользователя хуже, чем показать «статус
  /// неизвестен» — выйти он может кнопкой.
  Future<void> refresh() async {
    if (!state.authed) {
      state = state.copyWith(checking: false, clearPlus: true);
      return;
    }
    state = state.copyWith(checking: true);
    try {
      final plus = await ym.hasPlus();
      state = state.copyWith(checking: false, hasPlus: plus, clearNote: true);
    } catch (e) {
      state = state.copyWith(
        checking: false,
        clearPlus: true,
        note: YmAuthNote(YmAuthNoteKind.error, '$e'),
      );
    }
  }

  /// Начать device-flow: код → открыть страницу подтверждения → поллинг токена.
  Future<void> startAuth() async {
    _pollGen++; // отменить прошлый поллинг
    state = state.copyWith(
      connecting: true,
      clearCode: true,
      note: const YmAuthNote(YmAuthNoteKind.gettingCode),
    );
    try {
      final d = await ym.authStart(_deviceId());
      state = state.copyWith(
        userCode: d.userCode,
        verifyUrl: d.verificationUrl,
        note: const YmAuthNote(YmAuthNoteKind.waiting),
      );
      // Страница подтверждения открывается в браузере: своей её показать
      // негде, а вводить код всё равно в Яндекс ID. Не открылась — код и
      // адрес видны на экране, пользователь дойдёт руками.
      unawaited(openVerifyPage(d.verificationUrl));

      final gen = ++_pollGen;
      final deadline = DateTime.now().add(d.expiresIn);
      // Меньше 3 секунд между опросами Яндекс считает «slow_down».
      final step = d.interval < const Duration(seconds: 3)
          ? const Duration(seconds: 3)
          : d.interval;
      unawaited(_poll(gen, d.deviceCode, deadline, step));
    } catch (e) {
      state = state.copyWith(
        connecting: false,
        clearCode: true,
        note: YmAuthNote(YmAuthNoteKind.error, '$e'),
      );
    }
  }

  Future<void> _poll(
    int gen,
    String deviceCode,
    DateTime deadline,
    Duration step,
  ) async {
    while (true) {
      if (gen != _pollGen) return; // отменён
      if (DateTime.now().isAfter(deadline)) {
        state = state.copyWith(
          connecting: false,
          clearCode: true,
          note: const YmAuthNote(YmAuthNoteKind.codeExpired),
        );
        return;
      }
      try {
        final r = await ym.authPoll(deviceCode);
        if (gen != _pollGen) return;
        if (!r.isPending) {
          _saveToken(r.token);
          state = state.copyWith(
            authed: true,
            connecting: false,
            clearCode: true,
            clearNote: true,
          );
          await refresh();
          return;
        }
      } catch (e) {
        if (gen != _pollGen) return;
        state = state.copyWith(
          connecting: false,
          clearCode: true,
          note: YmAuthNote(YmAuthNoteKind.error, '$e'),
        );
        return;
      }
      await Future<void>.delayed(step);
    }
  }

  /// Прервать поллинг (уход с экрана, повторный вход).
  void cancelAuth() {
    _pollGen++;
    state = state.copyWith(connecting: false, clearCode: true, clearNote: true);
  }

  /// Выйти: токен удаляется, площадка исчезает из поиска.
  void logout() {
    _pollGen++; // остановить поллинг
    _saveToken(null);
    clearYmStreamCache();
    state = const YmAuthState();
  }
}

/// Открыть страницу подтверждения. Отдельной функцией — тесты подменяют её,
/// чтобы не дёргать браузер.
Future<bool> Function(String url) openVerifyPage = (url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
};

/// Человеческая причина отказа для UI: код `ym.err.*` либо текст площадки.
String ymErrorCode(Object error) {
  final s = error is YmException ? error.code : '$error';
  return s.startsWith('YmException: ') ? s.substring(13) : s;
}
