import '../models/anime.dart';
import '../util/time_utils.dart';
import 'app_log.dart';
import 'bangumi_api.dart';
import 'llm_client.dart';
import 'tavily_api.dart';

/// One bangumi subject with its airing status.
class Candidate {
  final BgmSubject subject;
  final BgmEpisodes episodes;
  final bool airing; // false => upcoming
  Candidate({required this.subject, required this.episodes, required this.airing});
}

class CallStats {
  int bangumi = 0;
  int tavily = 0;
  int llm = 0;
  @override
  String toString() => 'Bangumi ×$bangumi · Tavily ×$tavily · LLM ×$llm';
}

class PipelineResult {
  final AnimeEntry? entry;
  final List<Candidate>? choices;
  final String? error;
  final CallStats stats;
  final List<String> log;
  final Duration elapsed;

  /// Name and bangumi id of the show when [error] is 'already_added'.
  final String? alreadyName;
  final int? alreadyId;
  PipelineResult({
    this.entry,
    this.choices,
    this.error,
    required this.stats,
    required this.log,
    this.elapsed = Duration.zero,
    this.alreadyName,
    this.alreadyId,
  });
}

class PipelineAbort implements Exception {
  final String message;
  PipelineAbort(this.message);
  @override
  String toString() => message;
}

/// keyword -> bangumi -> (tavily -> llm)* -> AnimeEntry
class SearchPipeline {
  SearchPipeline({
    required this.bangumi,
    required this.tavily,
    required this.llm,
    this.onProgress,
    this.isAlreadyAdded,
  });

  final BangumiApi bangumi;
  final TavilyApi tavily;
  final LlmClient llm;
  final void Function(String step)? onProgress;

  /// When set, a picked show that is already on the schedule stops the
  /// pipeline before any Tavily/LLM call (error 'already_added').
  final bool Function(int subjectId)? isAlreadyAdded;

  final Map<String, List<Candidate>> _candidateCache = {};
  static final _log = AppLog.instance;

  Future<PipelineResult> run(String keyword, {int? chosenId}) async {
    final stats = CallStats();
    final log = <String>[];
    void step(String s) {
      log.add(s);
      _log.d('pipeline', s);
      onProgress?.call(s);
    }

    _log.i('pipeline', 'run keyword="$keyword" chosenId=$chosenId');

    final b0 = bangumi.calls, t0 = tavily.calls, l0 = llm.calls;
    final sw = Stopwatch()..start();
    void snap() {
      stats.bangumi = bangumi.calls - b0;
      stats.tavily = tavily.calls - t0;
      stats.llm = llm.calls - l0;
    }

    try {
      final candidates = await _findCandidates(keyword, step);
      snap();
      Candidate? pick;
      _log.d('pipeline', 'candidates for "$keyword": ${candidates.map((c) => '#${c.subject.id} ${c.airing ? 'airing' : 'upcoming'} ${c.subject.nameCn.isNotEmpty ? c.subject.nameCn : c.subject.name} first=${c.episodes.firstAirDate} last=${c.episodes.lastAirDate}').toList()}');
      if (chosenId != null) {
        pick = candidates.where((c) => c.subject.id == chosenId).firstOrNull;
        _log.d('pipeline', 'user chose #$chosenId → ${pick == null ? 'NOT in candidate list' : 'ok'}');
      } else {
        final airing = candidates.where((c) => c.airing).toList();
        final upcoming = candidates.where((c) => !c.airing).toList();
        if (airing.length == 1) {
          pick = airing.first;
        } else if (airing.length > 1) {
          _log.i('pipeline', '${airing.length} airing candidates → asking user');
          return PipelineResult(choices: airing, stats: stats, log: log, elapsed: sw.elapsed);
        } else if (upcoming.length == 1) {
          pick = upcoming.first;
        } else if (upcoming.length > 1) {
          _log.i('pipeline', '${upcoming.length} upcoming candidates → asking user');
          return PipelineResult(choices: upcoming, stats: stats, log: log, elapsed: sw.elapsed);
        }
      }
      if (pick == null) {
        _log.w('pipeline', 'no airing/upcoming candidate for "$keyword" ($stats)');
        return PipelineResult(error: 'not_found', stats: stats, log: log, elapsed: sw.elapsed);
      }
      _log.i('pipeline', 'picked #${pick.subject.id} ${pick.subject.name} (${pick.airing ? 'airing' : 'upcoming'})');
      if (isAlreadyAdded?.call(pick.subject.id) ?? false) {
        final name = pick.subject.nameCn.isNotEmpty ? pick.subject.nameCn : pick.subject.name;
        _log.i('pipeline', '#${pick.subject.id} $name already on the schedule → stop before Tavily/LLM');
        return PipelineResult(error: 'already_added', alreadyName: name, alreadyId: pick.subject.id, stats: stats, log: log, elapsed: sw.elapsed);
      }

      step('Bangumi: subject ${pick.subject.id}');
      final detail = await bangumi.subject(pick.subject.id);
      snap();
      final entry = await _resolveBroadcasts(pick, detail, step);
      snap();
      _log.i('pipeline', 'done "$keyword" → #${entry.id} ${entry.displayName}, ${entry.broadcasts.length} broadcasts ($stats)');
      _log.d('pipeline', 'final entry JSON:\n${AppLog.prettyJson(_encode(entry))}\n'
          'local slots:\n${entry.broadcasts.map((b) {
        final slot = toLocalSlot(b);
        return '  ${b.platform}: src wd=${b.weekday} ${b.hour}:${b.minute.toString().padLeft(2, '0')} ${b.timezone} first=${b.firstAirDate} → local wd=${slot.weekday} ${slot.timeLabel} first=${slot.firstAirLocal}';
      }).join('\n')}');
      return PipelineResult(entry: entry, stats: stats, log: log, elapsed: sw.elapsed);
    } on PipelineAbort catch (e) {
      snap();
      _log.w('pipeline', 'aborted "$keyword": ${e.message} ($stats)');
      return PipelineResult(error: e.message, stats: stats, log: log, elapsed: sw.elapsed);
    } catch (e, st) {
      snap();
      _log.e('pipeline', 'failed "$keyword" ($stats)', e, st);
      return PipelineResult(error: e.toString(), stats: stats, log: log, elapsed: sw.elapsed);
    }
  }

  /// Runs the pipeline for a known bangumi subject (e.g. from a user's
  /// collection list), skipping the keyword search. Ended shows return the
  /// error 'ended'; the caller filters those out.
  Future<PipelineResult> runSubject(BgmSubject subject) async {
    final stats = CallStats();
    final log = <String>[];
    void step(String s) {
      log.add(s);
      _log.d('pipeline', s);
      onProgress?.call(s);
    }

    final b0 = bangumi.calls, t0 = tavily.calls, l0 = llm.calls;
    final sw = Stopwatch()..start();
    void snap() {
      stats.bangumi = bangumi.calls - b0;
      stats.tavily = tavily.calls - t0;
      stats.llm = llm.calls - l0;
    }

    final label = subject.nameCn.isNotEmpty ? subject.nameCn : subject.name;
    _log.i('pipeline', 'runSubject #${subject.id} $label');
    try {
      step('Bangumi: episodes ${subject.id}');
      final cand = await _classifyOne(subject, _today());
      snap();
      if (cand == null) {
        _log.i('pipeline', '#${subject.id} $label is ended → skipped');
        return PipelineResult(error: 'ended', stats: stats, log: log, elapsed: sw.elapsed);
      }
      step('Bangumi: subject ${subject.id}');
      final detail = await bangumi.subject(subject.id);
      snap();
      final entry = await _resolveBroadcasts(cand, detail, step);
      snap();
      _log.i('pipeline', 'done #${entry.id} ${entry.displayName}, ${entry.broadcasts.length} broadcasts ($stats)');
      return PipelineResult(entry: entry, stats: stats, log: log, elapsed: sw.elapsed);
    } on PipelineAbort catch (e) {
      snap();
      return PipelineResult(error: e.message, stats: stats, log: log, elapsed: sw.elapsed);
    } catch (e, st) {
      snap();
      _log.e('pipeline', 'runSubject failed #${subject.id} ($stats)', e, st);
      return PipelineResult(error: e.toString(), stats: stats, log: log, elapsed: sw.elapsed);
    }
  }

  /// Cheap date pre-filter used before spending an episodes call.
  static bool plausiblyCurrent(BgmSubject s) {
    if (s.date == null) return true; // unknown date: let the episodes call decide
    final d = DateTime.tryParse(s.date!);
    if (d == null) return false;
    return d.isAfter(_today().subtract(const Duration(days: 270)));
  }

  // ---------------------------------------------------------------- candidates

  Future<List<Candidate>> _findCandidates(String keyword, void Function(String) step) async {
    final cached = _candidateCache[keyword];
    if (cached != null) {
      _log.d('pipeline', 'candidate cache hit for "$keyword" (${cached.length})');
      return cached;
    }

    step('Bangumi: search "$keyword"');
    var subjects = await bangumi.search(keyword, limit: 10);
    var cands = await _classify(subjects, step);

    if (cands.isEmpty) {
      step('LLM: expanding keyword');
      final suggestions = await _suggestKeywords(keyword);
      _log.d('pipeline', 'LLM keyword suggestions for "$keyword": $suggestions');
      for (final kw in suggestions.take(3)) {
        if (kw.trim().isEmpty || kw.trim() == keyword.trim()) continue;
        step('Bangumi: search "$kw"');
        subjects = await bangumi.search(kw, limit: 10);
        cands = await _classify(subjects, step);
        if (cands.isNotEmpty) break;
      }
    }
    _candidateCache[keyword] = cands;
    return cands;
  }

  Future<List<Candidate>> _classify(List<BgmSubject> subjects, void Function(String) step) async {
    final today = _today();
    final plausible = subjects.where((s) {
      final d = s.date == null ? null : DateTime.tryParse(s.date!);
      if (d == null) return false;
      // Started within the last ~9 months or not started yet.
      return d.isAfter(today.subtract(const Duration(days: 270)));
    }).toList()
      ..sort((a, b) => b.date!.compareTo(a.date!));

    _log.d('pipeline', 'classify: ${subjects.length} subjects, ${plausible.length} plausible (date > ${_fmt(today.subtract(const Duration(days: 270)))}): '
        '${plausible.map((s) => '#${s.id}@${s.date}').toList()}; checking first ${plausible.length.clamp(0, 4)}');
    final out = <Candidate>[];
    for (final s in plausible.take(4)) {
      step('Bangumi: episodes ${s.id}');
      final c = await _classifyOne(s, today);
      if (c != null) out.add(c);
    }
    return out;
  }

  /// Episodes call + airing/upcoming/ended decision for one subject.
  /// Returns null when the show has ended (or has no usable dates).
  Future<Candidate?> _classifyOne(BgmSubject s, DateTime today) async {
    final eps = await bangumi.episodes(s.id);
    final first = DateTime.tryParse(eps.firstAirDate ?? s.date ?? '');
    final last = eps.lastAirDate == null ? null : DateTime.tryParse(eps.lastAirDate!);
    if (first == null) {
      _log.d('pipeline', '  #${s.id}: no first air date → skip');
      return null;
    }
    if (first.isAfter(today)) {
      _log.d('pipeline', '  #${s.id}: first=$first > today → UPCOMING');
      return Candidate(subject: s, episodes: eps, airing: false);
    }
    if (last != null && !last.isBefore(today)) {
      _log.d('pipeline', '  #${s.id}: first=$first last=$last >= today → AIRING');
      return Candidate(subject: s, episodes: eps, airing: true);
    }
    if (last == null && first.isAfter(today.subtract(const Duration(days: 200)))) {
      _log.d('pipeline', '  #${s.id}: last unknown, first=$first within 200 days → assume AIRING');
      return Candidate(subject: s, episodes: eps, airing: true);
    }
    _log.d('pipeline', '  #${s.id}: first=$first last=$last → ENDED, skip');
    return null;
  }

  Future<List<String>> _suggestKeywords(String keyword) async {
    const system = 'You help map a user\'s rough anime keyword to search terms that will match the '
        'official title in the Bangumi (bgm.tv) database. Reply with JSON only.';
    final user = 'Today is ${_fmt(_today())}. The user typed: "$keyword".\n'
        'Guess which currently-airing (or about-to-air) TV anime they mean. Return up to 3 alternative '
        'search keywords, preferring the official Japanese title, then the Simplified Chinese title, then '
        'a shorter distinctive fragment. JSON format: {"keywords": ["...", "..."]}';
    final text = await llm.complete(system: system, user: user, maxTokens: 4096);
    final j = LlmClient.parseJsonObject(text);
    final list = j['keywords'];
    if (list is! List) return const [];
    return list.whereType<String>().toList();
  }

  // ---------------------------------------------------------------- broadcasts

  Future<AnimeEntry> _resolveBroadcasts(
    Candidate pick,
    BgmSubjectDetail detail,
    void Function(String) step,
  ) async {
    final s = detail.subject;
    final ja = s.name;
    final cn = s.nameCn.isNotEmpty ? s.nameCn : (detail.aliases.firstOrNull ?? '');
    final en = detail.latinAlias;

    final hints = StringBuffer()
      ..writeln('Japanese title: $ja')
      ..writeln('Chinese title: $cn')
      ..writeln('Other aliases: ${detail.aliases.join(' / ')}')
      ..writeln('Bangumi first air date: ${pick.episodes.firstAirDate ?? s.date ?? 'unknown'}')
      ..writeln('Bangumi 放送星期: ${detail.broadcastWeekday ?? 'unknown'}')
      ..writeln('Bangumi 播放电视台: ${detail.tvStations ?? 'unknown'}')
      ..writeln('Episodes: ${s.totalEpisodes}');

    final queries = <(String, String)>[
      ('ja-jp', '$ja 放送時間 曜日'),
      ('en-us', '${en ?? ja} anime broadcast schedule time'),
      if (cn.isNotEmpty) ('zh-tw', '$cn 播出時間 每週 動畫'),
      if (cn.isNotEmpty) ('zh-hk', '$cn 播放時間 香港 動畫'),
      if (cn.isNotEmpty) ('zh-cn', '$cn 放送时间 每周 动画'),
    ];

    final gathered = <TavilyHit>[];
    final answers = <String>[];
    List<Broadcast> broadcasts = const [];
    var complete = false;
    Map<String, String> titles = const {};

    for (final (lang, q) in queries) {
      step('Tavily [$lang]: $q');
      final r = await tavily.search(q);
      if (r.answer != null && r.answer!.trim().isNotEmpty) answers.add(r.answer!.trim());
      gathered.addAll(r.results);
      step('LLM: extracting schedule ($lang)');
      final parsed = await _extract(hints.toString(), gathered, answers);
      broadcasts = parsed.$1;
      complete = parsed.$2;
      if (parsed.$3.isNotEmpty) titles = parsed.$3;
      _log.d('pipeline', 'round $lang: ${gathered.length} snippets gathered, complete=$complete, '
          'broadcasts=${broadcasts.map((b) => '${b.platform} wd${b.weekday} ${b.hour}:${b.minute.toString().padLeft(2, '0')} ${b.timezone} first=${b.firstAirDate}').toList()}');
      if (complete) break;
    }

    if (broadcasts.isEmpty) {
      // Fall back to what bangumi knows: weekday only, JST.
      final w = detail.weekdayNumber;
      _log.w('pipeline', 'no broadcast extracted after ${queries.length} rounds; bangumi weekday=$w');
      if (w != null) {
        broadcasts = [
          Broadcast.normalised(
            platform: detail.tvStations ?? 'TV',
            weekday: w,
            hour: -1,
            minute: 0,
            timezone: 'Asia/Tokyo',
            firstAirDate: pick.episodes.firstAirDate ?? s.date,
          ),
        ];
      } else {
        throw PipelineAbort('no_schedule');
      }
    }

    String? nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    return AnimeEntry(
      id: s.id,
      nameCn: cn.isNotEmpty ? cn : (nonEmpty(titles['zh_hans']) ?? ''),
      nameJp: ja,
      nameEn: nonEmpty(titles['en']) ?? en,
      nameZhHant: nonEmpty(titles['zh_hant']),
      coverUrl: s.coverUrl,
      firstAirDate: pick.episodes.firstAirDate ?? s.date,
      lastAirDate: pick.episodes.lastAirDate,
      totalEpisodes: s.totalEpisodes,
      broadcasts: broadcasts,
      addedAt: DateTime.now(),
    );
  }

  Future<(List<Broadcast>, bool, Map<String, String>)> _extract(String hints, List<TavilyHit> hits, List<String> answers) async {
    const system = '''
You extract TV anime broadcast schedules from web search snippets and return strict JSON.

Output format (JSON only, no prose):
{
  "complete": true|false,
  "titles": {
    "en": "official English title (as used by Crunchyroll/Netflix etc.), else romaji",
    "zh_hans": "简体中文标题 (use the Bangumi Chinese title from the known facts if given)",
    "zh_hant": "繁體中文標題",
    "zh_hant_source": "official" | "transcoded"
  },
  "broadcasts": [
    {
      "platform": "MBS",              // TV station or streaming service, as named in the source
      "weekday": 4,                   // 1=Monday ... 7=Sunday, EXACTLY as written in the source
      "time": "25:00",                // HH:MM exactly as written; keep 24+ hours (e.g. 25:30) as-is, do not convert
      "timezone": "Asia/Tokyo",       // IANA zone of that platform (Japanese TV = Asia/Tokyo)
      "first_air_date": "2026-07-02", // yyyy-MM-dd of the first episode on this platform, or null
      "note": ""                      // optional, e.g. "先行放送"
    }
  ]
}

Title rules:
- zh_hant must be the OFFICIAL Traditional Chinese release title used in Taiwan / Hong Kong (巴哈姆特動畫瘋, 木棉花, 羚邦, 曼迪, Netflix TW, Ani-One), which often differs in wording from the Simplified title (e.g. 間諜家家酒 vs 间谍过家家, 我的英雄學院, 葬送的芙莉蓮). Use your knowledge of these releases; set zh_hant_source to "official".
- Only if you genuinely do not know the official title, convert zh_hans character-by-character to Traditional and set zh_hant_source to "transcoded".
- zh_hans: use the Bangumi Chinese title from the known facts when given.
- en: the official English title (Crunchyroll / Netflix / official site); romaji only as a last resort.

Rules:
- Only include a platform when the snippets state its weekday AND time. Never invent times.
- Japanese "毎週木曜 25:00" means weekday=4, time="25:00" (leave normalisation to the caller).
- If the same platform appears with conflicting times, prefer the official site or the most recent source.
- Global streaming (Crunchyroll, Netflix, ABEMA, dアニメ, bilibili, 巴哈姆特 etc.) counts as a platform.
- "complete" is true when at least one platform has weekday, time and first_air_date.
- Think briefly; the final answer must be only the JSON object.
''';
    final buf = StringBuffer()
      ..writeln('Today: ${_fmt(_today())}')
      ..writeln('## Known facts from Bangumi')
      ..writeln(hints)
      ..writeln('## Search engine answers')
      ..writeln(answers.isEmpty ? '(none)' : answers.join('\n---\n'))
      ..writeln('## Search snippets');
    for (var i = 0; i < hits.length; i++) {
      final h = hits[i];
      buf.writeln('[${i + 1}] ${h.title}\n${h.url}\n${h.content}\n');
    }
    final text = await llm.complete(system: system, user: buf.toString(), maxTokens: 16000);
    final j = LlmClient.parseJsonObject(text);
    final list = j['broadcasts'];
    final out = <Broadcast>[];
    if (list is List) {
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final platform = (item['platform'] as String? ?? '').trim();
        final weekday = _parseWeekday(item['weekday']);
        final time = _parseTime(item['time']);
        if (platform.isEmpty || weekday == null || time == null) {
          _log.d('pipeline', 'dropping broadcast item (platform/weekday/time unparsable): $item');
          continue;
        }
        final tzName = (item['timezone'] as String? ?? 'Asia/Tokyo').trim();
        final date = item['first_air_date'];
        out.add(Broadcast.normalised(
          platform: platform,
          weekday: weekday,
          hour: time.$1,
          minute: time.$2,
          timezone: tzName.isEmpty ? 'Asia/Tokyo' : tzName,
          firstAirDate: date is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ? date : null,
          note: (item['note'] as String?)?.trim(),
        ));
      }
    }
    final complete = j['complete'] == true && out.any((b) => b.firstAirDate != null);
    final titles = <String, String>{};
    final t = j['titles'];
    if (t is Map<String, dynamic>) {
      for (final k in const ['en', 'zh_hans', 'zh_hant', 'zh_hant_source']) {
        final v = t[k];
        if (v is String && v.trim().isNotEmpty) titles[k] = v.trim();
      }
      _log.d('pipeline', 'titles: $titles');
    }
    return (out, complete, titles);
  }

  static String _encode(AnimeEntry e) => AnimeEntry.encodeList([e]);

  static int? _parseWeekday(dynamic v) {
    if (v is num) {
      final n = v.toInt();
      return (n >= 1 && n <= 7) ? n : null;
    }
    if (v is String) {
      final s = v.trim().toLowerCase();
      final n = int.tryParse(s);
      if (n != null && n >= 1 && n <= 7) return n;
      const names = {
        'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
        '月': 1, '火': 2, '水': 3, '木': 4, '金': 5, '土': 6, '日': 7,
      };
      for (final e in names.entries) {
        if (s.startsWith(e.key)) return e.value;
      }
    }
    return null;
  }

  static (int, int)? _parseTime(dynamic v) {
    if (v is! String) return null;
    final m = RegExp(r'(\d{1,2})[:：時时](\d{2})?').firstMatch(v.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final min = int.tryParse(m.group(2) ?? '0') ?? 0;
    if (h == null || h < 0 || h > 47) return null;
    return (h, min);
  }

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
