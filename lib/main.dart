import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/session.dart';
import 'core/log/bloom_log.dart';
import 'core/profiles/profiles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only: the layout is built for a narrow screen and falls apart in
  // landscape. Android's manifest says the same; this is for iOS and in case
  // the system hands the activity over sideways.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // The log opens first, so it catches what happens to the other stores.
  await BloomLog.instance.open();
  _catchUnhandled();
  logInfo('app', 'start · ${Platform.operatingSystemVersion}');
  // Who uses this Bloom, before anything touches a profile's files.
  await Profiles.init();
  await enterBloom();
}

/// Unhandled errors go to the log. Two doors: `FlutterError.onError` for the
/// widget tree, `PlatformDispatcher.onError` for the rest (dropped `Future`s).
/// Default behaviour stays: errors still print to the console.
void _catchUnhandled() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('flutter', details.exceptionAsString(), details.stack?.toString());
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('dart', '$error', stack);
    return false; // false lets the platform handle it as usual
  };
}
