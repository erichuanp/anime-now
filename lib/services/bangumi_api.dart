import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'bangumi_hosts.dart';

const bangumiUserAgent = 'erichuanp/anime-now (https://github.com/erichuanp/anime-now)';

class BangumiException implements Exception {
  final String message;
  BangumiException(this.message);
  @override
  String toString() => 'Bangumi: $message';
}

class BgmSubject {
  final int id;
  final String name;
  final String nameCn;
  final String? date;
  final int eps;
  final int totalEpisodes;
  final String coverUrl;
  final String platform;

  BgmSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.date,
    required this.eps,
    required this.totalEpisodes,
    required this.coverUrl,
    required this.platform,
  });

  factory BgmSubject.fromJson(Map<String, dynamic> j) {
    final images = j['images'] as Map<String, dynamic>?;
    final date = (j['date'] as String?)?.trim();
    return BgmSubject(
      id: (j['id'] as num).toInt(),
      name: j['name'] as String? ?? '',
      nameCn: j['name_cn'] as String? ?? '',
      date: (date == null || date.isEmpty) ? null : date,
      eps: (j['eps'] as num?)?.toInt() ?? 0,
      totalEpisodes: (j['total_episodes'] as num?)?.toInt() ?? 0,
      coverUrl: BangumiHosts.instance.canonical(images?['large'] as String? ?? images?['common'] as String? ?? ''),
      platform: j['platform'] as String? ?? '',
    );
  }
}

class BgmSubjectDetail {
  final BgmSubject subject;
  final List<String> aliases;
  final String? broadcastWeekday; // e.g. 星期四
  final String? tvStations;

  BgmSubjectDetail({
    required this.subject,
    required this.aliases,
    this.broadcastWeekday,
    this.tvStations,
  });

  /// First alias that looks like Latin script (romaji / English title).
  String? get latinAlias {
    for (final a in aliases) {
      if (RegExp(r'^[\x00-\x7F]+$').hasMatch(a)) return a;
    }
    return null;
  }

  /// Bangumi 放送星期 mapped to 1..7, if present.
  int? get weekdayNumber {
    final w = broadcastWeekday;
    if (w == null) return null;
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
    for (final e in map.entries) {
      if (w.contains('星期${e.key}') || w.contains('周${e.key}')) return e.value;
    }
    const jp = {'月': 1, '火': 2, '水': 3, '木': 4, '金': 5, '土': 6, '日': 7};
    for (final e in jp.entries) {
      if (w.contains('${e.key}曜')) return e.value;
    }
    return null;
  }
}

class BgmEpisodes {
  final String? firstAirDate;
  final String? lastAirDate;
  final int count;
  BgmEpisodes({this.firstAirDate, this.lastAirDate, required this.count});
}

class BangumiApi {
  BangumiApi({http.Client? client, BangumiHosts? hosts})
      : _client = client ?? LoggingClient(tag: 'http.bangumi'),
        _hosts = hosts ?? BangumiHosts.instance;

  static final _log = AppLog.instance;

  final http.Client _client;
  final BangumiHosts _hosts;
  int calls = 0;

  /// The 番时 mirror queues requests globally (one every 3 s, up to 20
  /// waiting), so a queued request can legitimately take a minute.
  Duration get _timeout =>
      _hosts.source == BangumiSource.mirror ? const Duration(seconds: 75) : const Duration(seconds: 20);

  Future<http.Response> _get(String pathAndQuery) {
    calls++;
    return _client.get(_hosts.api(pathAndQuery), headers: _headers).timeout(_timeout);
  }

  Future<http.Response> _post(String pathAndQuery, Object body) {
    calls++;
    return _client.post(_hosts.api(pathAndQuery), headers: _headers, body: jsonEncode(body)).timeout(_timeout);
  }

  /// Throws for non-200 responses. The 番时 mirror answers 503 with
  /// `{"error":"mirror_busy"}` when its queue is full; that becomes the
  /// well-known message 'mirror_busy' so the UI can localise it.
  void _check(http.Response res, String what) {
    if (res.statusCode == 200) return;
    if (res.statusCode == 503 && utf8.decode(res.bodyBytes, allowMalformed: true).contains('mirror_busy')) {
      throw BangumiException('mirror_busy');
    }
    throw BangumiException('$what HTTP ${res.statusCode}');
  }

  Map<String, String> get _headers => {
        'User-Agent': bangumiUserAgent,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<List<BgmSubject>> search(String keyword, {int limit = 10}) async {
    final res = await _post('/v0/search/subjects?limit=$limit', {
      'keyword': keyword,
      'sort': 'match',
      'filter': {
        'type': [2],
      },
    });
    _check(res, 'search');
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = body['data'] as List<dynamic>? ?? [];
    final list = data.map((e) => BgmSubject.fromJson(e as Map<String, dynamic>)).toList();
    _log.d('bangumi', 'search "$keyword" → ${body['total']} total, ${list.length} returned:\n'
        '${list.map((s) => '  #${s.id} ${s.date ?? '????-??-??'} eps=${s.eps}/${s.totalEpisodes} ${s.name} / ${s.nameCn}').join('\n')}');
    return list;
  }

  Future<BgmSubjectDetail> subject(int id) async {
    final res = await _get('/v0/subjects/$id');
    _check(res, 'subject');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final subject = BgmSubject.fromJson(j);
    final infobox = j['infobox'] as List<dynamic>? ?? [];
    final aliases = <String>[];
    String? weekday, stations;
    for (final item in infobox) {
      final m = item as Map<String, dynamic>;
      final key = m['key'] as String? ?? '';
      final value = m['value'];
      String? asText() => value is String ? value : null;
      switch (key) {
        case '别名':
          if (value is List) {
            for (final v in value) {
              final s = (v as Map<String, dynamic>)['v'] as String?;
              if (s != null && s.trim().isNotEmpty) aliases.add(s.trim());
            }
          } else if (value is String && value.trim().isNotEmpty) {
            aliases.add(value.trim());
          }
        case '放送星期':
          weekday = asText();
        case '播放电视台':
          stations = asText();
      }
    }
    _log.d('bangumi', 'subject #$id: ${subject.name} / ${subject.nameCn} date=${subject.date} eps=${subject.totalEpisodes}\n'
        '  aliases=$aliases\n  放送星期=$weekday 播放电视台=$stations');
    return BgmSubjectDetail(
      subject: subject,
      aliases: aliases,
      broadcastWeekday: weekday,
      tvStations: stations,
    );
  }

  /// Anime the user is watching (type 3) and wishes to watch (type 1).
  /// Public collections only; 404 = unknown user.
  Future<List<BgmSubject>> userCollections(String username, {List<int> types = const [3, 1]}) async {
    final seen = <int>{};
    final out = <BgmSubject>[];
    for (final type in types) {
      var offset = 0;
      while (true) {
        final res = await _get('/v0/users/${Uri.encodeComponent(username)}/collections'
            '?subject_type=2&type=$type&limit=50&offset=$offset');
        if (res.statusCode == 404) throw BangumiException('user_not_found');
        _check(res, 'collections');
        final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final data = j['data'] as List<dynamic>? ?? [];
        for (final item in data) {
          final subj = (item as Map<String, dynamic>)['subject'];
          if (subj is! Map<String, dynamic>) continue;
          final s = BgmSubject.fromJson(subj);
          if (seen.add(s.id)) out.add(s);
        }
        final total = (j['total'] as num?)?.toInt() ?? 0;
        offset += data.length;
        if (data.isEmpty || offset >= total) break;
      }
    }
    _log.d('bangumi', 'collections of "$username" (types $types): ${out.length} unique subjects\n'
        '${out.map((s) => '  #${s.id} ${s.date ?? '????-??-??'} eps=${s.eps} ${s.nameCn.isNotEmpty ? s.nameCn : s.name}').join('\n')}');
    return out;
  }

  Future<BgmEpisodes> episodes(int subjectId) async {
    final res = await _get('/v0/episodes?subject_id=$subjectId&type=0&limit=200');
    _check(res, 'episodes');
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final data = j['data'] as List<dynamic>? ?? [];
    final dates = <String>[];
    for (final e in data) {
      final d = ((e as Map<String, dynamic>)['airdate'] as String? ?? '').trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) dates.add(d);
    }
    dates.sort();
    _log.d('bangumi', 'episodes #$subjectId: ${data.length} eps, first=${dates.isEmpty ? null : dates.first} last=${dates.isEmpty ? null : dates.last}');
    return BgmEpisodes(
      firstAirDate: dates.isEmpty ? null : dates.first,
      lastAirDate: dates.isEmpty ? null : dates.last,
      count: data.length,
    );
  }
}
