import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../models/anime.dart';
import '../services/settings.dart';
import '../util/time_utils.dart';
import '../util/toast.dart';
import 'cover_image.dart';

class AnimeCard extends StatelessWidget {
  const AnimeCard({super.key, required this.entry, this.trailing});

  final AnimeEntry entry;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<AppSettings>();
    final sorted = sortedBroadcasts(entry);
    final earliest = sorted.isEmpty ? null : sorted.first;
    final slot = earliest == null ? null : toLocalSlot(earliest);

    // Line 2: premiere date + local weekday/time. Line 3: earliest platform.
    String line2;
    String? line3;
    if (earliest == null || slot == null) {
      line2 = s.timeUnknown;
    } else {
      final parts = <String>[];
      final first = slot.firstAirLocal;
      if (first != null) parts.add('${s.firstAir} ${fmtDate(first)}');
      final wd = s.weekdayShort(slot.weekday, japanese: settings.japaneseWeekday);
      parts.add(slot.timeKnown ? '$wd ${slot.timeLabel}' : '$wd ${s.timeUnknown}');
      line2 = parts.join(' · ');
      line3 = earliest.platform;
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showBroadcastDialog(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(10),
          // Fixed height and a reserved trailing slot so cards on the schedule
          // page and the search page are exactly the same size.
          child: SizedBox(
            height: 104,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 72,
                  height: 100,
                  child: CoverImage(url: entry.coverUrl),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.titleFor(s.lang),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(line2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    if (line3 != null)
                      Text(line3, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    if (entry.isUpcoming || entry.isEnded) ...[
                      const SizedBox(height: 6),
                      _Tag(
                        text: entry.isEnded ? s.ended : s.upcoming,
                        color: entry.isEnded ? Colors.grey.shade400 : const Color(0xFFF06292),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(width: 44, child: Center(child: trailing)),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
      );
}

Future<void> showBroadcastDialog(BuildContext context, AnimeEntry entry) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final s = S.of(ctx);
      final settings = ctx.watch<AppSettings>();
      // Platforms sharing the same local weekday + time are merged into one
      // row; at most five rows are shown (regional TV lists can run past 30).
      const maxShown = 5;
      final all = sortedBroadcasts(entry);
      final groups = <String, _SlotGroup>{};
      for (final b in all) {
        final slot = toLocalSlot(b);
        final key = '${slot.weekday}-${slot.hour}-${slot.minute}';
        final g = groups.putIfAbsent(key, () => _SlotGroup(slot));
        if (!g.platforms.contains(b.platform)) g.platforms.add(b.platform);
        g.firstAirLocal ??= slot.firstAirLocal;
        if (g.note == null && b.note != null && b.note!.isNotEmpty) g.note = b.note;
      }
      final rows = groups.values.take(maxShown).toList();
      final hidden = all.length - rows.fold<int>(0, (n, g) => n + g.platforms.length);
      return AlertDialog(
        backgroundColor: const Color(0xFFFFF8FB),
        title: GestureDetector(
          onLongPress: () => _copy(context, entry.titleFor(s.lang)),
          child: Text(entry.titleFor(s.lang), style: const TextStyle(fontSize: 17)),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.nameJp.isNotEmpty && entry.nameJp != entry.titleFor(s.lang))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GestureDetector(
                    onLongPress: () => _copy(context, entry.nameJp),
                    child: Text(entry.nameJp, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ),
                ),
              Text(s.allPlatforms, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 12),
                  itemBuilder: (_, i) {
                    final g = rows[i];
                    final slot = g.slot;
                    final wd = s.weekday(slot.weekday, japanese: settings.japaneseWeekday);
                    final time = slot.timeKnown ? slot.timeLabel : s.timeUnknown;
                    final first = g.firstAirLocal;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.platforms.join(' · '), style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('$wd $time', style: const TextStyle(fontSize: 14)),
                        if (first != null)
                          Text('${s.firstAir} ${fmtDateTime(first)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (g.note != null)
                          Text(g.note!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    );
                  },
                ),
              ),
              if (hidden > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.morePlatforms(hidden), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              const SizedBox(height: 10),
              Text(s.localTimeNote, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.close)),
        ],
      );
    },
  );
}

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, '${S.of(context).copied}: $text');
}

/// Platforms that share one local broadcast slot.
class _SlotGroup {
  _SlotGroup(this.slot);
  final LocalSlot slot;
  final List<String> platforms = [];
  DateTime? firstAirLocal;
  String? note;
}
