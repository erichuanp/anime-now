@Tags(['live'])
library;

import 'package:anime_now/services/bangumi_api.dart';
import 'package:anime_now/services/bangumi_hosts.dart';
import 'package:anime_now/services/search_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bangumi search/subject/episodes parse real data', () async {
    final api = BangumiApi();
    final hits = await api.search('转生重骑士', limit: 5);
    expect(hits, isNotEmpty);
    final first = hits.first;
    expect(first.id, 511177);
    final detail = await api.subject(first.id);
    expect(detail.weekdayNumber, 4);
    expect(detail.latinAlias, isNotNull);
    final eps = await api.episodes(first.id);
    expect(eps.firstAirDate, '2026-07-02');
    expect(eps.lastAirDate, isNotNull);
    expect(api.calls, 3);
  });

  test('user collections: erichuanp watching + wish lists, ended filtered by date prefilter', () async {
    final api = BangumiApi();
    final subjects = await api.userCollections('erichuanp');
    expect(subjects.length, greaterThan(20));
    expect(subjects.map((s) => s.id).toSet().length, subjects.length); // deduped
    final recent = subjects.where(SearchPipeline.plausiblyCurrent).toList();
    expect(recent.length, lessThan(subjects.length));
    expect(recent.any((s) => s.id == 515594), isTrue); // slime S4, airing
    expect(recent.any((s) => s.id == 253), isFalse); // Cowboy Bebop 1998, out
    expect(() => api.userCollections('this-user-does-not-exist-xyz-123'), throwsA(isA<BangumiException>()));
  });

  test('mirror bgmapi.erichuanp.com serves the same data with canonical cover urls', () async {
    final hosts = BangumiHosts()..configure(source: BangumiSource.mirror, customApi: '', customImage: '');
    final api = BangumiApi(hosts: hosts);
    final hits = await api.search('转生重骑士', limit: 5);
    expect(hits.first.id, 511177);
    expect(hits.first.coverUrl, startsWith('https://lain.bgm.tv/'));
    expect(hosts.display(hits.first.coverUrl), startsWith('https://bgmimg.erichuanp.com/'));
    final detail = await api.subject(511177);
    expect(detail.weekdayNumber, 4);
    final eps = await api.episodes(511177);
    expect(eps.firstAirDate, '2026-07-02');
    final mine = await api.userCollections('erichuanp');
    expect(mine.length, greaterThan(20));
  });
}
