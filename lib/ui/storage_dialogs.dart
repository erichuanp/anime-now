import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../main.dart';
import '../services/anime_store.dart';
import '../services/app_log.dart';
import '../services/app_storage.dart';
import '../util/toast.dart';

/// Saves anime.json where the platform puts downloads, then explains how to
/// restore it.
Future<void> downloadAnimeBackup(BuildContext context) async {
  final storage = context.read<AppStorage>();
  final store = context.read<AnimeStore>();
  final s = S.of(context);
  String? saved;
  try {
    saved = await storage.export(AnimeStore.fileName, const JsonEncoder.withIndent('  ').convert(store.toJson()));
  } catch (e) {
    AppLog.instance.w('storage', 'backup failed: $e');
    if (context.mounted) showToast(context, '${s.backupFailed}: $e');
    return;
  }
  if (saved == null) return; // desktop save panel dismissed
  final where = saved;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFFFFF8FB),
      title: Text(s.backupDoneTitle, style: const TextStyle(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.backupDoneBody(where), style: const TextStyle(fontSize: 14, height: 1.4)),
            const SizedBox(height: 8),
            SelectableText(storage.path, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey.shade700)),
          ],
        ),
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(s.ok),
        ),
      ],
    ),
  );
}
