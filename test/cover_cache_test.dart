import 'dart:async';
import 'dart:io';

import 'package:anime_now/services/bangumi_hosts.dart';
import 'package:anime_now/services/cover_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('covers'));
  tearDown(() => dir.deleteSync(recursive: true));

  File fileFor(String key) => File('${dir.path}/${key.hashCode}.jpg')..writeAsStringSync(key);

  test('covers are fetched one at a time, in request order, via the active host as /r/400', () async {
    final fetched = <String>[];
    final gates = <String, Completer<void>>{};
    final hosts = BangumiHosts()..configure(source: BangumiSource.mirror, customApi: '', customImage: '');
    final cache = CoverCache(
      hosts: hosts,
      lookup: (_) async => null,
      fetch: (url, key) async {
        fetched.add(url);
        await (gates[key] = Completer<void>()).future;
        return fileFor(key);
      },
    );
    const a = 'https://lain.bgm.tv/pic/cover/l/a.jpg';
    const b = 'https://lain.bgm.tv/pic/cover/l/b.jpg';
    const c = 'https://lain.bgm.tv/pic/cover/l/c.jpg';
    cache.ensureAll([a, b, c]);
    cache.ensure(b); // duplicate: ignored
    await Future<void>.delayed(Duration.zero);
    expect(fetched, ['https://bgmimg.erichuanp.com/r/400/pic/cover/l/a.jpg']); // b, c wait
    expect(cache.current, a);
    gates[a]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(cache.fileFor(a), isNotNull);
    expect(fetched.length, 2);
    expect(fetched.last, endsWith('/b.jpg'));
    gates[b]!.complete();
    await Future<void>.delayed(Duration.zero);
    gates[c]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(fetched.length, 3);
    expect(cache.pending, 0);
    expect(cache.fileFor(c)!.readAsStringSync(), c);
  });

  test('a cover already on disk is used without any request', () async {
    var fetches = 0;
    final cache = CoverCache(
      hosts: BangumiHosts(),
      lookup: (key) async => key.endsWith('cached.jpg') ? fileFor(key) : null,
      fetch: (url, key) async {
        fetches++;
        return fileFor(key);
      },
    );
    cache.ensureAll(['https://lain.bgm.tv/pic/cover/l/cached.jpg', 'https://lain.bgm.tv/pic/cover/l/new.jpg']);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(fetches, 1);
    expect(cache.fileFor('https://lain.bgm.tv/pic/cover/l/cached.jpg'), isNotNull);
    expect(cache.fileFor('https://lain.bgm.tv/pic/cover/l/new.jpg'), isNotNull);
  });

  test('failures are remembered and retried on retryFailed', () async {
    var attempts = 0;
    final cache = CoverCache(
      hosts: BangumiHosts(),
      lookup: (_) async => null,
      fetch: (url, key) async {
        attempts++;
        if (attempts == 1) throw const SocketException('mirror busy');
        return fileFor(key);
      },
    );
    const u = 'https://lain.bgm.tv/pic/cover/l/x.jpg';
    cache.ensure(u);
    await Future<void>.delayed(Duration.zero);
    expect(cache.fileFor(u), isNull);
    cache.ensure(u); // still failed: no automatic re-fetch until asked
    cache.retryFailed();
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 2);
    expect(cache.fileFor(u), isNotNull);
  });
}
