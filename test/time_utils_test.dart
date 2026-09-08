import 'dart:convert';

import 'package:anime_now/models/anime.dart';
import 'package:anime_now/services/llm_client.dart';
import 'package:anime_now/util/time_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(() => tzdata.initializeTimeZones());
  _nextOccurrencesTests();

  test('25:00 on Tuesday normalises to Wednesday 01:00', () {
    final b = Broadcast.normalised(
      platform: 'MBS',
      weekday: 2,
      hour: 25,
      minute: 0,
      timezone: 'Asia/Tokyo',
      firstAirDate: '2026-07-07',
    );
    expect(b.weekday, 3);
    expect(b.hour, 1);
    expect(b.firstAirDate, '2026-07-08');
  });

  test('Sunday 24:30 wraps to Monday', () {
    final b = Broadcast.normalised(platform: 'x', weekday: 7, hour: 24, minute: 30, timezone: 'Asia/Tokyo');
    expect(b.weekday, 1);
    expect(b.hour, 0);
    expect(b.minute, 30);
  });

  test('JST slot converts to the local zone consistently', () {
    final b = Broadcast.normalised(platform: 'MBS', weekday: 4, hour: 25, minute: 0, timezone: 'Asia/Tokyo');
    final slot = toLocalSlot(b);
    // Friday 01:00 JST == Thursday 16:00 UTC. Local weekday must be Thu or Fri
    // depending on the host offset, and the instant must match.
    final loc = tz.getLocation('Asia/Tokyo');
    final now = tz.TZDateTime.now(loc);
    var d = tz.TZDateTime(loc, now.year, now.month, now.day, 1, 0);
    while (d.weekday != 5) {
      d = tz.TZDateTime(loc, d.year, d.month, d.day + 1, 1, 0);
    }
    final local = DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch).toLocal();
    expect(slot.weekday, local.weekday);
    expect(slot.hour, local.hour);
    expect(slot.minute, 0);
  });

  test('broadcasts are ordered earliest first', () {
    final entry = AnimeEntry(
      id: 1,
      nameCn: 'a',
      nameJp: 'a',
      coverUrl: '',
      firstAirDate: '2026-07-02',
      broadcasts: [
        Broadcast.normalised(platform: 'Late', weekday: 6, hour: 22, minute: 0, timezone: 'Asia/Tokyo', firstAirDate: '2026-07-04'),
        Broadcast.normalised(platform: 'Early', weekday: 4, hour: 25, minute: 0, timezone: 'Asia/Tokyo', firstAirDate: '2026-07-02'),
      ],
      addedAt: DateTime(2026, 9, 2),
    );
    expect(sortedBroadcasts(entry).first.platform, 'Early');
  });

  test('LLM JSON parsing tolerates fences and prose', () {
    final j = LlmClient.parseJsonObject('Sure!\n```json\n{"complete": true, "broadcasts": []}\n```');
    expect(j['complete'], true);
  });

  test('entries round-trip through JSON', () {
    final entry = AnimeEntry(
      id: 511177,
      nameCn: '遭到流放的转生重骑士凭借游戏知识大开无双',
      nameJp: '追放された転生重騎士はゲーム知識で無双する',
      coverUrl: 'https://example/x.jpg',
      firstAirDate: '2026-07-02',
      lastAirDate: '2026-12-24',
      broadcasts: [
        Broadcast.normalised(platform: 'MBS', weekday: 4, hour: 25, minute: 0, timezone: 'Asia/Tokyo', firstAirDate: '2026-07-02'),
      ],
      addedAt: DateTime(2026, 9, 2),
    );
    final back = AnimeEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())) as Map<String, dynamic>);
    expect(back.id, entry.id);
    expect(back.broadcasts.single.weekday, 5);
    expect(back.broadcasts.single.hour, 1);
    expect(back.isEnded, false);
    expect(back.isUpcoming, false);
  });

  test('titleFor picks the language-specific title with fallbacks', () {
    final e = AnimeEntry(
      id: 1,
      nameCn: '关于我转生变成史莱姆这档事',
      nameJp: '転生したらスライムだった件',
      nameEn: 'That Time I Got Reincarnated as a Slime',
      nameZhHant: '關於我轉生變成史萊姆這檔事',
      coverUrl: '',
      broadcasts: const [],
      addedAt: DateTime(2026, 9, 2),
    );
    expect(e.titleFor('zh'), '关于我转生变成史莱姆这档事');
    expect(e.titleFor('zht'), '關於我轉生變成史萊姆這檔事');
    expect(e.titleFor('en'), 'That Time I Got Reincarnated as a Slime');
    final legacy = AnimeEntry(id: 2, nameCn: '幼女战记', nameJp: '幼女戦記', coverUrl: '', broadcasts: const [], addedAt: DateTime(2026, 9, 2));
    expect(legacy.titleFor('zht'), '幼女战记'); // no traditional title yet → simplified
    expect(legacy.titleFor('en'), '幼女戦記'); // no English title yet → Japanese
  });
}

void _nextOccurrencesTests() {
  group('nextOccurrences', () {
    // Thursday 23:00 Tokyo; "now" = Wed 2026-09-02 12:00 Tokyo (= 03:00 UTC).
    final b = Broadcast.normalised(platform: 'x', weekday: 4, hour: 23, minute: 0, timezone: 'Asia/Tokyo', firstAirDate: '2026-07-02');
    final now = DateTime.utc(2026, 9, 2, 3);

    test('lists weekly instants strictly after now', () {
      final t = nextOccurrences(b, count: 3, now: now);
      expect(t.length, 3);
      expect(t[0].toUtc(), DateTime.utc(2026, 9, 3, 14)); // Thu 23:00 JST
      expect(t[1].difference(t[0]).inDays, 7);
      expect(t[2].difference(t[1]).inDays, 7);
    });

    test('stops after the last air date (one day of slack)', () {
      final t = nextOccurrences(b, count: 6, lastAirDate: '2026-09-17', now: now);
      expect(t.map((d) => d.toUtc()).toList(), [DateTime.utc(2026, 9, 3, 14), DateTime.utc(2026, 9, 10, 14), DateTime.utc(2026, 9, 17, 14)]);
    });

    test('skips dates before the premiere and unknown times', () {
      final up = Broadcast.normalised(platform: 'x', weekday: 4, hour: 23, minute: 0, timezone: 'Asia/Tokyo', firstAirDate: '2026-10-01');
      final t = nextOccurrences(up, count: 2, now: now);
      expect(t.first.toUtc(), DateTime.utc(2026, 10, 1, 14));
      final unknown = Broadcast.normalised(platform: 'x', weekday: 4, hour: -1, minute: 0, timezone: 'Asia/Tokyo');
      expect(nextOccurrences(unknown, now: now), isEmpty);
    });

    test('25:00-style slots land on the next day', () {
      final late = Broadcast.normalised(platform: 'x', weekday: 3, hour: 25, minute: 30, timezone: 'Asia/Tokyo');
      final t = nextOccurrences(late, count: 1, now: now);
      expect(t.single.toUtc(), DateTime.utc(2026, 9, 2, 16, 30)); // Thu 01:30 JST
    });
  });
}
