import 'package:flutter/foundation.dart';

import 'app_log.dart';

/// Where Bangumi requests go: official api.bgm.tv, the 番时 mirror
/// (our own nginx reverse proxy on the hk VPS, published through a Cloudflare
/// Tunnel as bgmapi/bgmimg.erichuanp.com), or the user's own reverse proxy.
enum BangumiSource { official, mirror, custom }

class BangumiEndpoint {
  final String id;
  final String api; // e.g. https://api.bgm.tv  (no trailing slash)
  final String image; // e.g. https://lain.bgm.tv (no trailing slash)
  const BangumiEndpoint(this.id, this.api, this.image);

  static const official = BangumiEndpoint('official', 'https://api.bgm.tv', 'https://lain.bgm.tv');
  static const mirror = BangumiEndpoint('mirror', 'https://bgmapi.erichuanp.com', 'https://bgmimg.erichuanp.com');

  String get apiHost => Uri.tryParse(api)?.host ?? api;

  @override
  String toString() => '$id($apiHost)';
}

/// Single source of truth for the active Bangumi endpoint. Stored cover URLs
/// always point at lain.bgm.tv (canonical form); [display] rewrites them for
/// the active endpoint at render time, so switching sources never touches
/// anime.json.
class BangumiHosts extends ChangeNotifier {
  BangumiHosts();
  static final instance = BangumiHosts();

  static final _log = AppLog.instance;

  BangumiSource _source = BangumiSource.official;
  BangumiEndpoint _custom = const BangumiEndpoint('custom', '', '');
  BangumiEndpoint _active = BangumiEndpoint.official;

  BangumiSource get source => _source;
  BangumiEndpoint get active => _active;
  BangumiEndpoint get custom => _custom;

  void configure({required BangumiSource source, required String customApi, required String customImage}) {
    _source = source;
    final api = _trim(customApi);
    final img = _trim(customImage);
    _custom = BangumiEndpoint('custom', api, img.isEmpty ? BangumiEndpoint.official.image : img);
    _active = switch (source) {
      BangumiSource.official => BangumiEndpoint.official,
      BangumiSource.mirror => BangumiEndpoint.mirror,
      BangumiSource.custom => _custom.api.isEmpty ? BangumiEndpoint.official : _custom,
    };
    _log.i('bangumi.hosts', 'source=${source.name} active=$_active image=${_active.image}');
    notifyListeners();
  }

  static String _trim(String s) {
    var t = s.trim();
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    if (t.isNotEmpty && !t.contains('://')) t = 'https://$t';
    return t;
  }

  /// Builds an absolute API URL for the active endpoint.
  Uri api(String pathAndQuery) => Uri.parse('${_active.api}$pathAndQuery');

  // ---- image URL rewriting ---------------------------------------------

  static const _lain = 'https://lain.bgm.tv';

  List<String> get _knownImageHosts => [
        BangumiEndpoint.mirror.image,
        if (_custom.image.isNotEmpty) _custom.image,
      ];

  /// Covers are shown at 72×100 dp, so the 400 px resize is plenty and about
  /// a quarter of the size of the original `/pic/cover/l/` file.
  static const _thumb = '/r/400';
  static final _resized = RegExp(r'^/r/\d+(/pic/)');

  /// Any known proxy image host → lain.bgm.tv, and any `/r/<n>/` resize prefix
  /// dropped, so stored data is host- and size-agnostic.
  String canonical(String url) {
    var u = url;
    for (final h in _knownImageHosts) {
      if (h != _lain && u.startsWith('$h/')) {
        u = _lain + u.substring(h.length);
        break;
      }
    }
    if (u.startsWith('$_lain/')) {
      final path = u.substring(_lain.length).replaceFirstMapped(_resized, (m) => m.group(1)!);
      u = _lain + path;
    }
    return u;
  }

  /// Canonical lain.bgm.tv URL → the active endpoint's image host, as a
  /// `/r/400` thumbnail for `/pic/` covers.
  String display(String url) {
    if (!url.startsWith('$_lain/')) return url;
    final img = _active.image.isEmpty ? _lain : _active.image;
    var path = url.substring(_lain.length);
    if (path.startsWith('/pic/')) path = '$_thumb$path';
    return img + path;
  }
}
