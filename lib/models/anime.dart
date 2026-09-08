import 'dart:convert';

/// One broadcast slot on one platform, expressed in the platform's own timezone.
class Broadcast {
  final String platform;

  /// 1 = Monday ... 7 = Sunday, already normalised (25:00 -> next day 01:00).
  final int weekday;

  /// -1 when the time is unknown (only the weekday is known).
  final int hour;
  final int minute;

  /// IANA timezone name, e.g. Asia/Tokyo.
  final String timezone;

  /// yyyy-MM-dd of the first episode on this platform, if known.
  final String? firstAirDate;
  final String? note;

  const Broadcast._({
    required this.platform,
    required this.weekday,
    required this.hour,
    required this.minute,
    required this.timezone,
    this.firstAirDate,
    this.note,
  });

  /// Builds a broadcast from raw source values, normalising "25:00"-style hours.
  factory Broadcast.normalised({
    required String platform,
    required int weekday,
    required int hour,
    required int minute,
    required String timezone,
    String? firstAirDate,
    String? note,
  }) {
    var w = weekday;
    var h = hour;
    var date = firstAirDate;
    if (h >= 24) {
      final extraDays = h ~/ 24;
      h = h % 24;
      w = ((w - 1 + extraDays) % 7) + 1;
      final parsed = date == null ? null : DateTime.tryParse(date);
      if (parsed != null) {
        final shifted = parsed.add(Duration(days: extraDays));
        date = _fmtDate(shifted);
      }
    }
    if (w < 1 || w > 7) w = ((w - 1) % 7 + 7) % 7 + 1;
    return Broadcast._(
      platform: platform,
      weekday: w,
      hour: h,
      minute: minute.clamp(0, 59),
      timezone: timezone,
      firstAirDate: date,
      note: note,
    );
  }

  bool get timeKnown => hour >= 0;

  Map<String, dynamic> toJson() => {
        'platform': platform,
        'weekday': weekday,
        'hour': hour,
        'minute': minute,
        'timezone': timezone,
        'firstAirDate': firstAirDate,
        'note': note,
      };

  factory Broadcast.fromJson(Map<String, dynamic> j) => Broadcast._(
        platform: j['platform'] as String? ?? '',
        weekday: (j['weekday'] as num?)?.toInt() ?? 1,
        hour: (j['hour'] as num?)?.toInt() ?? -1,
        minute: (j['minute'] as num?)?.toInt() ?? 0,
        timezone: j['timezone'] as String? ?? 'Asia/Tokyo',
        firstAirDate: j['firstAirDate'] as String?,
        note: j['note'] as String?,
      );
}

class AnimeEntry {
  final int id; // bangumi subject id
  final String nameCn; // 简体
  final String nameJp;
  final String? nameEn;
  final String? nameZhHant; // 繁體
  final String coverUrl;

  /// First air date overall (from bangumi), yyyy-MM-dd.
  final String? firstAirDate;

  /// Air date of the last episode (from bangumi episodes), yyyy-MM-dd.
  final String? lastAirDate;
  final int? totalEpisodes;
  final List<Broadcast> broadcasts;
  final DateTime addedAt;

  const AnimeEntry({
    required this.id,
    required this.nameCn,
    required this.nameJp,
    this.nameEn,
    this.nameZhHant,
    required this.coverUrl,
    this.firstAirDate,
    this.lastAirDate,
    this.totalEpisodes,
    required this.broadcasts,
    required this.addedAt,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : nameJp;

  /// Title for the UI language ('zh' 简体, 'zht' 繁體, 'en'); falls back sensibly.
  String titleFor(String lang) {
    String pick(String? v) => (v != null && v.trim().isNotEmpty) ? v : '';
    switch (lang) {
      case 'en':
        return pick(nameEn).isNotEmpty ? nameEn! : (nameJp.isNotEmpty ? nameJp : displayName);
      case 'zht':
        return pick(nameZhHant).isNotEmpty ? nameZhHant! : displayName;
      default:
        return displayName;
    }
  }

  bool get isUpcoming {
    final d = firstAirDate == null ? null : DateTime.tryParse(firstAirDate!);
    if (d == null) return false;
    return d.isAfter(_today());
  }

  bool get isEnded {
    final d = lastAirDate == null ? null : DateTime.tryParse(lastAirDate!);
    if (d == null) return false;
    return d.isBefore(_today());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nameCn': nameCn,
        'nameJp': nameJp,
        'nameEn': nameEn,
        'nameZhHant': nameZhHant,
        'coverUrl': coverUrl,
        'firstAirDate': firstAirDate,
        'lastAirDate': lastAirDate,
        'totalEpisodes': totalEpisodes,
        'broadcasts': broadcasts.map((b) => b.toJson()).toList(),
        'addedAt': addedAt.toIso8601String(),
      };

  factory AnimeEntry.fromJson(Map<String, dynamic> j) => AnimeEntry(
        id: (j['id'] as num).toInt(),
        nameCn: j['nameCn'] as String? ?? '',
        nameJp: j['nameJp'] as String? ?? '',
        nameEn: j['nameEn'] as String?,
        nameZhHant: j['nameZhHant'] as String?,
        coverUrl: j['coverUrl'] as String? ?? '',
        firstAirDate: j['firstAirDate'] as String?,
        lastAirDate: j['lastAirDate'] as String?,
        totalEpisodes: (j['totalEpisodes'] as num?)?.toInt(),
        broadcasts: (j['broadcasts'] as List<dynamic>? ?? [])
            .map((e) => Broadcast.fromJson(e as Map<String, dynamic>))
            .toList(),
        addedAt: DateTime.tryParse(j['addedAt'] as String? ?? '') ?? DateTime.now(),
      );

  static String encodeList(List<AnimeEntry> list) => jsonEncode(list.map((e) => e.toJson()).toList());
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
