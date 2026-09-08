import 'dart:io';

import '../services/app_log.dart';
import 'host.dart';

/// A value that stays the same for the life of one machine and differs between
/// machines: `ANDROID_ID` on Android, the hardware `IOPlatformUUID` on macOS,
/// `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid` on Windows.
///
/// Only used as HKDF salt for [KeyVault], so the guarantee we need is "stable
/// on this device, useless on another one". A factory reset (Android), a wiped
/// SMC (macOS) or a reinstalled Windows changes it and the stored API keys stop
/// decrypting, which is the intended behaviour.
Future<String> deviceFingerprint() async {
  String id = '';
  try {
    id = await hostChannel.invokeMethod<String>('deviceId') ?? '';
  } catch (e) {
    AppLog.instance.w('device', 'deviceId channel failed: $e');
  }
  if (id.isEmpty) {
    // Never fall back to a constant: that would make one key work everywhere.
    id = 'fallback:${Platform.operatingSystem}:${Platform.localHostname}';
    AppLog.instance.w('device', 'no platform id, using $id');
  }
  return id;
}
