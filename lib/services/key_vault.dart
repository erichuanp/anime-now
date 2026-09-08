import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../platform/device_id.dart';
import 'app_log.dart';

/// Encrypts API keys before they touch config.json.
///
/// AES-256-GCM with a key derived (HKDF-SHA256) from a compiled-in app secret
/// and the machine's own id (see [deviceFingerprint]). That id survives
/// uninstall + reinstall, so the config still opens after a reinstall on the
/// same machine but cannot be decrypted on another one.
class KeyVault {
  KeyVault._();
  static final KeyVault instance = KeyVault._();

  static const _appSecret = 'anime-now::7f3c9b1e-4d2a-4c8e-9a6b-0f1e2d3c4b5a::v1';
  static const prefix = 'enc:v1:';

  final _cipher = AesGcm.with256bits();
  SecretKey? _key;

  Future<SecretKey> _deriveKey() async {
    final cached = _key;
    if (cached != null) return cached;
    final deviceId = await deviceFingerprint();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final k = await hkdf.deriveKey(
      secretKey: SecretKey(utf8.encode(_appSecret)),
      nonce: utf8.encode(deviceId),
      info: utf8.encode('anime-now-config-keys'),
    );
    _key = k;
    AppLog.instance.d('vault', 'key derived (device id len ${deviceId.length})');
    return k;
  }

  bool isEncrypted(String stored) => stored.startsWith(prefix);

  /// Returns `enc:v1:<base64(nonce|ciphertext|mac)>`; empty stays empty.
  Future<String> encrypt(String plain) async {
    if (plain.isEmpty) return '';
    final key = await _deriveKey();
    final box = await _cipher.encrypt(utf8.encode(plain), secretKey: key);
    return prefix + base64Encode(box.concatenation());
  }

  /// Decrypts a stored value. Legacy plaintext (no prefix) is returned as-is.
  Future<String> decrypt(String stored) async {
    if (stored.isEmpty) return '';
    if (!isEncrypted(stored)) return stored;
    try {
      final key = await _deriveKey();
      final bytes = base64Decode(stored.substring(prefix.length));
      final box = SecretBox.fromConcatenation(bytes, nonceLength: 12, macLength: 16);
      final clear = await _cipher.decrypt(box, secretKey: key);
      return utf8.decode(clear);
    } catch (e) {
      AppLog.instance.e('vault', 'decrypt failed (different device or corrupted value)', e);
      return '';
    }
  }
}
