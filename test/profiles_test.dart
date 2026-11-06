import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloom/core/profiles/profiles.dart';
import 'package:bloom/core/store/app_dirs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Profiles p;

  setUp(() {
    root = Directory.systemTemp.createTempSync('bloom_profiles_');
    p = Profiles.forTest(root.path);
    setOpenProfile(null);
  });

  tearDown(() {
    setOpenProfile(null);
    root.deleteSync(recursive: true);
  });

  Map<String, dynamic> doc() =>
      jsonDecode(File('${root.path}/profiles.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the PIN key is the one the computer makes', () {
    // Python: hashlib.pbkdf2_hmac('sha256', b'1234', bytes(range(16)), 100000)
    expect(
      base64Encode(pbkdf2Sha256('1234', List.generate(16, (i) => i), 100000)),
      'hp5sg1DFvrCsw5n7qsO2DSIEM4lrJqZHc00NjxWG4fo=',
    );
    expect(
      base64Encode(pbkdf2Sha256('0000', utf8.encode('saltsaltsaltsalt'), 1000)),
      'drO1S3hPQxR796cqiWSow2hBTW0lbjnzM/HZP6koX/U=',
    );
  });

  test('no profiles: the gate asks to create one', () {
    final s = p.boot();
    expect(s.gate, isTrue);
    expect(s.view, 'create');
  });

  test('an unlocked last profile opens straight away', () async {
    final id = await p.make('Dana', Uint8List.fromList([1, 2, 3]), null);
    expect(id, isNotNull);
    final s = p.boot();
    expect(s.gate, isFalse);
    expect(s.id, id);
    final e = p.find(id)!;
    expect(e.name, 'Dana');
    expect(e.avatar, isNotNull);
    expect(File(e.avatar!).existsSync(), isTrue);
  });

  test('a locked one asks its PIN; five wrong ones make a wait', () async {
    final id = (await p.make('A', null, '1234'))!;
    final s = p.boot();
    expect(s.view, 'pin');
    expect(s.id, id);
    expect(p.open(id), isFalse);

    for (var i = 0; i < 4; i++) {
      expect(await p.unlock(id, '0000'), -1);
    }
    expect(await p.unlock(id, '0000'), 30);
    expect(p.waitLeft(id), greaterThan(0));
    // Even the right one waits.
    expect(await p.unlock(id, '1234'), greaterThan(0));
  });

  test('the right PIN opens it and clears the misses', () async {
    final id = (await p.make('A', null, '1234'))!;
    expect(await p.unlock(id, '0000'), -1);
    expect(await p.unlock(id, '1234'), 0);
    final e = (doc()['list'] as List).first as Map;
    expect(e.containsKey('fails'), isFalse);
    expect(doc()['last'], id);
  });

  test(
    'signing out shows the list; deleting from inside drops the folder',
    () async {
      final a = (await p.make('A', null, null))!;
      await p.make('B', null, null);
      setOpenProfile(a);
      p.signOut();
      expect(p.boot().view, 'list');

      p.open(a);
      setOpenProfile(a);
      Directory(p.dirOf(a)).createSync(recursive: true);
      p.remove();
      setOpenProfile(null);
      final s = p.boot();
      expect(Directory(p.dirOf(a)).existsSync(), isFalse);
      expect(p.list().map((e) => e.name), ['B']);
      expect(s.view, 'list');
    },
  );

  test('setting, changing and removing the PIN of the open profile', () async {
    final id = (await p.make('A', null, null))!;
    setOpenProfile(id);
    expect(p.locked, isFalse);
    expect(await p.setPin(null, '1111'), isTrue);
    expect(p.locked, isTrue);
    expect(await p.setPin('2222', '3333'), isFalse);
    expect(await p.setPin('1111', '3333'), isTrue);
    p.setBio(true);
    expect(p.bioOn, isTrue);
    expect(await p.setPin('3333', null), isTrue);
    expect(p.locked, isFalse);
    // The fingerprint goes with the PIN it stood in for.
    expect(p.bioOn, isFalse);
  });

  test('forgetting a profile deletes it and its folder', () async {
    final id = (await p.make('A', null, '1234'))!;
    p.forget(id);
    expect(p.list(), isEmpty);
    expect(Directory(p.dirOf(id)).existsSync(), isFalse);
    expect(p.boot().view, 'create');
  });

  test(
    'the card mirrors into the list, and the folder name is clean',
    () async {
      final id = (await p.make('A', null, null))!;
      setOpenProfile(id);
      p.mirror('Ма/ша?', null);
      expect(p.find(id)!.name, 'Ма/ша?');
      expect(p.downloadFolder, 'Маша');
      p.mirror('', null);
      expect(p.downloadFolder, id);
    },
  );
}
