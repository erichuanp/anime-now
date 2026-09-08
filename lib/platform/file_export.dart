import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../services/app_log.dart';
import 'host.dart';

/// Hands [content] to the user as a file, the way the platform expects.
///
/// Android drops it straight into `Download/AnimeNow/` through MediaStore (no
/// permission, no dialog). Desktop opens the system save panel. Returns where
/// it landed, or null when the user cancelled the desktop dialog.
Future<String?> exportTextFile(String name, String content) async {
  if (isDesktop) return _saveViaDialog(name, content);
  final r = await hostChannel.invokeMethod<String>('saveToDownloads', {'name': name, 'content': content});
  AppLog.instance.i('export', 'saved $name to $r');
  return r ?? 'Download/AnimeNow/$name';
}

Future<String?> _saveViaDialog(String name, String content) async {
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json'], uniformTypeIdentifiers: ['public.json']),
    ],
  );
  if (location == null) {
    AppLog.instance.i('export', 'save dialog cancelled');
    return null;
  }
  await File(location.path).writeAsString(content, encoding: utf8, flush: true);
  AppLog.instance.i('export', 'saved $name to ${location.path}');
  return location.path;
}
