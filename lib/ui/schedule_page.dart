import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../main.dart';
import '../models/anime.dart';
import '../services/anime_store.dart';
import '../services/settings.dart';
import '../util/time_utils.dart';
import '../util/toast.dart';
import 'anime_card.dart';
import 'context_menu.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  final _centerKey = const ValueKey('today');
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Measured height of each weekday section (all cycles repeat these 7).
  final Map<int, double> _heights = {};
  bool _bannerDismissed = false;

  /// Jump to the NEAREST occurrence of today's section. Today's sections sit
  /// at offsets k * (sum of the 7 section heights) for every integer k, since
  /// the center sliver starts with today and both directions repeat the week.
  void _backToToday() {
    if (!_scroll.hasClients) return;
    var cycle = 0.0;
    for (var w = 1; w <= 7; w++) {
      cycle += _heights[w] ?? 0;
    }
    if (cycle <= 0 || _heights.length < 7) {
      // Not every weekday measured yet: fall back to the original center.
      _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      return;
    }
    final k = (_scroll.position.pixels / cycle).round();
    _scroll.animateTo(k * cycle, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<AppSettings>();
    final store = context.watch<AnimeStore>();
    final today = DateTime.now().weekday; // 1..7

    // Group entries by local weekday according to the time basis setting.
    final byDay = <int, List<AnimeEntry>>{for (var i = 1; i <= 7; i++) i: []};
    for (final e in store.items) {
      final sorted = sortedBroadcasts(e);
      if (sorted.isEmpty) continue;
      final basis = settings.timeBasis == TimeBasis.earliest ? sorted.first : sorted.last;
      final slot = toLocalSlot(basis);
      byDay[slot.weekday]!.add(e);
    }
    for (final list in byDay.values) {
      list.sort((a, b) {
        final sa = toLocalSlot(_basis(a, settings));
        final sb = toLocalSlot(_basis(b, settings));
        return (sa.hour * 60 + sa.minute).compareTo(sb.hour * 60 + sb.minute);
      });
    }

    int dayAt(int offset) => ((today - 1 + offset) % 7 + 7) % 7 + 1;

    final showBanner = store.hasEnded && !_bannerDismissed;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.appName),
        actions: [
          IconButton(
            tooltip: s.backToToday,
            icon: const Icon(Icons.today_outlined),
            color: AppColors.accent,
            onPressed: _backToToday,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            center: _centerKey,
            slivers: [
              // Days before today, laid out upwards (infinite).
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _Measured(
                    onSize: (h) => _heights[dayAt(-(i + 1))] = h,
                    child: _DaySection(
                      weekday: dayAt(-(i + 1)),
                      entries: byDay[dayAt(-(i + 1))]!,
                      // Every 7th item upwards is today's weekday again.
                      isToday: (i + 1) % 7 == 0,
                    ),
                  ),
                ),
              ),
              // Today and onwards (infinite).
              SliverList(
                key: _centerKey,
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _Measured(
                    onSize: (h) => _heights[dayAt(i)] = h,
                    child: _DaySection(
                      weekday: dayAt(i),
                      entries: byDay[dayAt(i)]!,
                      isToday: i % 7 == 0,
                    ),
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
            ],
          ),
          if (showBanner)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: _EndedBanner(
                text: s.endedBanner,
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            ),
        ],
      ),
    );
  }

  static Broadcast _basis(AnimeEntry e, AppSettings settings) {
    final sorted = sortedBroadcasts(e);
    return settings.timeBasis == TimeBasis.earliest ? sorted.first : sorted.last;
  }
}

/// Reports its laid-out height after each frame (no rebuild triggered).
class _Measured extends StatefulWidget {
  const _Measured({required this.onSize, required this.child});
  final void Function(double height) onSize;
  final Widget child;

  @override
  State<_Measured> createState() => _MeasuredState();
}

class _MeasuredState extends State<_Measured> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = context.size?.height;
      if (h != null && h > 0) widget.onSize(h);
    });
    return widget.child;
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.weekday, required this.entries, required this.isToday});

  final int weekday;
  final List<AnimeEntry> entries;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<AppSettings>();
    final title = s.weekday(weekday, japanese: settings.japaneseWeekday);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
          child: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: isToday ? AppColors.accent : const Color(0xFF6D4C57),
                ),
              ),
              if (isToday) ...[
                const SizedBox(width: 8),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text(s.emptyDay, style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
          )
        else
          for (final e in entries) _SwipeToDelete(entry: e),
      ],
    );
  }
}

class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({required this.entry});
  final AnimeEntry entry;

  Future<void> _remove(BuildContext context, S s) async {
    final store = context.read<AnimeStore>();
    final idx = await store.remove(entry.id);
    if (context.mounted) {
      showToast(
        context,
        '${s.deleted}: ${entry.titleFor(s.lang)}',
        action: SnackBarAction(label: s.undo, onPressed: () => store.insert(idx, entry)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    // Swipe left on a touchscreen, right-click with a mouse.
    return ContextMenuRegion(
      items: [
        ContextMenuItem(label: s.dismiss, icon: Icons.close, danger: true, onSelected: () => _remove(context, s)),
      ],
      child: Slidable(
        key: ValueKey('anime-${entry.id}'),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.28,
          children: [
            CustomSlidableAction(
              onPressed: (ctx) => _remove(ctx, s),
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(16),
              padding: EdgeInsets.zero,
              child: const Icon(Icons.close, size: 44),
            ),
          ],
        ),
        child: AnimeCard(entry: entry),
      ),
    );
  }
}

class _EndedBanner extends StatelessWidget {
  const _EndedBanner({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) onDismiss();
      },
      child: Dismissible(
        key: const ValueKey('ended-banner'),
        direction: DismissDirection.horizontal,
        onDismissed: (_) => onDismiss(),
        child: Material(
          elevation: 3,
          borderRadius: BorderRadius.circular(12),
          color: AppColors.bannerYellow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Color(0xFF8D6E00)),
                const SizedBox(width: 8),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: Color(0xFF5D4A00)))),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: const Color(0xFF8D6E00),
                  onPressed: onDismiss,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
