import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

enum LogLevel { debug, info, warn, error }

/// Always-on file logger. Nothing in the UI exposes it.
///
/// Every cold start (new process) deletes the previous log and starts a fresh
/// one; resuming from the background keeps appending. Path:
/// `<external app files dir>/logs/anime_now.log`, e.g.
/// /sdcard/Android/data/com.erichuanp.animenow/files/logs/anime_now.log
/// (readable with a file manager or `adb pull`, no root needed).
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  /// Max characters kept per message (bodies are truncated beyond this).
  static const int maxMessageChars = 60000;

  File? _file;
  RandomAccessFile? _raf;
  bool _initialised = false;
  final List<String> _pending = [];

  /// Path of the current log file, once [init] has run.
  String? get path => _file?.path;

  /// Deletes the previous log and opens a fresh one. Call once at startup.
  /// [baseDir] defaults to the app's external files dir.
  Future<void> init([Directory? baseDir]) async {
    if (_initialised) return;
    _initialised = true;
    await _open(baseDir);
  }

  Future<void> _open(Directory? baseDir, {String carried = ''}) async {
    try {
      final base = baseDir ?? await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/logs');
      await dir.create(recursive: true);
      _file = File('${dir.path}/anime_now.log');
      // Fresh file every launch.
      if (await _file!.exists()) await _file!.delete();
      final stale = File('${dir.path}/anime_now.log.1');
      if (await stale.exists()) await stale.delete();
      // Synchronous, unbuffered writes: every line is on disk before the
      // next statement runs, and nothing can throw on a pending flush.
      _raf = _file!.openSync(mode: FileMode.write);
      if (carried.isNotEmpty) {
        _raf!.writeStringSync(carried);
        _raf!.flushSync();
      } else {
        _writeLine('===== session start ${DateTime.now().toIso8601String()} '
          'tz=${DateTime.now().timeZoneName} offset=${DateTime.now().timeZoneOffset} '
          'platform=${Platform.operatingSystem} ${Platform.operatingSystemVersion} =====');
      }
      for (final line in _pending) {
        _writeLine(line);
      }
      _pending.clear();
      debugPrint('[AnimeNow] log → ${_file!.path}');
    } catch (e) {
      debugPrint('[AnimeNow] failed to open log file: $e');
    }
  }

  void d(String tag, String message) => _add(LogLevel.debug, tag, message);
  void i(String tag, String message) => _add(LogLevel.info, tag, message);
  void w(String tag, String message) => _add(LogLevel.warn, tag, message);
  void e(String tag, String message, [Object? error, StackTrace? stack]) {
    final buf = StringBuffer(message);
    if (error != null) buf.write('\n  error: $error');
    if (stack != null) buf.write('\n  stack: $stack');
    _add(LogLevel.error, tag, buf.toString());
  }

  void _add(LogLevel level, String tag, String message) {
    var msg = message;
    if (msg.length > maxMessageChars) {
      msg = '${msg.substring(0, maxMessageChars)}\n…[truncated ${message.length - maxMessageChars} chars]';
    }
    final levelChar = const ['D', 'I', 'W', 'E'][level.index];
    final line = '${DateTime.now().toIso8601String()} $levelChar/$tag: $msg';
    debugPrint('[AnimeNow] $line');
    if (_raf == null) {
      _pending.add(line);
      if (_pending.length > 2000) _pending.removeRange(0, _pending.length - 2000);
      return;
    }
    _writeLine(line);
  }

  void _writeLine(String line) {
    try {
      _raf!.writeStringSync('$line\n');
      _raf!.flushSync();
    } catch (e) {
      debugPrint('[AnimeNow] log write failed: $e');
    }
  }

  /// Pretty-prints JSON when possible, otherwise returns the raw text.
  static String prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  /// Replaces credential headers with a placeholder. Nothing about the key
  /// itself reaches the log file — not a prefix, not a suffix, not its length:
  /// the log lives in a world-readable directory on Android and users paste it
  /// into bug reports.
  static Map<String, String> maskHeaders(Map<String, String> headers) {
    final out = <String, String>{};
    headers.forEach((k, v) {
      final lk = k.toLowerCase();
      if (lk == 'authorization' || lk == 'x-api-key') {
        // Keep the scheme ("Bearer") so the line still reads as an auth header.
        final scheme = v.split(' ');
        out[k] = scheme.length > 1 ? '${scheme.first} <key>' : '<key>';
      } else {
        out[k] = v;
      }
    });
    return out;
  }
}

/// http.Client wrapper that logs every request/response.
class LoggingClient extends http.BaseClient {
  LoggingClient({http.Client? inner, this.tag = 'http'}) : _inner = inner ?? http.Client();

  final http.Client _inner;
  final String tag;
  static int _seq = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final log = AppLog.instance;
    final id = ++_seq;
    final sw = Stopwatch()..start();
    final buf = StringBuffer('#$id → ${request.method} ${request.url}');
    buf.write('\n  headers: ${AppLog.maskHeaders(request.headers)}');
    if (request is http.Request && request.body.isNotEmpty) {
      buf.write('\n  body: ${AppLog.prettyJson(request.body)}');
    }
    log.d(tag, buf.toString());
    try {
      final res = await _inner.send(request);
      final bytes = await res.stream.toBytes();
      sw.stop();
      String text;
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = '<${bytes.length} bytes, not utf8>';
      }
      log.d(tag,
          '#$id ← ${res.statusCode} ${request.method} ${request.url} (${sw.elapsedMilliseconds} ms, ${bytes.length} bytes)'
          '\n  headers: ${res.headers}'
          '\n  body: ${AppLog.prettyJson(text)}');
      return http.StreamedResponse(
        http.ByteStream.fromBytes(bytes),
        res.statusCode,
        contentLength: bytes.length,
        request: res.request,
        headers: res.headers,
        isRedirect: res.isRedirect,
        persistentConnection: res.persistentConnection,
        reasonPhrase: res.reasonPhrase,
      );
    } catch (e, st) {
      sw.stop();
      log.e(tag, '#$id ✗ ${request.method} ${request.url} failed after ${sw.elapsedMilliseconds} ms', e, st);
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}
