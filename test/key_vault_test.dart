import 'package:anime_now/services/key_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypt/decrypt round-trips and never stores plaintext', () async {
    final v = KeyVault.instance;
    const plain = 'sk-super-secret-1234567890';
    final stored = await v.encrypt(plain);
    expect(stored, startsWith(KeyVault.prefix));
    expect(stored.contains('secret'), isFalse);
    expect(v.isEncrypted(stored), isTrue);
    expect(await v.decrypt(stored), plain);
    // Fresh nonce every time.
    expect(await v.encrypt(plain), isNot(stored));
  });

  test('legacy plaintext passes through, empty stays empty', () async {
    final v = KeyVault.instance;
    expect(await v.decrypt('tvly-legacy'), 'tvly-legacy');
    expect(await v.encrypt(''), '');
    expect(await v.decrypt(''), '');
  });

  test('corrupted ciphertext yields empty string, not a crash', () async {
    final v = KeyVault.instance;
    expect(await v.decrypt('${KeyVault.prefix}AAAA'), '');
  });
}
