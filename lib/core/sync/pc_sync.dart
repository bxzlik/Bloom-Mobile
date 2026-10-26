/// Один круг синхронизации с ПК — телефонная сторона `SyncHost` ПК
/// (`src/sync/SyncHost.cpp`). Круг ведёт телефон:
///
/// 1. `GET /v1/sync` — id и часы ПК, докуда ПК уже принял наше (`got`);
/// 2. своё от этого курсора (`ownOnly`): сначала картинки, которых у ПК нет,
///    потом `POST /v1/sync/push`; пока `more`;
/// 3. `POST /v1/sync/pull` от наших курсоров ПК, картинки, которых нет у нас,
///    и [SyncLog.apply]; пока `more`.
///
/// Часы: изменение побеждает по своему `mod`, а это часы устройства. Разница
/// с ПК меряется в начале круга; если она заметная, `mod` уходящих изменений
/// переводится на часы ПК, а пришедших — на наши. Прослушивания не сдвигаются:
/// по времени они узнают свои дубли.
library;

import 'dart:typed_data';

import '../db/db.dart';
import '../log/bloom_log.dart';
import 'pc_client.dart';
import 'sync_log.dart';
import 'sync_pictures.dart';

/// Разница часов меньше этой — не разница (сеть сама даёт десятки мс).
const int _kSkewMs = 2000;

/// Чем кончился круг.
class SyncRound {
  const SyncRound({
    required this.link,
    required this.touched,
    required this.sent,
    required this.took,
  });

  /// Связка с адресом, по которому ПК ответил (его стоит сохранить).
  final PcLink link;

  /// Виды, изменившиеся здесь ([SyncLog.apply]).
  final Set<String> touched;
  final int sent, took;
}

/// ПК не нашёлся ни по одному адресу, ни поиском.
class PcUnreachable implements Exception {
  const PcUnreachable();
}

/// По адресу ответил не тот ПК (его база новая — новый id).
class PcChanged implements Exception {
  const PcChanged();
}

Future<SyncRound> syncWithPc(PcLink link, BloomDb db, String coversDir) async {
  final reached = await reachPc(link);
  final client = reached.client;
  link = reached.link;
  final hello = reached.hello;
  if (hello['device'] != link.device) throw const PcChanged();
  final skew = reached.skew;

  final log = SyncLog(db);
  final pictures = SyncPictures(db, coversDir);

  // ── своё на ПК ──
  var sent = 0;
  var cursor = hello['got'] is Map ? hello['got'] as Map : const {};
  while (true) {
    final out = log.outgoing(
      link.device,
      seq: _int(cursor['seq']),
      play: _int(cursor['play']),
      ownOnly: true,
    );
    final names = pictures.toWire(out);
    _shift(out, skew);
    if (names.isNotEmpty) {
      final ask = await client.json(
        'POST',
        '/v1/sync/pictures',
        body: {'names': names.toList()},
      );
      for (final name in (ask['missing'] as List?) ?? const []) {
        final bytes = name is String ? pictures.read(name) : null;
        if (bytes != null) {
          await client.send('PUT', '/v1/sync/picture/$name', body: bytes);
        }
      }
    }
    final res = await client.json(
      'POST',
      '/v1/sync/push',
      body: out,
      timeout: const Duration(seconds: 60),
    );
    sent += (out['changes'] as List).length + (out['plays'] as List).length;
    cursor = res['got'] is Map ? res['got'] as Map : const {};
    if (out['more'] != true) break;
  }

  // ── своё ПК здесь ──
  var took = 0;
  final touched = <String>{};
  while (true) {
    final from = log.got(link.device);
    final payload = await client.json(
      'POST',
      '/v1/sync/pull',
      body: {'seq': from.seq, 'play': from.play},
      timeout: const Duration(seconds: 60),
    );
    for (final name in pictures.wanted(payload)) {
      if (pictures.has(name)) continue;
      try {
        final bytes = await client.send('GET', '/v1/sync/picture/$name');
        pictures.put(name, Uint8List.fromList(bytes));
      } on PcHttpError catch (e) {
        // У ПК её уже нет — изменение придёт без картинки.
        if (e.status != 404) rethrow;
      }
    }
    pictures.fromWire(payload);
    _shift(payload, -skew);
    if (!log.apply(payload, touched: touched)) {
      throw const PcHttpError(0, 'refused');
    }
    took +=
        ((payload['changes'] as List?) ?? const []).length +
        ((payload['plays'] as List?) ?? const []).length;
    if (payload['more'] != true) break;
  }
  logInfo(
    'sync',
    'с ПК «${link.name}»: отдал $sent, взял $took · ${touched.join(' ')}',
  );
  return SyncRound(link: link, touched: touched, sent: sent, took: took);
}

/// Где ПК сейчас: адрес, где он ответил в последний раз, потом остальные
/// разом, потом поиск в сети по отпечатку.
Future<({PcClient client, PcLink link, Map<String, Object?> hello, int skew})>
reachPc(PcLink link) async {
  Future<({PcClient client, Map<String, Object?> hello, int skew})?> hello(
    String address,
    int port,
  ) async {
    final c = PcClient(address, port, print: link.print, token: link.token);
    try {
      final t0 = DateTime.now().millisecondsSinceEpoch;
      final h = await c.json(
        'GET',
        '/v1/sync',
        timeout: const Duration(seconds: 5),
      );
      final t1 = DateTime.now().millisecondsSinceEpoch;
      final skew = _int(h['now']) - (t0 + t1) ~/ 2;
      return (client: c, hello: h, skew: skew.abs() < _kSkewMs ? 0 : skew);
    } on PcHttpError {
      rethrow; // ПК ответил, но не пустил: искать дальше незачем
    } on PcPrintMismatch {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  if (link.addresses.isNotEmpty) {
    final first = await hello(link.addresses.first, link.port);
    if (first != null) {
      return (
        client: first.client,
        link: link,
        hello: first.hello,
        skew: first.skew,
      );
    }
  }
  final rest = link.addresses.skip(1).toList();
  if (rest.isNotEmpty) {
    final tries = await Future.wait([
      for (final a in rest) hello(a, link.port),
    ]);
    for (var i = 0; i < rest.length; i++) {
      final r = tries[i];
      if (r != null) {
        return (
          client: r.client,
          link: link.at(rest[i], link.port),
          hello: r.hello,
          skew: r.skew,
        );
      }
    }
  }
  for (final pc in await findPcs(print: link.print, to: link.addresses)) {
    if (pc.device != link.device) continue;
    final r = await hello(pc.address, pc.port);
    if (r != null) {
      return (
        client: r.client,
        link: link.at(pc.address, pc.port),
        hello: r.hello,
        skew: r.skew,
      );
    }
  }
  throw const PcUnreachable();
}

void _shift(Map<String, Object?> payload, int by) {
  if (by == 0) return;
  for (final c in (payload['changes'] as List?) ?? const []) {
    if (c is Map && c['mod'] is num) c['mod'] = (c['mod'] as num).toInt() + by;
  }
}

int _int(Object? v) => v is num ? v.toInt() : 0;
