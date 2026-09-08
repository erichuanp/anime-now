import 'package:flutter/foundation.dart';

import '../models/anime.dart';
import 'app_log.dart';
import 'app_storage.dart';

/// The user's anime list, persisted as anime.json in [AppStorage].
class AnimeStore extends ChangeNotifier {
  AnimeStore._(this._storage);

  static const fileName = 'anime.json';
  final AppStorage _storage;
  List<AnimeEntry> _items = [];

  List<AnimeEntry> get items => List.unmodifiable(_items);

  static Future<AnimeStore> load(AppStorage storage) async {
    final s = AnimeStore._(storage);
    s._items = await _readFrom(storage) ?? [];
    AppLog.instance.i('store', 'loaded ${s._items.length} entries from ${storage.path}: ${s._items.map((e) => '#${e.id}').join(',')}');
    return s;
  }

  static Future<List<AnimeEntry>?> _readFrom(AppStorage storage) async {
    final j = await storage.readJson(fileName);
    if (j == null) return null;
    try {
      return (j['items'] as List<dynamic>? ?? [])
          .map((e) => AnimeEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLog.instance.e('store', 'failed to decode saved list; starting empty', e);
      return [];
    }
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'items': _items.map((e) => e.toJson()).toList(),
      };

  bool contains(int id) => _items.any((e) => e.id == id);

  Future<void> add(AnimeEntry e) async {
    _items.removeWhere((x) => x.id == e.id);
    _items.add(e);
    AppLog.instance.i('store', 'add #${e.id} ${e.displayName}');
    await _save();
  }

  Future<void> insert(int index, AnimeEntry e) async {
    _items.removeWhere((x) => x.id == e.id);
    _items.insert(index.clamp(0, _items.length), e);
    await _save();
  }

  Future<int> remove(int id) async {
    final idx = _items.indexWhere((e) => e.id == id);
    AppLog.instance.i('store', 'remove #$id (index $idx)');
    if (idx >= 0) {
      _items.removeAt(idx);
      await _save();
    }
    return idx;
  }

  Future<int> removeEnded() async {
    final before = _items.length;
    final ended = _items.where((e) => e.isEnded).map((e) => '#${e.id} ${e.displayName} last=${e.lastAirDate}').toList();
    _items.removeWhere((e) => e.isEnded);
    AppLog.instance.i('store', 'removeEnded: $ended');
    await _save();
    return before - _items.length;
  }

  bool get hasEnded => _items.any((e) => e.isEnded);

  Future<void> _save() async {
    await _storage.writeJson(fileName, toJson());
    notifyListeners();
  }
}
