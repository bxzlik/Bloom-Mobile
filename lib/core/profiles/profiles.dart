/// Who uses this Bloom. `profiles.json` in the root lists the profiles (id, a
/// copy of the card's name and avatar for the gate, the lock), which one was
/// open last and whether it was left signed out. Nothing else is shared
/// between profiles: each keeps its files in `<root>/profiles/<id>`.
///
/// A launch opens the last profile straight away, as Steam does. The gate
/// comes instead when there is none, when it was signed out of, or when it's
/// locked: a 4-digit PIN, asked at every launch (five wrong ones in a row: a
/// 30 s wait), or a fingerprint or face when its owner turned that on. The
/// lock only keeps the way in shut; the files stay as they are.
///
/// Switching profiles closes the open one inside the process: see
/// `app/session.dart`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../log/bloom_log.dart';
import '../store/app_dirs.dart';

/// Wrong PINs in a row before a wait, and the wait.
const int _kTries = 5;
const int _kWaitMs = 30 * 1000;

/// PBKDF2-SHA256: slow enough to make guessing dull, quick enough not to be
/// felt.
const int _kRounds = 100000;

const int kProfileNameMax = 32;

/// The PIN's length: exactly 4 digits, as on a phone's lock screen.
const int kPinLength = 4;

/// The `local:` prefix of an own picture, as in the card.
const String _local = 'local:';

/// One row of the gate's list.
class ProfileEntry {
  const ProfileEntry({
    required this.id,
    required this.name,
    required this.avatar,
    required this.locked,
    required this.bio,
  });

  final String id;

  /// The card's nick; empty means none, and the default name fills in.
  final String name;

  /// The avatar file's absolute path, or `null`.
  final String? avatar;

  /// It has a PIN.
  final bool locked;

  /// Its owner opens it by fingerprint or face (only with a PIN).
  final bool bio;
}

/// How a launch goes on: a profile opens straight away, or the gate shows.
class ProfilesStart {
  const ProfilesStart.open(String this.id) : view = null, look = null;
  const ProfilesStart.gate(String this.view, {this.id, this.look});

  /// The profile to open, or the locked one the gate asks the PIN of.
  final String? id;

  /// The gate's first screen: `create` (none yet), `pin`, `list`; `null`
  /// means open [id].
  final String? view;

  /// Whose settings the gate looks like: the last profile's, else the first's.
  final String? look;

  bool get gate => view != null;
}

class Profiles {
  Profiles._(this.root);

  static Profiles? _instance;

  /// Set up by [init] before anything else touches a profile's files.
  static Profiles get instance =>
      _instance ?? (throw StateError('Profiles.init() was not called'));

  /// `null` where nothing set them up (tests).
  static Profiles? get maybe => _instance;

  static Future<Profiles> init() async =>
      _instance ??= Profiles._((await appRootDir()).path);

  /// A test root, with no platform directories.
  static Profiles forTest(String root) => _instance = Profiles._(root);

  final String root;

  File get _file => File('$root/profiles.json');

  String dirOf(String id) => profileDirPath(root, id);

  // ── The file ──

  Map<String, dynamic> _load() {
    try {
      if (!_file.existsSync()) return {};
      final doc = jsonDecode(_file.readAsStringSync());
      if (doc is Map) return doc.cast<String, dynamic>();
    } catch (e) {
      logWarn('profiles', 'profiles.json is broken: $e');
    }
    return {};
  }

  bool _save(Map<String, dynamic> doc) {
    try {
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(
        const JsonEncoder.withIndent('    ').convert(doc),
        flush: true,
      );
      tmp.renameSync(_file.path);
      return true;
    } catch (e) {
      logError('profiles', 'cannot write profiles.json', e);
      return false;
    }
  }

  static List<Map<String, dynamic>> _entries(Map<String, dynamic> doc) => [
    for (final v in (doc['list'] as List? ?? const []))
      if (v is Map) v.cast<String, dynamic>(),
  ];

  static Map<String, dynamic>? _entry(Map<String, dynamic> doc, String? id) {
    for (final e in _entries(doc)) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  /// The list with one entry changed by [fn], or dropped when it says false.
  static void _edit(
    Map<String, dynamic> doc,
    String id,
    bool Function(Map<String, dynamic> e) fn,
  ) {
    doc['list'] = [
      for (final e in _entries(doc))
        if (e['id'] != id || fn(e)) e,
    ];
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  String _newId(Map<String, dynamic> doc) {
    final rnd = Random.secure();
    for (;;) {
      final id = rnd.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
      if (_entry(doc, id) == null && !Directory(dirOf(id)).existsSync()) {
        return id;
      }
    }
  }

  void _erase(String id) {
    if (id.isEmpty) return;
    try {
      final dir = Directory(dirOf(id));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      logInfo('profiles', 'deleted profile $id');
    } catch (e) {
      logError('profiles', 'profile $id not deleted', e);
    }
  }

  // ── Launch ──

  /// Each launch and each return to the gate: deletes what was asked to go,
  /// then picks the profile or the gate.
  ProfilesStart boot() {
    final doc = _load();
    var dirty = false;

    // Deleted from inside: its files were still open then.
    final drop = doc.remove('drop');
    if (drop is List) {
      for (final id in drop.whereType<String>()) {
        _erase(id);
        _edit(doc, id, (_) => false);
      }
      dirty = true;
    }
    // A last profile that's gone (deleted, or its folder taken away).
    if (doc.containsKey('last') &&
        _entry(doc, doc['last'] as String?) == null) {
      doc.remove('last');
      dirty = true;
    }
    if (dirty) _save(doc);

    final last = doc['last'] as String?;
    final list = _entries(doc);
    final look = last ?? (list.isEmpty ? null : list.first['id'] as String?);
    final e = _entry(doc, last);
    if (e != null && doc['out'] != true) {
      if (!_hasLock(e)) {
        logInfo('profiles', 'profile $last');
        return ProfilesStart.open(last!);
      }
      logInfo('profiles', 'gate: pin');
      return ProfilesStart.gate('pin', id: last, look: look);
    }
    final view = list.isEmpty ? 'create' : 'list';
    logInfo('profiles', 'gate: $view');
    return ProfilesStart.gate(view, look: look);
  }

  static bool _hasLock(Map<String, dynamic> e) =>
      e['lock'] is Map && (e['lock'] as Map).isNotEmpty;

  // ── The gate ──

  List<ProfileEntry> list() => [for (final e in _entries(_load())) _view(e)];

  ProfileEntry? find(String? id) {
    final e = _entry(_load(), id);
    return e == null ? null : _view(e);
  }

  ProfileEntry _view(Map<String, dynamic> e) {
    final id = e['id'] as String? ?? '';
    return ProfileEntry(
      id: id,
      name: e['name'] as String? ?? '',
      avatar: _avatarPath(id, e['avatar']),
      locked: _hasLock(e),
      bio: _hasLock(e) && e['bio'] == true,
    );
  }

  String? _avatarPath(String id, Object? avatar) {
    if (avatar is! String || !avatar.startsWith(_local)) return null;
    final path = '${dirOf(id)}/covers/${avatar.substring(_local.length)}';
    return File(path).existsSync() ? path : null;
  }

  /// An unlocked profile becomes the one to open. False when it's locked.
  bool open(String id) {
    final doc = _load();
    final e = _entry(doc, id);
    if (e == null || _hasLock(e)) return false;
    _opened(doc, id);
    return _save(doc);
  }

  /// A fingerprint or face let the owner in: no PIN this time.
  bool openByBio(String id) {
    final doc = _load();
    final e = _entry(doc, id);
    if (e == null || e['bio'] != true) return false;
    _opened(doc, id);
    return _save(doc);
  }

  void _opened(Map<String, dynamic> doc, String id) {
    _edit(doc, id, (e) {
      e.remove('fails');
      e.remove('wait');
      return true;
    });
    doc['last'] = id;
    doc.remove('out');
  }

  /// The PIN right: 0, the profile is the one to open. Wrong: -1, or the
  /// seconds to wait when that was one too many (and while that wait lasts).
  Future<int> unlock(String id, String pin) async {
    final wait = waitLeft(id);
    if (wait > 0) return wait;
    final lock = _entry(_load(), id)?['lock'];
    if (lock == null) return -1;
    final ok = await _fits(lock, pin);
    // Re-read: the check took a while.
    final doc = _load();
    if (_entry(doc, id) == null) return -1;
    if (!ok) {
      // As on a phone: so many wrong ones in a row, then a wait.
      var out = -1;
      _edit(doc, id, (e) {
        final fails = ((e['fails'] as num?)?.toInt() ?? 0) + 1;
        if (fails >= _kTries) {
          e.remove('fails');
          e['wait'] = _now() + _kWaitMs;
          out = _kWaitMs ~/ 1000;
        } else {
          e['fails'] = fails;
        }
        return true;
      });
      _save(doc);
      return out;
    }
    _opened(doc, id);
    _save(doc);
    return 0;
  }

  /// Seconds left of a wait after wrong PINs, 0 if none.
  int waitLeft(String id) {
    final until = (_entry(_load(), id)?['wait'] as num?)?.toInt() ?? 0;
    final left = until - _now();
    // A clock put back mustn't make it endless.
    return left > 0 && left <= _kWaitMs ? (left + 999) ~/ 1000 : 0;
  }

  /// A new profile, the one to open. [avatar]: a cropped picture or `null`;
  /// [pin]: 4 digits, or `null` for none. Returns its id.
  Future<String?> make(String name, Uint8List? avatar, String? pin) async {
    if (pin != null && !isPin(pin)) return null;
    final lock = pin == null ? null : await _lockFor(pin);
    final doc = _load();
    final id = _newId(doc);
    final covers = Directory('${dirOf(id)}/covers');
    covers.createSync(recursive: true);

    String? picture;
    if (avatar != null) {
      final name = 'avatar_${_now()}.png';
      try {
        File('${covers.path}/$name').writeAsBytesSync(avatar, flush: true);
        picture = '$_local$name';
      } catch (e) {
        logWarn('profiles', 'the new profile\'s picture was not saved: $e');
      }
    }
    final e = <String, dynamic>{
      'id': id,
      'name': _clip(name),
      'avatar': picture ?? '',
      'created': _now(),
      'lock': ?lock,
    };
    doc['list'] = [..._entries(doc), e];
    doc['last'] = id;
    doc.remove('out');
    if (!_save(doc)) return null;
    logInfo('profiles', 'new profile $id');
    return id;
  }

  /// "Forgot the PIN": the profile and all its files go.
  void forget(String id) {
    final doc = _load();
    if (_entry(doc, id) == null) return;
    _erase(id);
    _edit(doc, id, (_) => false);
    if (doc['last'] == id) doc.remove('last');
    _save(doc);
  }

  // ── The open profile ──

  String? get _open => openProfileId;

  bool get locked => _hasLock(_entry(_load(), _open) ?? const {});

  bool get bioOn => _entry(_load(), _open)?['bio'] == true && locked;

  Future<bool> checkPin(String pin) async {
    final lock = _entry(_load(), _open)?['lock'];
    return lock == null || await _fits(lock, pin);
  }

  /// A new PIN, or none with `null`. The current one is checked first, if
  /// there is one. Dropping the PIN drops the fingerprint too: it has nothing
  /// to stand in for.
  Future<bool> setPin(String? current, String? pin) async {
    final id = _open;
    if (id == null || (pin != null && !isPin(pin))) return false;
    if (locked && (current == null || !await checkPin(current))) return false;
    final lock = pin == null ? null : await _lockFor(pin);
    final doc = _load();
    _edit(doc, id, (e) {
      if (lock == null) {
        e.remove('lock');
        e.remove('bio');
      } else {
        e['lock'] = lock;
      }
      return true;
    });
    return _save(doc);
  }

  void setBio(bool on) {
    final id = _open;
    if (id == null) return;
    final doc = _load();
    _edit(doc, id, (e) {
      if (on) {
        e['bio'] = true;
      } else {
        e.remove('bio');
      }
      return true;
    });
    _save(doc);
  }

  /// Back to the gate's list on the next start of the gate.
  void signOut() {
    final doc = _load()..['out'] = true;
    _save(doc);
  }

  /// This profile goes with all its files once it's closed: [boot] deletes
  /// it.
  void remove() {
    final id = _open;
    if (id == null) return;
    final doc = _load();
    doc['drop'] = [...(doc['drop'] as List? ?? const []), id];
    doc.remove('last');
    _save(doc);
  }

  /// The card's name and avatar (`local:` value), copied for the gate when
  /// they change.
  void mirror(String name, String? avatar) {
    final id = _open;
    if (id == null) return;
    final doc = _load();
    var changed = false;
    _edit(doc, id, (e) {
      final pic = avatar ?? '';
      changed = e['name'] != name || e['avatar'] != pic;
      e['name'] = name;
      e['avatar'] = pic;
      return true;
    });
    if (changed) _save(doc);
  }

  /// What the gate gave the open profile, for its first card: name and avatar
  /// (`local:` value, only if the file is still there).
  ({String name, String? avatar})? seed() {
    final e = _entry(_load(), _open);
    if (e == null) return null;
    final avatar = e['avatar'];
    final id = _open!;
    return (
      name: e['name'] as String? ?? '',
      avatar: avatar is String && _avatarPath(id, avatar) != null
          ? avatar
          : null,
    );
  }

  /// The open profile's folder name for downloads the user sees: its name,
  /// cleaned for a path, or its id with no name.
  String? get downloadFolder {
    final id = _open;
    if (id == null) return null;
    final name = (_entry(_load(), id)?['name'] as String? ?? '')
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '')
        .trim();
    // A dot alone or at the end makes a folder the system won't open.
    final clean = name.replaceAll(RegExp(r'\.+$'), '').trim();
    return clean.isEmpty ? id : clean;
  }

  static String _clip(String name) {
    final s = name.trim();
    return s.length <= kProfileNameMax ? s : s.substring(0, kProfileNameMax);
  }
}

bool isPin(String pin) => RegExp(r'^[0-9]{4}$').hasMatch(pin);

// ── The lock ──

Future<Map<String, dynamic>> _lockFor(String pin) async {
  final rnd = Random.secure();
  final salt = Uint8List.fromList([
    for (var i = 0; i < 16; i++) rnd.nextInt(256),
  ]);
  final hash = await Isolate.run(() => pbkdf2Sha256(pin, salt, _kRounds));
  return {
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'n': _kRounds,
  };
}

Future<bool> _fits(Object? lock, String pin) async {
  if (lock is! Map || lock.isEmpty) return true;
  try {
    final salt = base64Decode(lock['salt'] as String);
    final want = base64Decode(lock['hash'] as String);
    final n = (lock['n'] as num?)?.toInt() ?? _kRounds;
    final got = await Isolate.run(() => pbkdf2Sha256(pin, salt, n));
    // Every byte compared, right or wrong.
    if (got.length != want.length) return false;
    var diff = 0;
    for (var i = 0; i < got.length; i++) {
      diff |= got[i] ^ want[i];
    }
    return diff == 0;
  } catch (_) {
    return false;
  }
}

/// PBKDF2 with HMAC-SHA256, one 32-byte block: the same key the computer's
/// lock makes, so one profiles.json format serves both.
Uint8List pbkdf2Sha256(String pin, List<int> salt, int rounds) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < rounds; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}
