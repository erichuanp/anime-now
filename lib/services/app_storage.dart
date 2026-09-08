import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/file_export.dart';
import '../platform/host.dart';
import 'app_log.dart';

/// Where config.json / anime.json / logs live.
///
/// Android: the app's own `Android/data/com.erichuanp.animenow/files/` (no
/// permission needed, visible over USB, wiped on uninstall). Desktop: the
/// per-user application-support directory the OS hands out — on macOS
/// `~/Library/Application Support/com.erichuanp.animenow/`, on Windows
/// `%APPDATA%\erichuanp\Anime Now\` (company + product from the exe's
/// version info).
class AppStorage extends ChangeNotifier {
  AppStorage.at(this.dir);

  final Directory dir;
  String get path => dir.path;

  static Future<AppStorage> resolve() async {
    Directory? d;
    if (!isDesktop) {
      try {
        d = await getExternalStorageDirectory();
      } catch (e) {
        AppLog.instance.w('storage', 'external files dir unavailable: $e');
      }
    }
    d ??= await getApplicationSupportDirectory();
    await d.create(recursive: true);
    AppLog.instance.i('storage', 'using ${d.path}');
    return AppStorage.at(d);
  }

  /// Hands a file to the user: straight into `Download/AnimeNow/` on Android,
  /// through the system save panel on desktop. Null means the user cancelled.
  Future<String?> export(String name, String content) => exportTextFile(name, content);

  File file(String name) => File('${dir.path}/$name');

  Future<Map<String, dynamic>?> readJson(String name) async {
    final f = file(name);
    try {
      if (!await f.exists()) return null;
      final text = await f.readAsString();
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      AppLog.instance.e('storage', 'read $name failed', e);
      return null;
    }
  }

  /// Atomic write: temp file then rename.
  Future<void> writeJson(String name, Object data) async {
    final f = file(name);
    final tmp = File('${f.path}.tmp');
    try {
      await dir.create(recursive: true);
      await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      await tmp.rename(f.path);
      AppLog.instance.d('storage', 'wrote ${f.path}');
    } catch (e) {
      AppLog.instance.e('storage', 'write $name failed', e);
    }
  }
}
