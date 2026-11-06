/// Where the app keeps its files.
///
/// [appRootDir] is the app's own internal directory: `profiles.json` (who uses
/// this Bloom) and the log, shared by everyone. Each profile keeps the rest in
/// `<root>/profiles/<id>`, and [appPrivateDir] is the open profile's folder
/// (`bloom.json`, the database, covers, offline copies). Nothing else is
/// shared between profiles.
///
/// [appVisibleDir] is what the user downloaded and must find. On iOS that's
/// the profile's folder in Files; on Android downloads go to shared Music past
/// it (see `MediaStoreSaver`), so it's unused there.
///
/// Why the root differs per platform: on iOS Files shows ALL of `Documents`
/// with `UIFileSharingEnabled`, and the user could wipe internal files. So on
/// iOS they live in `Application Support`, which Files can't see. On Android
/// it stays `Documents`, private to the app.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

String? _profile;

/// The open profile's id; `null` before one opens (the gate).
String? get openProfileId => _profile;

/// Every file below goes to this profile's folder from now on. `null` is the
/// gate: nothing of a profile is open.
void setOpenProfile(String? id) => _profile = id;

/// The shared internal directory. Created if missing: `Application Support`
/// may not exist on a fresh iOS install, and the first write would silently go
/// nowhere.
Future<Directory> appRootDir() async {
  final dir = Platform.isIOS
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// A profile's folder, whether it's open or not.
String profileDirPath(String root, String id) => '$root/profiles/$id';

/// The open profile's internal directory: library, covers, offline copies.
Future<Directory> appPrivateDir() async {
  final root = await appRootDir();
  final id = _profile;
  if (id == null) {
    throw StateError('no profile is open');
  }
  final dir = Directory(profileDirPath(root.path, id));
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// The open profile's folder in system Files (iOS), named as the profile so
/// it's found there. [folder] is that name, ready for a path.
Future<Directory> appVisibleDir(String? folder) async {
  final docs = await getApplicationDocumentsDirectory();
  return folder == null || folder.isEmpty
      ? docs
      : Directory('${docs.path}/$folder');
}
