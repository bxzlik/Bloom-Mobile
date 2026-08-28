/// Web-API Last.fm (`ws.audioscrobbler.com/2.0/`) — порт сетевой части
/// десктопного `features/lastfm/model/lastfmStore.ts`.
///
/// Бэкенда у этой интеграции нет ни там, ни здесь: всё делается прямыми
/// запросами с подписью `api_sig = md5(отсортированные ключ+значение + secret)`.
/// Свой md5 с десктопа (`lastfm/lib/md5.ts`) НЕ переносим — в проекте уже есть
/// пакет `crypto` ради подписи ссылок Яндекса.
///
/// Ключи приложения свои у каждого пользователя (`last.fm/api/account/create`),
/// вшитого ключа Bloom нет — как и на ПК.
///
/// Ошибки наружу не бросаем: скробблинг — фоновое дело, ронять из-за него
/// воспроизведение нельзя. Неудача выглядит как `null`/`false`.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

const String kLastfmBase = 'https://ws.audioscrobbler.com/2.0/';

/// Страница подтверждения доступа: туда уходит браузер после `auth.getToken`.
String lastfmAuthUrl(String apiKey, String token) =>
    'https://www.last.fm/api/auth/?api_key=$apiKey&token=$token';

/// Где заводят свои ключи. Показывается в инструкции.
const String kLastfmApiAccountUrl = 'https://www.last.fm/api/account/create';

/// Подпись запроса — десктопный `sign`: ключи по алфавиту, значения встык,
/// в хвост секрет, всё это md5 по UTF-8. `format` в подпись НЕ входит: его
/// добавляют уже после (так же на ПК и так же требует сам Last.fm).
String lastfmSign(Map<String, String> params, String apiSecret) {
  final keys = params.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final k in keys) {
    buffer
      ..write(k)
      ..write(params[k]);
  }
  buffer.write(apiSecret);
  return md5.convert(utf8.encode(buffer.toString())).toString();
}

/// Транспорт запросов. Отдельной переменной — чтобы тесты подменяли его и не
/// ходили в сеть (тот же приём, что `openVerifyPage` у Яндекса).
typedef LastfmTransport =
    Future<Map<String, dynamic>?> Function(
      Map<String, String> form, {
      bool get,
    });

LastfmTransport lastfmTransport = defaultLastfmTransport;

final http.Client _http = http.Client();

/// Настоящий транспорт — HTTP. Отдельным именем, чтобы тест мог вернуть его на
/// место после подмены.
Future<Map<String, dynamic>?> defaultLastfmTransport(
  Map<String, String> form, {
  bool get = false,
}) async {
  try {
    final res = get
        ? await _http.get(Uri.parse(kLastfmBase).replace(queryParameters: form))
        : await _http.post(Uri.parse(kLastfmBase), body: form);
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : null;
  } catch (_) {
    // Сеть отвалилась / пришёл не JSON: для скробблинга это просто «не вышло».
    return null;
  }
}

/// Подписанный POST. Возвращает разобранный ответ либо `null`.
Future<Map<String, dynamic>?> lastfmPost(
  Map<String, String> params, {
  required String apiKey,
  required String apiSecret,
}) {
  if (apiKey.isEmpty || apiSecret.isEmpty) return Future.value(null);
  final p = {...params, 'api_key': apiKey};
  return lastfmTransport({
    ...p,
    'api_sig': lastfmSign(p, apiSecret),
    'format': 'json',
  }, get: false);
}

/// Ответ `auth.getToken`: либо токен, либо причина отказа от самой площадки.
class LastfmTokenResult {
  const LastfmTokenResult({this.token, this.message});

  final String? token;

  /// Текст ошибки Last.fm (`message`), если токена не дали.
  final String? message;
}

/// Шаг 1 OAuth: разовый токен. Подписи не требует.
Future<LastfmTokenResult> lastfmGetToken(String apiKey) async {
  final data = await lastfmTransport({
    'method': 'auth.getToken',
    'api_key': apiKey,
    'format': 'json',
  }, get: true);
  if (data == null) return const LastfmTokenResult();
  final token = data['token'];
  final message = data['message'];
  return LastfmTokenResult(
    token: token is String && token.isNotEmpty ? token : null,
    message: message is String ? message : null,
  );
}

/// Сессия Last.fm: ключ и ник.
class LastfmSession {
  const LastfmSession({required this.key, required this.name});

  final String key;
  final String name;
}

/// Ответ `auth.getSession`. Сессии нет — либо доступ ещё не подтверждён в
/// браузере, либо площадка объяснила причину в [message].
class LastfmSessionResult {
  const LastfmSessionResult({this.session, this.message});

  final LastfmSession? session;
  final String? message;
}

/// Шаг 2 OAuth: обмен подтверждённого токена на ключ сессии.
Future<LastfmSessionResult> lastfmGetSession({
  required String apiKey,
  required String apiSecret,
  required String token,
}) async {
  final data = await lastfmPost(
    {'method': 'auth.getSession', 'token': token},
    apiKey: apiKey,
    apiSecret: apiSecret,
  );
  if (data == null) return const LastfmSessionResult();
  final session = data['session'];
  final message = data['message'];
  if (session is Map) {
    final key = session['key'];
    final name = session['name'];
    if (key is String && key.isNotEmpty) {
      return LastfmSessionResult(
        session: LastfmSession(key: key, name: name is String ? name : ''),
      );
    }
  }
  return LastfmSessionResult(message: message is String ? message : null);
}

/// «Сейчас играет». Статус живёт у Last.fm недолго и обновляется на каждом
/// треке — результат никого не интересует.
Future<void> lastfmNowPlaying({
  required String apiKey,
  required String apiSecret,
  required String sk,
  required String artist,
  required String track,
  required String album,
}) async {
  await lastfmPost(
    {
      'method': 'track.updateNowPlaying',
      'artist': artist,
      'track': track,
      'album': album,
      'sk': sk,
    },
    apiKey: apiKey,
    apiSecret: apiSecret,
  );
}

/// Засчитать прослушивание. [timestamp] — секунды Unix НАЧАЛА трека, как
/// требует Last.fm (и как считает десктоп).
Future<void> lastfmScrobble({
  required String apiKey,
  required String apiSecret,
  required String sk,
  required String artist,
  required String track,
  required String album,
  required int timestamp,
}) async {
  await lastfmPost(
    {
      'method': 'track.scrobble',
      'artist': artist,
      'track': track,
      'timestamp': '$timestamp',
      'album': album,
      'sk': sk,
    },
    apiKey: apiKey,
    apiSecret: apiSecret,
  );
}
