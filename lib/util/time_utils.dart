import 'package:timezone/timezone.dart' as tz;

import '../models/anime.dart';

/// A broadcast slot converted into the device's local timezone.
class LocalSlot {
  final int weekday; // 1 = Monday ... 7 = Sunday
  final int hour; // -1 when unknown
  final int minute;
  final DateTime? firstAirLocal; // local datetime of the first episode, if known

  const LocalSlot({required this.weekday, required this.hour, required this.minute, this.firstAirLocal});

  bool get timeKnown => hour >= 0;

  String get timeLabel => timeKnown
      ? '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
      : '--:--';
}

tz.Location _location(String name) {
  try {
    return tz.getLocation(name);
  } catch (_) {
    return tz.getLocation('Asia/Tokyo');
  }
}

/// Converts a broadcast into the local timezone, using the next occurrence
/// (so daylight-saving differences are handled for the current week).
LocalSlot toLocalSlot(Broadcast b) {
  final loc = _location(b.timezone);
  if (!b.timeKnown) {
    // Without a time we cannot shift days reliably; keep the source weekday.
    return LocalSlot(weekday: b.weekday, hour: -1, minute: 0, firstAirLocal: _firstAirLocal(b, loc));
  }
  final nowSrc = tz.TZDateTime.now(loc);
  var day = tz.TZDateTime(loc, nowSrc.year, nowSrc.month, nowSrc.day, b.hour, b.minute);
  var guard = 0;
  while (day.weekday != b.weekday && guard < 8) {
    day = tz.TZDateTime(loc, day.year, day.month, day.day + 1, b.hour, b.minute);
    guard++;
  }
  final local = DateTime.fromMillisecondsSinceEpoch(day.millisecondsSinceEpoch).toLocal();
  return LocalSlot(
    weekday: local.weekday,
    hour: local.hour,
    minute: local.minute,
    firstAirLocal: _firstAirLocal(b, loc),
  );
}

DateTime? _firstAirLocal(Broadcast b, tz.Location loc) {
  final d = b.firstAirDate == null ? null : DateTime.tryParse(b.firstAirDate!);
  if (d == null) return null;
  final h = b.timeKnown ? b.hour : 0;
  final m = b.timeKnown ? b.minute : 0;
  final src = tz.TZDateTime(loc, d.year, d.month, d.day, h, m);
  return DateTime.fromMillisecondsSinceEpoch(src.millisecondsSinceEpoch).toLocal();
}

/// Absolute instant used to order platforms from earliest to latest.
int broadcastSortKey(Broadcast b, AnimeEntry entry) {
  final loc = _location(b.timezone);
  final dateStr = b.firstAirDate ?? entry.firstAirDate;
  final d = dateStr == null ? null : DateTime.tryParse(dateStr);
  final h = b.timeKnown ? b.hour : 0;
  final m = b.timeKnown ? b.minute : 0;
  if (d != null) {
    // Snap to the broadcast weekday on/after the given date.
    var day = tz.TZDateTime(loc, d.year, d.month, d.day, h, m);
    var guard = 0;
    while (day.weekday != b.weekday && guard < 8) {
      day = tz.TZDateTime(loc, day.year, day.month, day.day + 1, h, m);
      guard++;
    }
    return day.millisecondsSinceEpoch;
  }
  final nowSrc = tz.TZDateTime.now(loc);
  var day = tz.TZDateTime(loc, nowSrc.year, nowSrc.month, nowSrc.day, h, m);
  var guard = 0;
  while (day.weekday != b.weekday && guard < 8) {
    day = tz.TZDateTime(loc, day.year, day.month, day.day + 1, h, m);
    guard++;
  }
  return day.millisecondsSinceEpoch;
}

/// Broadcasts sorted from earliest to latest.
List<Broadcast> sortedBroadcasts(AnimeEntry entry) {
  final list = List<Broadcast>.from(entry.broadcasts);
  list.sort((a, b) => broadcastSortKey(a, entry).compareTo(broadcastSortKey(b, entry)));
  return list;
}

String fmtDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String fmtDateTime(DateTime d) =>
    '${fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Upcoming instants of [b] in local time, strictly after [now], at most
/// [count], skipping anything before the platform's premiere and anything
/// after [lastAirDate] (yyyy-MM-dd in the source timezone, one day of slack).
List<DateTime> nextOccurrences(Broadcast b, {int count = 6, String? lastAirDate, DateTime? now}) {
  if (!b.timeKnown || count <= 0) return const [];
  final loc = _location(b.timezone);
  final nowSrc = now == null ? tz.TZDateTime.now(loc) : tz.TZDateTime.from(now, loc);
  var day = tz.TZDateTime(loc, nowSrc.year, nowSrc.month, nowSrc.day, b.hour, b.minute);
  var guard = 0;
  while ((day.weekday != b.weekday || !day.isAfter(nowSrc)) && guard < 9) {
    day = tz.TZDateTime(loc, day.year, day.month, day.day + 1, b.hour, b.minute);
    guard++;
  }
  final firstDate = b.firstAirDate == null ? null : DateTime.tryParse(b.firstAirDate!);
  final first = firstDate == null ? null : tz.TZDateTime(loc, firstDate.year, firstDate.month, firstDate.day);
  final lastDate = lastAirDate == null ? null : DateTime.tryParse(lastAirDate);
  final end = lastDate == null ? null : tz.TZDateTime(loc, lastDate.year, lastDate.month, lastDate.day + 2);
  final out = <DateTime>[];
  guard = 0;
  while (out.length < count && guard < 60) {
    if (end != null && !day.isBefore(end)) break;
    if (first == null || !day.isBefore(first)) {
      out.add(DateTime.fromMillisecondsSinceEpoch(day.millisecondsSinceEpoch).toLocal());
    }
    day = tz.TZDateTime(loc, day.year, day.month, day.day + 7, b.hour, b.minute);
    guard++;
  }
  return out;
}
