import 'package:anime_now/services/bangumi_api.dart';
import 'package:anime_now/services/bangumi_hosts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const lain = 'https://lain.bgm.tv/pic/cover/l/13/c5/400602_ZI8Y9.jpg';

  test('mirror urls are stored canonically and displayed per active host', () {
    final h = BangumiHosts()..configure(source: BangumiSource.mirror, customApi: '', customImage: '');
    expect(h.canonical('https://bgmimg.erichuanp.com/pic/cover/l/13/c5/400602_ZI8Y9.jpg'), lain);
    expect(h.canonical(lain), lain);
    expect(h.display(lain), 'https://bgmimg.erichuanp.com/r/400/pic/cover/l/13/c5/400602_ZI8Y9.jpg');
    expect(h.canonical('https://bgmimg.erichuanp.com/r/400/pic/cover/l/13/c5/400602_ZI8Y9.jpg'), lain);
    expect(h.canonical('https://lain.bgm.tv/r/200/pic/cover/l/13/c5/400602_ZI8Y9.jpg'), lain);
    expect(h.api('/v0/subjects/1').toString(), 'https://bgmapi.erichuanp.com/v0/subjects/1');
    h.configure(source: BangumiSource.official, customApi: '', customImage: '');
    expect(h.display(lain), 'https://lain.bgm.tv/r/400/pic/cover/l/13/c5/400602_ZI8Y9.jpg');
    expect(h.api('/v0/subjects/1').toString(), 'https://api.bgm.tv/v0/subjects/1');
  });

  test('custom: trailing slash trimmed, scheme added, empty image host keeps lain, empty api falls back to official', () {
    final h = BangumiHosts()..configure(source: BangumiSource.custom, customApi: 'a.example.com/', customImage: 'https://i.example.com/');
    expect(h.active.api, 'https://a.example.com');
    expect(h.display('https://lain.bgm.tv/x.jpg'), 'https://i.example.com/x.jpg');
    expect(h.canonical('https://i.example.com/x.jpg'), 'https://lain.bgm.tv/x.jpg');
    h.configure(source: BangumiSource.custom, customApi: 'https://a.example.com', customImage: '');
    expect(h.display('https://lain.bgm.tv/x.jpg'), 'https://lain.bgm.tv/x.jpg');
    h.configure(source: BangumiSource.custom, customApi: '', customImage: '');
    expect(h.active.id, 'official');
  });

  test('BangumiApi requests go to the active host and covers come back canonical', () async {
    final h = BangumiHosts()..configure(source: BangumiSource.mirror, customApi: '', customImage: '');
    final seen = <String>[];
    final api = BangumiApi(
      hosts: h,
      client: MockClient((req) async {
        seen.add(req.url.toString());
        return http.Response(
          '{"id":1,"name":"x","name_cn":"y","date":"2026-07-02","eps":12,"total_episodes":12,'
          '"images":{"large":"https://bgmimg.erichuanp.com/pic/cover/l/1.jpg"},"platform":"TV","infobox":[]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final d = await api.subject(1);
    expect(seen, ['https://bgmapi.erichuanp.com/v0/subjects/1']);
    expect(d.subject.coverUrl, 'https://lain.bgm.tv/pic/cover/l/1.jpg');
    expect(h.display(d.subject.coverUrl), 'https://bgmimg.erichuanp.com/r/400/pic/cover/l/1.jpg');
  });

  test('mirror 503 mirror_busy becomes BangumiException(mirror_busy)', () async {
    final h = BangumiHosts()..configure(source: BangumiSource.mirror, customApi: '', customImage: '');
    final api = BangumiApi(
      hosts: h,
      client: MockClient((req) async => http.Response(
            '{"error":"mirror_busy","description":"镜像站暂时不可用，请在几分钟后尝试"}',
            503,
            headers: {'content-type': 'application/json', 'retry-after': '120'},
          )),
    );
    await expectLater(api.subject(1), throwsA(isA<BangumiException>().having((e) => e.message, 'message', 'mirror_busy')));
    await expectLater(api.search('x'), throwsA(isA<BangumiException>().having((e) => e.message, 'message', 'mirror_busy')));
    await expectLater(api.episodes(1), throwsA(isA<BangumiException>().having((e) => e.message, 'message', 'mirror_busy')));
    await expectLater(api.userCollections('u'), throwsA(isA<BangumiException>().having((e) => e.message, 'message', 'mirror_busy')));
  });

  test('other non-200 keeps the HTTP status message', () async {
    final api = BangumiApi(hosts: BangumiHosts(), client: MockClient((req) async => http.Response('nope', 500)));
    await expectLater(api.subject(1), throwsA(isA<BangumiException>().having((e) => e.message, 'message', 'subject HTTP 500')));
  });
}
