import 'package:flutter/material.dart';

import '../main.dart';

/// One line of a [ContextMenuRegion] menu.
class ContextMenuItem {
  const ContextMenuItem({required this.label, required this.icon, required this.onSelected, this.danger = false});

  final String label;
  final IconData icon;
  final VoidCallback onSelected;
  final bool danger;
}

/// Right-click menu, the desktop counterpart of swiping a card left. The swipe
/// keeps working, so a mouse and a finger both have a way to reach the action.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({super.key, required this.child, required this.items});

  final Widget child;
  final List<ContextMenuItem> items;

  Future<void> _open(BuildContext context, Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final chosen = await showMenu<ContextMenuItem>(
      context: context,
      color: const Color(0xFFFFF8FB),
      position: RelativeRect.fromLTRB(
        at.dx,
        at.dy,
        overlay.size.width - at.dx,
        overlay.size.height - at.dy,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<ContextMenuItem>(
            value: item,
            height: 38,
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: item.danger ? const Color(0xFFE53935) : AppColors.accent),
                const SizedBox(width: 8),
                Text(item.label, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
      ],
    );
    chosen?.onSelected();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onSecondaryTapDown: (d) => _open(context, d.globalPosition),
        child: child,
      );
}
