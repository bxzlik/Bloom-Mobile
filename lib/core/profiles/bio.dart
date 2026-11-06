/// A fingerprint or face in place of a profile's PIN. Only the phone's own
/// biometrics: the phone's passcode doesn't stand in for the PIN, or anyone
/// who knows it would get in.
library;

import 'package:local_auth/local_auth.dart';

import '../log/bloom_log.dart';

final LocalAuthentication _auth = LocalAuthentication();

/// The phone can check a fingerprint or face, and has one enrolled.
Future<bool> bioAvailable() async {
  try {
    if (!await _auth.isDeviceSupported()) return false;
    return (await _auth.getAvailableBiometrics()).isNotEmpty;
  } catch (e) {
    logWarn('profiles', 'biometrics unavailable: $e');
    return false;
  }
}

/// Asks for it with [reason] under the system's prompt. False when it was
/// cancelled, failed or isn't there: the PIN is still the way in.
Future<bool> bioAsk(String reason) async {
  try {
    return await _auth.authenticate(
      localizedReason: reason,
      biometricOnly: true,
    );
  } on LocalAuthException catch (e) {
    logInfo('profiles', 'biometrics: ${e.code.name}');
    return false;
  } catch (e) {
    logWarn('profiles', 'biometrics failed: $e');
    return false;
  }
}
