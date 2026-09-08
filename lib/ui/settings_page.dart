import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/strings.dart';
import '../main.dart';
import '../services/anime_store.dart';
import '../services/app_log.dart';
import '../services/bangumi_hosts.dart';
import '../services/cover_cache.dart';
import '../services/llm_client.dart';
import '../services/notifications.dart';
import '../services/settings.dart';
import '../util/toast.dart';
import 'storage_dialogs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _llmKey;
  late final TextEditingController _tavilyKey;
  late final TextEditingController _baseUrl;
  late final TextEditingController _modelCtrl;
  final FocusNode _modelFocus = FocusNode();
  final FocusNode _tavilyFocus = FocusNode();
  bool _fetching = false;
  String? _fetchError;

  /// True once the key in the text field differs from the stored (validated) key.
  bool _keyDirty = false;
  int _lastKeyLen = 0;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppSettings>();
    // Stored keys are never loaded into the UI; the fields start empty and
    // show dots as a hint when a key exists.
    _llmKey = TextEditingController();
    _tavilyKey = TextEditingController();
    _tavilyFocus.addListener(() => setState(() {}));
    _baseUrl = TextEditingController(text: s.baseUrl);
    _modelCtrl = TextEditingController(text: s.model);
  }

  @override
  void dispose() {
    _llmKey.dispose();
    _tavilyKey.dispose();
    _baseUrl.dispose();
    _modelCtrl.dispose();
    _modelFocus.dispose();
    _tavilyFocus.dispose();
    super.dispose();
  }

  void _onKeyChanged(String value) {
    // Backspace clears the whole key.
    if (value.length < _lastKeyLen) {
      _llmKey.clear();
      value = '';
    }
    _lastKeyLen = value.length;
    setState(() {
      _keyDirty = true;
      _fetchError = null;
    });
  }

  Future<void> _fetchModels() async {
    final settings = context.read<AppSettings>();
    final s = S.of(context);
    var key = _llmKey.text.trim();
    setState(() {
      _fetching = true;
      _fetchError = null;
    });
    await settings.setBaseUrl(_baseUrl.text);
    if (key.isNotEmpty) {
      await settings.setLlmKey(key); // encrypted at rest
    } else {
      key = await settings.llmKey(); // decrypt only for this call
    }
    if (key.isEmpty) {
      if (mounted) setState(() => _fetching = false);
      return;
    }
    try {
      final client = LlmClient(provider: settings.provider, baseUrl: settings.baseUrl, apiKey: key);
      final models = await client.listModels();
      if (models.isEmpty) throw LlmException('empty list');
      await settings.setModels(models); // clears the current model name
      _modelCtrl.clear();
      if (mounted) setState(() => _keyDirty = false);
    } catch (e) {
      AppLog.instance.w('settings', 'fetch models failed: $e');
      if (mounted) setState(() => _fetchError = '${s.fetchFailed}\n$e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _persistKeyIfDirty(AppSettings settings) async {
    if (_keyDirty && _llmKey.text.trim().isNotEmpty) {
      await settings.setBaseUrl(_baseUrl.text);
      await settings.setLlmKey(_llmKey.text.trim());
      _keyDirty = false;
    }
  }

  Future<void> _showTavilyGuide(BuildContext context) {
    final s = S.of(context);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8FB),
        title: Text(s.tavilyGuideTitle, style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in s.tavilyGuideSteps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(step, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(s.close)),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => launchUrl(Uri.parse('https://app.tavily.com/home'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(s.openTavily),
          ),
        ],
      ),
    );
  }

  /// Custom Bangumi proxy: API mirror + image mirror, cancel / save.
  Future<void> _showBangumiCustomDialog(BuildContext context, AppSettings settings) async {
    final s = S.of(context);
    final api = TextEditingController(text: settings.bangumiCustomApi);
    final img = TextEditingController(text: settings.bangumiCustomImage);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFFFFF8FB),
          title: Text(s.bangumiCustom, style: const TextStyle(fontSize: 17)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: api,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (_) => setDialogState(() {}),
                decoration: InputDecoration(labelText: s.bangumiCustomApi, hintText: 'https://api.example.com', prefixIcon: const Icon(Icons.dns_outlined)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: img,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(labelText: s.bangumiCustomImage, hintText: 'https://img.example.com', prefixIcon: const Icon(Icons.image_outlined)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(s.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: api.text.trim().isEmpty ? null : () => Navigator.of(ctx).pop(true),
              child: Text(s.save),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await settings.setBangumiCustom(api: api.text, image: img.text);
    }
    api.dispose();
    img.dispose();
  }

  /// Editable model name + a dropdown arrow that lists fetched models.
  Widget _modelBox(S s, AppSettings settings) {
    final listReady = settings.modelsValid && !_keyDirty && settings.models.isNotEmpty;
    if (_modelCtrl.text != settings.model && !_modelFocus.hasFocus) _modelCtrl.text = settings.model;
    return TextField(
      controller: _modelCtrl,
      focusNode: _modelFocus,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: s.model,
        suffixIcon: listReady
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.arrow_drop_down),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                tooltip: s.model,
                onSelected: (m) {
                  _modelCtrl.text = m;
                  settings.setModel(m);
                },
                itemBuilder: (_) => [
                  for (final m in settings.models) PopupMenuItem(value: m, child: Text(m)),
                ],
              )
            : null,
      ),
      onChanged: (v) async {
        await _persistKeyIfDirty(settings); // typing a model implies the key is final
        await settings.setModel(v.trim());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final settings = context.watch<AppSettings>();
    final store = context.watch<AnimeStore>();
    _lastKeyLen = _llmKey.text.length;
    final showVpnNote = s.showGfwNotice && (settings.provider == LlmProvider.openai || settings.provider == LlmProvider.anthropic);
    final canFetch = !_fetching && (_llmKey.text.trim().isNotEmpty || settings.hasLlmKey) && _baseUrl.text.trim().isNotEmpty;
    const dots = '●●●●●●●●●●●●●●●●●●●●';

    return Scaffold(
      appBar: AppBar(title: Text(s.tabSettings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _SectionTitle(s.llmSection),
          // 1. Provider
          InputDecorator(
            decoration: InputDecoration(labelText: s.provider, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<LlmProvider>(
                value: settings.provider,
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: [
                  for (final p in LlmProvider.values)
                    DropdownMenuItem(value: p, child: Text(p.isCustom ? s.customProvider : p.label)),
                ],
                onChanged: (p) async {
                  if (p == null) return;
                  await settings.setProvider(p);
                  // Each provider is its own profile: restore its saved URL/model,
                  // the key field stays empty and shows dots when a key exists.
                  _llmKey.clear();
                  _baseUrl.text = settings.baseUrl;
                  _modelCtrl.text = settings.model;
                  setState(() {
                    _keyDirty = false;
                    _fetchError = null;
                  });
                },
              ),
            ),
          ),
          if (showVpnNote)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Row(children: [
                const Icon(Icons.vpn_lock, size: 14, color: Color(0xFFEF6C00)),
                const SizedBox(width: 4),
                Text(s.needVpn, style: const TextStyle(fontSize: 11, color: Color(0xFFEF6C00))),
              ]),
            ),
          const SizedBox(height: 12),
          // 2. Base URL (changes with provider)
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            onSubmitted: settings.setBaseUrl,
            onTapOutside: (_) {
              if (_baseUrl.text.trim() != settings.baseUrl) settings.setBaseUrl(_baseUrl.text);
            },
            decoration: InputDecoration(
              labelText: s.baseUrl,
              hintText: settings.provider.isCustom ? 'https://example.com/v1' : settings.provider.defaultBaseUrl,
              prefixIcon: const Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 12),
          // 3. API key (dots)
          TextField(
            key: ValueKey('llm-key-${settings.provider.name}'),
            controller: _llmKey,
            obscureText: true,
            obscuringCharacter: '●',
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onKeyChanged,
            decoration: InputDecoration(
              labelText: s.apiKey,
              hintText: settings.hasLlmKey && _llmKey.text.isEmpty ? dots : null,
              hintStyle: const TextStyle(color: Colors.black87),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: settings.hasLlmKey
                  ? IconButton(
                      tooltip: s.clearKey,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await settings.setLlmKey('');
                        _llmKey.clear();
                        setState(() => _keyDirty = false);
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          // 4. Model box + fetch button
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _modelBox(s, settings)),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: canFetch ? _fetchModels : null,
                child: _fetching
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(s.fetchModels),
              ),
            ],
          ),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_fetchError!, style: const TextStyle(color: Color(0xFFC62828), fontSize: 12)),
            ),

          const SizedBox(height: 16),
          _SectionTitle(s.searchSection),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: InkWell(
              onTap: () => _showTavilyGuide(context),
              child: Text(
                s.tavilyKey,
                style: const TextStyle(
                  color: AppColors.accent,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.accent,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          TextField(
            controller: _tavilyKey,
            focusNode: _tavilyFocus,
            obscureText: true,
            obscuringCharacter: '●',
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) {
              if (v.trim().isNotEmpty) settings.setTavilyKey(v);
            },
            decoration: InputDecoration(
              // Identical to the LLM key field: floating label, dots when focused and a key is stored.
              labelText: s.tavilyKey,
              hintText: settings.hasTavilyKey && _tavilyKey.text.isEmpty ? dots : null,
              hintStyle: const TextStyle(color: Colors.black87),
              prefixIcon: const Icon(Icons.travel_explore),
              suffixIcon: settings.hasTavilyKey
                  ? IconButton(
                      tooltip: s.clearKey,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 28),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await settings.setTavilyKey('');
                        _tavilyKey.clear();
                        setState(() {});
                      },
                    )
                  : null,
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle(s.notificationsSection),
          SwitchListTile(
            value: settings.notifications,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            title: Text(s.pushNotifications),
            subtitle: Text(s.pushNotificationsHelp),
            onChanged: (v) async {
              if (!v) {
                await settings.setNotifications(false);
                return;
              }
              // First switch-on asks for the system permission; the switch
              // only shows ON while that permission is granted.
              final ok = await NotificationService.instance.requestPermission();
              if (!context.mounted) return;
              if (ok) {
                await settings.setNotifications(true);
              } else {
                showToast(context, s.notifDenied);
              }
            },
          ),
          const SizedBox(height: 4),
          Text(s.timeBasis, style: const TextStyle(fontWeight: FontWeight.w500)),
          RadioGroup<TimeBasis>(
            groupValue: settings.timeBasis,
            onChanged: (v) => v == null ? null : settings.setTimeBasis(v),
            child: Column(
              children: [
                _RadioRow<TimeBasis>(value: TimeBasis.earliest, label: s.basisEarliest, onTap: () => settings.setTimeBasis(TimeBasis.earliest)),
                _RadioRow<TimeBasis>(value: TimeBasis.latest, label: s.basisLatest, onTap: () => settings.setTimeBasis(TimeBasis.latest)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            value: settings.japaneseWeekday,
            activeThumbColor: AppColors.accent,
            contentPadding: EdgeInsets.zero,
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            title: Text(s.japaneseWeekday),
            subtitle: Text(s.japaneseWeekdayHelp),
            onChanged: settings.setJapaneseWeekday,
          ),
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(labelText: s.language, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: settings.language,
                isExpanded: true,
                isDense: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: [
                  DropdownMenuItem(value: 'zh', child: Text(s.langZhHans)),
                  DropdownMenuItem(value: 'zht', child: Text(s.langZhHant)),
                  DropdownMenuItem(value: 'en', child: Text(s.langEn)),
                ],
                onChanged: (v) => v == null ? null : settings.setLanguage(v),
              ),
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle(s.maintenanceSection),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC62828)),
            onPressed: store.hasEnded
                ? () async {
                    final covers = context.read<CoverCache>();
                    final gone = store.items.where((e) => e.isEnded).map((e) => e.coverUrl).toList();
                    final n = await store.removeEnded();
                    // Those shows are over for good: drop their cached covers too.
                    for (final c in gone) {
                      await covers.evict(c);
                    }
                    if (context.mounted) {
                      showToast(context, s.removedCount(n));
                    }
                  }
                : null,
            icon: const Icon(Icons.delete_sweep_outlined),
            label: Text(s.removeEnded),
          ),

          const SizedBox(height: 16),
          _SectionTitle(s.bangumiSection),
          RadioGroup<BangumiSource>(
            groupValue: settings.bangumiSource,
            onChanged: (v) {
              if (v == null) return;
              if (v == BangumiSource.custom) {
                _showBangumiCustomDialog(context, settings);
              } else {
                settings.setBangumiSource(v);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RadioRow<BangumiSource>(value: BangumiSource.official, label: s.bangumiOfficial, onTap: () => settings.setBangumiSource(BangumiSource.official)),
                if (s.showGfwNotice) _SubNote(s.needVpn, icon: Icons.vpn_lock, color: const Color(0xFFEF6C00)),
                _RadioRow<BangumiSource>(value: BangumiSource.mirror, label: s.bangumiMirror, onTap: () => settings.setBangumiSource(BangumiSource.mirror)),
                _SubNote(s.bangumiMirrorNotice),
                _RadioRow<BangumiSource>(
                  value: BangumiSource.custom,
                  label: s.bangumiCustom,
                  link: true,
                  onTap: () => _showBangumiCustomDialog(context, settings),
                ),
                if (settings.bangumiSource == BangumiSource.custom && settings.bangumiCustomApi.isNotEmpty)
                  _SubNote(settings.bangumiCustomApi + (settings.bangumiCustomImage.isEmpty ? '' : '  ·  ${settings.bangumiCustomImage}')),
              ],
            ),
          ),

          const SizedBox(height: 16),
          _SectionTitle(s.backupSection),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => downloadAnimeBackup(context),
            icon: const Icon(Icons.save_alt_outlined, size: 18),
            label: Text(s.backupAnime),
          ),

          const SizedBox(height: 16),
          _SectionTitle(s.about),
          _AboutRow(label: s.aboutVersion, value: '${s.appName} $appVersion'),
          _AboutRow(label: s.aboutAuthor, value: 'erichuanp', url: 'https://github.com/erichuanp'),
          _AboutRow(label: s.aboutProject, value: 'github.com/erichuanp/anime-now', url: 'https://github.com/erichuanp/anime-now'),
          _AboutRow(label: s.aboutLicense, value: 'MIT License © 2026 erichuanp', url: 'https://github.com/erichuanp/anime-now/blob/main/LICENSE'),
          const SizedBox(height: 6),
          Text(s.aboutText, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}

/// One line of the About section; tapping a linked value opens it in the browser.
class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value, this.url});
  final String label;
  final String value;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      value,
      style: TextStyle(
        fontSize: 13,
        color: url != null ? AppColors.accent : Colors.black87,
        decoration: url != null ? TextDecoration.underline : null,
        decorationColor: AppColors.accent,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 72, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
          Expanded(
            child: url == null
                ? text
                : InkWell(onTap: () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication), child: text),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.accent)),
      );
}

/// Tight radio row (~30dp) instead of the 48dp RadioListTile.
class _RadioRow<T> extends StatelessWidget {
  const _RadioRow({required this.value, required this.label, required this.onTap, this.link = false});
  final T value;
  final String label;
  final VoidCallback onTap;
  /// Pink underlined label (opens something instead of just selecting).
  final bool link;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              Radio<T>(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: link
                    ? const TextStyle(
                        fontSize: 14,
                        color: AppColors.accent,
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.accent,
                        fontWeight: FontWeight.w500,
                      )
                    : const TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
      );
}

/// Small grey note under a radio row, aligned with its label.
class _SubNote extends StatelessWidget {
  const _SubNote(this.text, {this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 34, bottom: 4),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color ?? Colors.grey.shade600), const SizedBox(width: 4)],
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: color ?? Colors.grey.shade600))),
        ]),
      );
}
