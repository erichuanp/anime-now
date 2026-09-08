import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'app_log.dart';
import 'app_storage.dart';
import 'bangumi_hosts.dart';
import 'key_vault.dart';

enum LlmProvider { deepseek, dashscope, volcengine, openai, anthropic, custom }

extension LlmProviderX on LlmProvider {
  String get label => switch (this) {
        LlmProvider.volcengine => 'Volcengine (Doubao)',
        LlmProvider.openai => 'OpenAI',
        LlmProvider.anthropic => 'Anthropic',
        LlmProvider.deepseek => 'DeepSeek',
        LlmProvider.dashscope => 'DashScope (Qwen)',
        LlmProvider.custom => '自定义 (OpenAI 兼容)',
      };

  bool get isCustom => this == LlmProvider.custom;

  String get defaultBaseUrl => switch (this) {
        LlmProvider.volcengine => 'https://ark.cn-beijing.volces.com/api/v3',
        LlmProvider.openai => 'https://api.openai.com/v1',
        LlmProvider.anthropic => 'https://api.anthropic.com/v1',
        LlmProvider.deepseek => 'https://api.deepseek.com',
        LlmProvider.dashscope => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
        LlmProvider.custom => '',
      };

  bool get isAnthropic => this == LlmProvider.anthropic;
}

enum TimeBasis { earliest, latest }

/// One provider's saved configuration. Switching providers keeps every
/// profile, so the key typed for DeepSeek is still there after visiting OpenAI.
class LlmProfile {
  LlmProfile({required this.baseUrl, this.model = '', this.models = const [], this.modelsValid = false, this.keyEnc = ''});

  String baseUrl;
  String model;
  List<String> models;
  bool modelsValid;
  String keyEnc; // encrypted (enc:v1:...) or '' when no key

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'model': model,
        'models': models,
        'modelsValid': modelsValid,
        'key': keyEnc,
      };

  factory LlmProfile.fromJson(LlmProvider p, Map<String, dynamic> j) => LlmProfile(
        baseUrl: (j['baseUrl'] as String?)?.trim().isNotEmpty == true ? (j['baseUrl'] as String).trim() : p.defaultBaseUrl,
        model: j['model'] as String? ?? '',
        models: (j['models'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        modelsValid: j['modelsValid'] as bool? ?? false,
        keyEnc: j['key'] as String? ?? '',
      );
}

/// All settings, persisted as one JSON file (config.json) in [AppStorage].
///
/// config.json v2 layout:
/// ```json
/// {
///   "configVersion": 2,
///   "llm": {"provider": "deepseek", "profiles": {"deepseek": {"baseUrl", "model", "models", "modelsValid", "key"}}},
///   "tavilyKey": "enc:v1:...",
///   "timeBasis": "earliest", "japaneseWeekday": true, "language": "zh", "notifications": false,
///   "bangumiSource": "official", "bangumiCustomApi": "", "bangumiCustomImage": ""
/// }
/// ```
/// v1 (flat `provider/baseUrl/model/models/modelsValid/llmKey`) is migrated on load.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._storage);

  static const fileName = 'config.json';
  static const configVersion = 2;
  final AppStorage _storage;

  LlmProvider _provider = LlmProvider.deepseek;
  final Map<LlmProvider, LlmProfile> _profiles = {};
  // Keys are held ONLY in encrypted form; decrypt at call time via llmKey()/tavilyKey().
  String _tavilyKeyEnc = '';
  TimeBasis _timeBasis = TimeBasis.earliest;
  bool _japaneseWeekday = true;
  String _language = defaultLanguage(); // zh | zht | en
  bool _notifications = false;
  BangumiSource _bangumiSource = BangumiSource.official;
  String _bangumiCustomApi = '';
  String _bangumiCustomImage = '';

  LlmProfile get _p => _profiles.putIfAbsent(_provider, () => LlmProfile(baseUrl: _provider.defaultBaseUrl));

  LlmProvider get provider => _provider;
  String get baseUrl => _p.baseUrl;
  String get model => _p.model;
  List<String> get models => _p.models;
  bool get modelsValid => _p.modelsValid;
  bool get hasLlmKey => _p.keyEnc.isNotEmpty;
  bool get hasTavilyKey => _tavilyKeyEnc.isNotEmpty;

  /// Decrypted on demand; never cached.
  Future<String> llmKey() => KeyVault.instance.decrypt(_p.keyEnc);
  Future<String> tavilyKey() => KeyVault.instance.decrypt(_tavilyKeyEnc);
  TimeBasis get timeBasis => _timeBasis;
  bool get japaneseWeekday => _japaneseWeekday;
  String get language => _language;
  bool get notifications => _notifications;
  BangumiSource get bangumiSource => _bangumiSource;
  String get bangumiCustomApi => _bangumiCustomApi;
  String get bangumiCustomImage => _bangumiCustomImage;

  bool get llmReady => hasLlmKey && model.isNotEmpty && baseUrl.trim().isNotEmpty;
  bool get tavilyReady => hasTavilyKey;

  static Future<AppSettings> load(AppStorage storage) async {
    final s = AppSettings._(storage);
    final j = await storage.readJson(fileName);
    var migrated = false;
    if (j != null) migrated = s._apply(j);
    AppLog.instance.d('settings', 'loaded from ${storage.path}: ${s._describe()}');
    await s._upgradeLegacyKeys();
    if (migrated) {
      AppLog.instance.i('settings', 'config migrated to v$configVersion');
      await s._save();
    }
    s._applyHosts();
    return s;
  }

  void _applyHosts() => BangumiHosts.instance.configure(
        source: _bangumiSource,
        customApi: _bangumiCustomApi,
        customImage: _bangumiCustomImage,
      );

  /// Plaintext keys from older configs are re-saved encrypted.
  Future<void> _upgradeLegacyKeys() async {
    final vault = KeyVault.instance;
    var changed = false;
    for (final prof in _profiles.values) {
      if (prof.keyEnc.isNotEmpty && !vault.isEncrypted(prof.keyEnc)) {
        prof.keyEnc = await vault.encrypt(prof.keyEnc);
        changed = true;
      }
    }
    if (_tavilyKeyEnc.isNotEmpty && !vault.isEncrypted(_tavilyKeyEnc)) {
      _tavilyKeyEnc = await vault.encrypt(_tavilyKeyEnc);
      changed = true;
    }
    if (changed) {
      AppLog.instance.i('settings', 'legacy plaintext keys re-encrypted');
      await _save();
    }
  }

  static LlmProvider _parseProvider(Object? name) =>
      LlmProvider.values.firstWhere((e) => e.name == name, orElse: () => LlmProvider.deepseek);

  /// Returns true when the file was in an older layout and should be rewritten.
  bool _apply(Map<String, dynamic> j) {
    var migrated = false;
    final llm = j['llm'];
    _profiles.clear();
    if (llm is Map<String, dynamic>) {
      _provider = _parseProvider(llm['provider']);
      final profs = llm['profiles'];
      if (profs is Map<String, dynamic>) {
        for (final e in profs.entries) {
          final prov = LlmProvider.values.where((p) => p.name == e.key).firstOrNull;
          if (prov != null && e.value is Map<String, dynamic>) {
            _profiles[prov] = LlmProfile.fromJson(prov, e.value as Map<String, dynamic>);
          }
        }
      }
    } else {
      // v1: flat fields for the single active provider.
      migrated = true;
      _provider = _parseProvider(j['provider']);
      final base = (j['baseUrl'] as String?)?.trim();
      _profiles[_provider] = LlmProfile(
        baseUrl: (base == null || base.isEmpty) ? _provider.defaultBaseUrl : base,
        model: j['model'] as String? ?? '',
        models: (j['models'] as List<dynamic>? ?? const []).whereType<String>().toList(),
        modelsValid: j['modelsValid'] as bool? ?? false,
        keyEnc: j['llmKey'] as String? ?? '',
      );
    }
    _tavilyKeyEnc = j['tavilyKey'] as String? ?? '';
    final b = j['timeBasis'] as String?;
    _timeBasis = TimeBasis.values.firstWhere((e) => e.name == b, orElse: () => TimeBasis.earliest);
    _japaneseWeekday = j['japaneseWeekday'] as bool? ?? true;
    final lang = j['language'] as String?;
    _language = (lang == 'zh' || lang == 'zht' || lang == 'en') ? lang! : defaultLanguage();
    _notifications = j['notifications'] as bool? ?? false;
    final src = j['bangumiSource'] as String?;
    _bangumiSource = BangumiSource.values.firstWhere((e) => e.name == src, orElse: () => BangumiSource.official);
    _bangumiCustomApi = (j['bangumiCustomApi'] as String?)?.trim() ?? '';
    _bangumiCustomImage = (j['bangumiCustomImage'] as String?)?.trim() ?? '';
    if ((j['configVersion'] as num?)?.toInt() != configVersion) migrated = true;
    return migrated;
  }

  Map<String, dynamic> toJson() => {
        'configVersion': configVersion,
        'llm': {
          'provider': _provider.name,
          'profiles': {for (final e in _profiles.entries) e.key.name: e.value.toJson()},
        },
        'tavilyKey': _tavilyKeyEnc,
        'timeBasis': _timeBasis.name,
        'japaneseWeekday': _japaneseWeekday,
        'language': _language,
        'notifications': _notifications,
        'bangumiSource': _bangumiSource.name,
        'bangumiCustomApi': _bangumiCustomApi,
        'bangumiCustomImage': _bangumiCustomImage,
      };

  String _keyState(String enc) => enc.isEmpty ? 'none' : (KeyVault.instance.isEncrypted(enc) ? 'encrypted' : 'PLAINTEXT-legacy');

  String _describe() => 'provider=${_provider.name} profiles=[${_profiles.entries.map((e) => '${e.key.name}: base=${e.value.baseUrl} model=${e.value.model} models=${e.value.models.length} valid=${e.value.modelsValid} key=${_keyState(e.value.keyEnc)}').join('; ')}] '
      'tavilyKey=${_keyState(_tavilyKeyEnc)} basis=${_timeBasis.name} jpWeekday=$_japaneseWeekday lang=$_language notifications=$_notifications '
      'bangumi=${_bangumiSource.name} customApi=$_bangumiCustomApi customImg=$_bangumiCustomImage';

  Future<void> _save() async {
    await _storage.writeJson(fileName, toJson());
    notifyListeners();
  }

  static String defaultLanguage() {
    final l = PlatformDispatcher.instance.locale;
    if (l.languageCode != 'zh') return 'en';
    if (l.scriptCode == 'Hans') return 'zh';
    if (l.scriptCode == 'Hant') return 'zht';
    return (l.countryCode == 'CN' || l.countryCode == 'SG') ? 'zh' : 'zht';
  }

  Locale get localeOverride => switch (_language) {
        'zh' => const Locale('zh', 'CN'),
        'zht' => const Locale('zh', 'TW'),
        _ => const Locale('en'),
      };

  /// Switches the active profile; the previous provider's key/model stay saved.
  Future<void> setProvider(LlmProvider p) async {
    if (p == _provider) return;
    AppLog.instance.i('settings', 'provider ${_provider.name} → ${p.name}');
    _provider = p;
    _p; // make sure the profile exists
    await _save();
  }

  Future<void> setBaseUrl(String url) async {
    _p.baseUrl = url.trim();
    AppLog.instance.d('settings', 'baseUrl[${_provider.name}] = ${_p.baseUrl}');
    await _save();
  }

  /// Any key change invalidates the model list until it is fetched again.
  Future<void> setLlmKey(String key) async {
    final plain = key.trim();
    final prof = _p;
    prof.keyEnc = await KeyVault.instance.encrypt(plain); // encrypted the moment it is stored
    AppLog.instance.i('settings', 'llm key[${_provider.name}] ${plain.isEmpty ? 'cleared' : 'set (stored encrypted)'}; models invalidated');
    prof.modelsValid = false;
    prof.model = '';
    prof.models = const [];
    await _save();
  }

  /// Saves a freshly fetched list and clears the current model (the user
  /// picks again from the list or types one).
  Future<void> setModels(List<String> models) async {
    final prof = _p;
    prof.models = models;
    prof.modelsValid = true;
    prof.model = '';
    AppLog.instance.i('settings', 'model list[${_provider.name}] saved (${models.length}); model cleared');
    await _save();
  }

  Future<void> setModel(String model) async {
    final prof = _p;
    prof.model = model;
    AppLog.instance.i('settings', 'model[${_provider.name}] = $model');
    if (!prof.models.contains(model) && model.isNotEmpty) {
      prof.models = [model, ...prof.models];
      prof.modelsValid = true;
    }
    await _save();
  }

  Future<void> setTavilyKey(String key) async {
    final plain = key.trim();
    _tavilyKeyEnc = await KeyVault.instance.encrypt(plain);
    AppLog.instance.d('settings', 'tavily key ${plain.isEmpty ? 'cleared' : 'set (stored encrypted)'}');
    await _save();
  }

  Future<void> setTimeBasis(TimeBasis b) async {
    _timeBasis = b;
    AppLog.instance.i('settings', 'timeBasis = ${b.name}');
    await _save();
  }

  Future<void> setJapaneseWeekday(bool v) async {
    _japaneseWeekday = v;
    AppLog.instance.i('settings', 'japaneseWeekday = $v');
    await _save();
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    AppLog.instance.i('settings', 'language = $lang');
    await _save();
  }

  /// Only ever true while the system notification permission is granted
  /// (NotificationService.sync turns it off again otherwise).
  Future<void> setNotifications(bool v) async {
    if (v == _notifications) return;
    _notifications = v;
    AppLog.instance.i('settings', 'notifications = $v');
    await _save();
  }

  Future<void> setBangumiSource(BangumiSource src) async {
    _bangumiSource = src;
    AppLog.instance.i('settings', 'bangumiSource = ${src.name}');
    _applyHosts();
    await _save();
  }

  /// Saves the custom proxy and switches to it.
  Future<void> setBangumiCustom({required String api, required String image}) async {
    _bangumiCustomApi = api.trim();
    _bangumiCustomImage = image.trim();
    _bangumiSource = BangumiSource.custom;
    AppLog.instance.i('settings', 'bangumiSource = custom api=$_bangumiCustomApi image=$_bangumiCustomImage');
    _applyHosts();
    await _save();
  }
}
