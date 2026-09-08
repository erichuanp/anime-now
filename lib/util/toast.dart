import 'dart:async';

import 'package:flutter/material.dart';

/// App-wide notifications rendered in the root overlay, stacked above the
/// floating nav pill. Each one lives 3 s on its own timer and can be
/// swiped down to dismiss; new ones never replace older ones.
void showToast(BuildContext context, String text, {SnackBarAction? action}) {
  _Toasts.instance.show(context, text, actionLabel: action?.label, onAction: action?.onPressed);
}

class _ToastItem {
  _ToastItem(this.id, this.text, this.actionLabel, this.onAction);
  final int id;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  Timer? timer;
}

class _Toasts {
  _Toasts._();
  static final _Toasts instance = _Toasts._();

  static const lifetime = Duration(seconds: 3);
  static const maxVisible = 4;

  final ValueNotifier<List<_ToastItem>> items = ValueNotifier(const []);
  OverlayEntry? _entry;
  int _seq = 0;

  void show(BuildContext context, String text, {String? actionLabel, VoidCallback? onAction}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final item = _ToastItem(++_seq, text, actionLabel, onAction);
    item.timer = Timer(lifetime, () => _remove(item));
    final next = [...items.value, item];
    // Oldest drops first when too many pile up.
    while (next.length > maxVisible) {
      next.removeAt(0).timer?.cancel();
    }
    items.value = next;
    if (_entry == null) {
      _entry = OverlayEntry(builder: (_) => _ToastLayer(manager: this));
      overlay.insert(_entry!);
    }
  }

  void _remove(_ToastItem item) {
    item.timer?.cancel();
    if (!items.value.contains(item)) return;
    items.value = items.value.where((i) => i != item).toList();
  }
}

class _ToastLayer extends StatelessWidget {
  const _ToastLayer({required this.manager});
  final _Toasts manager;

  @override
  Widget build(BuildContext context) {
    // 45dp pill + 12dp margin above the safe inset + 20dp gap.
    final bottom = MediaQuery.of(context).padding.bottom + 12 + 45 + 20;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: ValueListenableBuilder<List<_ToastItem>>(
        valueListenable: manager.items,
        builder: (context, list, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in list)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ToastCard(item: item, onDismiss: () => manager._remove(item)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.item, required this.onDismiss});
  final _ToastItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('toast-${item.id}'),
      direction: DismissDirection.down,
      onDismissed: (_) => onDismiss(),
      child: Material(
        color: const Color(0xFF322F33),
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(item.text, style: const TextStyle(color: Colors.white, fontSize: 14)),
              ),
              if (item.actionLabel != null)
                TextButton(
                  onPressed: () {
                    item.onAction?.call();
                    onDismiss();
                  },
                  child: Text(item.actionLabel!, style: const TextStyle(color: Color(0xFFF8BBD0), fontSize: 15)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
