/// Связь с ПК в домашней сети — телефонная сторона `Devices` ПК
/// (`src/devices/Devices.cpp`): сопряжение по QR или коду, TLS с закреплённым
/// сертификатом ПК, поиск ПК в сети, когда его адрес сменился.
///
/// ПК сам сервер не ищет и ничего телефону не шлёт: каждый круг ведёт телефон.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Порт поиска ПК — первый порт домашней сети ПК (`kPort` в Devices.cpp).
const int kFindPort = 49410;

String _b64url(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Отпечаток сертификата — как `f` в QR ПК: SHA-256 DER, base64url без `=`.
String certPrint(X509Certificate cert) =>
    _b64url(sha256.convert(cert.der).bytes);

/// Что показывает QR на экране ПК:
/// `{"bloom":"pair","v":1,"a":[адреса],"p":порт,"s":секрет,"f":отпечаток}`.
class PairOffer {
  const PairOffer({
    required this.addresses,
    required this.port,
    required this.secret,
    required this.print,
  });

  final List<String> addresses;
  final int port;
  final String secret;
  final String print;

  /// `null` — это не QR Bloom.
  static PairOffer? parse(String text) {
    Object? doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (doc is! Map || doc['bloom'] != 'pair' || doc['v'] != 1) return null;
    final a = doc['a'], p = doc['p'], s = doc['s'], f = doc['f'];
    if (a is! List || p is! int || s is! String || f is! String) return null;
    final addresses = [
      for (final x in a)
        if (x is String && x.isNotEmpty) x,
    ];
    if (addresses.isEmpty) return null;
    return PairOffer(addresses: addresses, port: p, secret: s, print: f);
  }
}

/// Сопряжённый ПК: кто он, где был в последний раз, чем доказывает, что это
/// он ([print]), и ключ этого телефона ([token]). Лежит в kv `sync.pc`.
class PcLink {
  const PcLink({
    required this.device,
    required this.name,
    required this.token,
    required this.print,
    required this.addresses,
    required this.port,
  });

  final String device;
  final String name;
  final String token;
  final String print;

  /// Где ПК отвечал; первым — где ответил в последний раз.
  final List<String> addresses;
  final int port;

  PcLink at(String address, int port) => PcLink(
    device: device,
    name: name,
    token: token,
    print: print,
    addresses: [
      address,
      for (final a in addresses)
        if (a != address) a,
    ],
    port: port,
  );

  Map<String, Object?> toJson() => {
    'device': device,
    'name': name,
    'token': token,
    'f': print,
    'a': addresses,
    'p': port,
  };

  static PcLink? fromJson(Object? json) {
    if (json is! Map) return null;
    final d = json['device'], n = json['name'], t = json['token'];
    final f = json['f'], a = json['a'], p = json['p'];
    if (d is! String ||
        t is! String ||
        f is! String ||
        a is! List ||
        p is! num) {
      return null;
    }
    return PcLink(
      device: d,
      name: n is String ? n : '',
      token: t,
      print: f,
      addresses: [
        for (final x in a)
          if (x is String) x,
      ],
      port: p.toInt(),
    );
  }
}

/// ПК, ответивший на поиск.
class FoundPc {
  const FoundPc({
    required this.address,
    required this.port,
    required this.device,
    required this.name,
  });

  final String address;
  final int port;
  final String device;
  final String name;
}

/// Ответ ПК, который не 2xx.
class PcHttpError implements Exception {
  const PcHttpError(this.status, this.code);

  final int status;

  /// `error` из ответа ПК: `wrong`, `not_pairing`, `too_many`, `unauthorized`…
  final String code;

  @override
  String toString() => 'PcHttpError($status, $code)';
}

/// Сертификат ПК не тот, что закреплён: другой ПК или его данные сброшены.
class PcPrintMismatch implements Exception {
  const PcPrintMismatch();
}

/// Один ПК по одному адресу. [print] — закреплённый отпечаток; `null` —
/// первое знакомство по коду: берём сертификат, какой есть, и запоминаем его
/// в [seen].
class PcClient {
  PcClient(this.address, this.port, {this.print, this.token});

  final String address;
  final int port;
  final String? print;
  final String? token;

  /// Отпечаток сертификата, увиденного в последнем запросе.
  String? seen;

  Future<Map<String, Object?>> json(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final bytes = await send(
      method,
      path,
      body: body == null ? null : utf8.encode(jsonEncode(body)),
      timeout: timeout,
    );
    final doc = jsonDecode(utf8.decode(bytes));
    return doc is Map<String, Object?> ? doc : <String, Object?>{};
  }

  Future<Uint8List> send(
    String method,
    String path, {
    List<int>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      // Сертификат ПК самоподписанный: цепочку не проверяем, сверяем отпечаток.
      ..badCertificateCallback = (cert, _, _) =>
          print == null || certPrint(cert) == print;
    try {
      final req = await client
          .openUrl(
            method,
            Uri(scheme: 'https', host: address, port: port, path: path),
          )
          .timeout(timeout);
      // Сервер ПК знает только Content-Length, не chunked.
      req.contentLength = body?.length ?? 0;
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        req.headers.contentType = path.startsWith('/v1/sync/picture/')
            ? ContentType.binary
            : ContentType.json;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final cert = res.certificate;
      if (cert == null) throw const PcPrintMismatch();
      seen = certPrint(cert);
      if (print != null && seen != print) throw const PcPrintMismatch();
      final out = BytesBuilder(copy: false);
      await res.forEach(out.add).timeout(timeout);
      final data = out.takeBytes();
      if (res.statusCode >= 300) {
        var code = '';
        try {
          final doc = jsonDecode(utf8.decode(data));
          if (doc is Map && doc['error'] is String) {
            code = doc['error'] as String;
          }
        } catch (_) {}
        throw PcHttpError(res.statusCode, code);
      }
      return data;
    } on HandshakeException {
      // Отпечаток не сошёлся — badCertificateCallback сказал «нет».
      throw const PcPrintMismatch();
    } finally {
      client.close(force: true);
    }
  }
}

/// Сопряжение: [secret] из QR (сертификат сверен с его `f` до отправки) или
/// [code] с экрана ПК (сертификат, увиденный сейчас, закрепляется). Адрес — тот
/// из [addresses], что отозвался первым. Ошибка ПК — [PcHttpError] (`wrong`,
/// `not_pairing`, `too_many`), никто не отозвался — `null`.
Future<PcLink?> pairPc({
  required List<String> addresses,
  required int port,
  String? print,
  String? secret,
  String? code,
  required String name,
  required String device,
}) async {
  // Кто отвечает: без ключа ПК скажет 401 — значит, он там.
  Future<String?> probe(String a) async {
    try {
      await PcClient(
        a,
        port,
        print: print,
      ).send('GET', '/v1', timeout: const Duration(seconds: 4));
      return a;
    } on PcHttpError {
      return a;
    } catch (_) {
      return null;
    }
  }

  final alive = (await Future.wait(addresses.map(probe))).nonNulls;
  if (alive.isEmpty) return null;
  final client = PcClient(alive.first, port, print: print);
  final res = await client.json(
    'POST',
    '/v1/pair',
    body: {'secret': ?secret, 'code': ?code, 'name': name, 'device': device},
  );
  final pc = res['pc'];
  final token = res['token'];
  if (token is! String || pc is! Map || pc['device'] is! String) {
    throw const PcHttpError(0, 'bad_reply');
  }
  return PcLink(
    device: pc['device'] as String,
    name: pc['name'] is String ? pc['name'] as String : '',
    token: token,
    print: print ?? client.seen!,
    addresses: [
      alive.first,
      for (final a in addresses)
        if (a != alive.first) a,
    ],
    port: port,
  );
}

/// Поиск ПК в сети: широковещательно и по [to]. С [print] отвечает только ПК с
/// этим сертификатом; без него — только ПК с открытым окном «Подключить
/// телефон» (сопряжение по коду).
Future<List<FoundPc>> findPcs({
  String? print,
  Iterable<String> to = const [],
  Duration wait = const Duration(milliseconds: 1500),
}) async {
  final found = <String, FoundPc>{};
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final msg = utf8.encode(jsonEncode({'bloom': 'find', 'f': ?print}));
    final done = Completer<void>();
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = socket!.receive();
      if (d == null) return;
      try {
        final o = jsonDecode(utf8.decode(d.data));
        if (o is Map &&
            o['bloom'] == 'here' &&
            o['p'] is int &&
            o['d'] is String) {
          found[o['d'] as String] = FoundPc(
            address: d.address.address,
            port: o['p'] as int,
            device: o['d'] as String,
            name: o['n'] is String ? o['n'] as String : '',
          );
        }
      } catch (_) {}
    });
    for (final target in {'255.255.255.255', ...to}) {
      try {
        socket.send(msg, InternetAddress(target), kFindPort);
      } catch (_) {
        // Адрес из другой сети или без маршрута — пробуем остальные.
      }
    }
    unawaited(Future<void>.delayed(wait).then((_) => done.complete()));
    await done.future;
    await sub.cancel();
  } catch (_) {
    // Сети нет — никого и не нашли.
  } finally {
    socket?.close();
  }
  return found.values.toList();
}
