import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'app_log.dart';
import 'bangumi_hosts.dart';

typedef CoverFetch = Future<File> Function(String displayUrl, String key);
typedef CoverLookup = Future<File?> Function(String key);

/// Loads covers strictly one at a time, in the order they were requested.
/// The 番时 mirror queues every request globally, so firing a screenful of
/// covers at once would just get most of them rejected; main.dart enqueues the
/// whole schedule in anime.json order at startup and whenever the list changes.
///
/// Files are keyed by the canonical lain.bgm.tv URL, so switching the Bangumi
/// source or removing and re-adding a show reuses what is already on disk and
/// never hits the network again. Covers are only evicted explicitly
/// ([evict], used by 「移除全部已完结的番剧」).
class CoverCache extends ChangeNotifier {
  CoverCache({
    CoverFetch? fetch,
    CoverLookup? lookup,
    BangumiHosts? hosts,
    Duration timeout = const Duration(seconds: 90),
  })  : _fetch = fetch ?? _diskFetch,
        _lookup = lookup ?? _diskLookup,
        _hosts = hosts ?? BangumiHosts.instance,
        _timeout = timeout; // ignore: prefer_initializing_formals

  static final instance = CoverCache();
  static final _log = AppLog.instance;

  /// Own cache bucket: covers are small and we never want the manager's
  /// default 200-object / 30-day cleanup to throw them away behind our back.
  static final CacheManager _manager = CacheManager(Config(
    'animeNowCovers',
    stalePeriod: const Duration(days: 3650),
    maxNrOfCacheObjects: 5000,
  ));

  static Future<File> _diskFetch(String url, String key) async => (await _manager.downloadFile(url, key: key)).file;

  static Future<File?> _diskLookup(String key) async => (await _manager.getFileFromCache(key))?.file;

  final CoverFetch _fetch;
  final CoverLookup _lookup;
  final BangumiHosts _hosts;
  final Duration _timeout;

  final Map<String, File> _files = {};
  final Set<String> _failed = {};
  final List<String> _queue = [];
  final Set<String> _queued = {};
  bool _running = false;
  String? _current;

  /// Canonical URL currently being fetched, if any.
  String? get current => _current;
  int get pending => _queue.length + (_current == null ? 0 : 1);

  File? fileFor(String canonical) => _files[canonical];

  /// Queues [canonical] unless it is loaded or already waiting. Cheap and
  /// idempotent, so widgets may call it from build.
  void ensure(String canonical) {
    if (canonical.isEmpty || _files.containsKey(canonical) || _queued.contains(canonical)) return;
    _failed.remove(canonical);
    _queue.add(canonical);
    _queued.add(canonical);
    _kick();
  }

  void ensureAll(Iterable<String> canonicals) {
    for (final c in canonicals) {
      ensure(c);
    }
  }

  /// Re-queues everything that failed (called on resume and when the Bangumi
  /// source changes).
  void retryFailed() {
    if (_failed.isEmpty) return;
    final again = _failed.toList();
    _failed.clear();
    ensureAll(again);
  }

  /// Drops a cover from memory and disk (the show is gone for good).
  Future<void> evict(String canonical) async {
    if (canonical.isEmpty) return;
    _files.remove(canonical);
    _failed.remove(canonical);
    try {
      await _manager.removeFile(canonical);
    } catch (e) {
      _log.w('covers', 'evict $canonical failed: $e');
    }
    notifyListeners();
  }

  void _kick() {
    if (_running) return;
    _running = true;
    // Never run (and notify) synchronously inside a build.
    Future(_drain);
  }

  Future<void> _drain() async {
    while (_queue.isNotEmpty) {
      final c = _queue.removeAt(0);
      try {
        var f = await _lookup(c);
        if (f != null && !f.existsSync()) f = null;
        if (f == null) {
          _current = c;
          final url = _hosts.display(c);
          _log.d('covers', 'fetch $url (${_queue.length} more queued)');
          f = await _fetch(url, c).timeout(_timeout);
        }
        _files[c] = f;
      } catch (e) {
        _failed.add(c);
        _log.w('covers', 'failed $c: $e');
      }
      _current = null;
      _queued.remove(c);
      notifyListeners();
    }
    _running = false;
  }
}
