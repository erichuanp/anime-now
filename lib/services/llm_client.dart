import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';
import 'settings.dart' show LlmProvider, LlmProviderX;

class LlmException implements Exception {
  final String message;
  LlmException(this.message);
  @override
  String toString() => 'LLM: $message';
}

/// Thin HTTP client covering OpenAI-compatible providers and Anthropic.
class LlmClient {
  LlmClient({
    required this.provider,
    required this.baseUrl,
    required this.apiKey,
    this.model = '',
    http.Client? client,
  }) : _client = client ?? LoggingClient(tag: 'http.llm');

  static final _log = AppLog.instance;

  final LlmProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;
  int calls = 0;

  String get _base {
    final b = baseUrl.trim();
    if (b.isEmpty) throw LlmException('Base URL is empty');
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  Map<String, String> get _headers => provider.isAnthropic
      ? {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        }
      : {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        };

  Future<List<String>> listModels() async {
    calls++;
    final url = provider.isAnthropic ? '$_base/models?limit=1000' : '$_base/models';
    final res = await _client
        .get(Uri.parse(url), headers: _headers)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw LlmException('API key rejected (${res.statusCode})');
    }
    if (res.statusCode != 200) {
      throw LlmException('HTTP ${res.statusCode}: ${_short(res.body)}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes));
    final data = j is Map<String, dynamic> ? j['data'] : null;
    if (data is! List) throw LlmException('unexpected model list response');
    final ids = <String>[];
    for (final m in data) {
      if (m is Map<String, dynamic>) {
        final id = m['id'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    ids.sort();
    _log.d('llm', 'models from ${provider.name} ($_base): ${ids.length} → $ids');
    return ids;
  }

  /// Single-turn completion; returns the assistant text.
  /// [maxTokens] must leave room for reasoning models (DeepSeek v4, doubao
  /// thinking, Claude) whose hidden reasoning counts against the budget.
  Future<String> complete({required String system, required String user, int maxTokens = 16000}) async {
    if (model.isEmpty) throw LlmException('no model selected');
    calls++;
    _log.d('llm', 'complete() provider=${provider.name} model=$model maxTokens=$maxTokens\n'
        '----- system -----\n$system\n----- user -----\n$user');
    final sw = Stopwatch()..start();
    final text = await _completeRaw(system: system, user: user, maxTokens: maxTokens);
    _log.d('llm', 'reply in ${sw.elapsedMilliseconds} ms (${text.length} chars):\n$text');
    return text;
  }

  Future<String> _completeRaw({required String system, required String user, required int maxTokens}) async {
    if (provider.isAnthropic) {
      final res = await _client
          .post(
            Uri.parse('$_base/messages'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'max_tokens': maxTokens,
              'system': system,
              'messages': [
                {'role': 'user', 'content': user},
              ],
            }),
          )
          .timeout(const Duration(seconds: 300));
      if (res.statusCode != 200) {
        throw LlmException('HTTP ${res.statusCode}: ${_short(res.body)}');
      }
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (j['stop_reason'] == 'refusal') {
        throw LlmException('the model refused the request');
      }
      final content = j['content'] as List<dynamic>? ?? [];
      final buf = StringBuffer();
      for (final block in content) {
        final b = block as Map<String, dynamic>;
        if (b['type'] == 'text') buf.write(b['text'] as String? ?? '');
      }
      return buf.toString();
    }

    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'temperature': 0.2,
      'max_tokens': maxTokens,
    };
    // This is a plain extraction task: turn hidden reasoning off where the
    // provider has a switch, otherwise thinking models burn the whole budget.
    final noThink = _noThinkingParams();
    body.addAll(noThink);
    var res = await _client
        .post(Uri.parse('$_base/chat/completions'), headers: _headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 300));
    if (res.statusCode == 400 && noThink.isNotEmpty) {
      // Provider/model does not accept the switch: retry without it.
      _log.w('llm', '400 with no-thinking params (${noThink.keys}); retrying without: ${_short(res.body)}');
      noThink.keys.forEach(body.remove);
      res = await _client
          .post(Uri.parse('$_base/chat/completions'), headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 300));
    }
    if (res.statusCode != 200) {
      throw LlmException('HTTP ${res.statusCode}: ${_short(res.body)}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final choices = j['choices'] as List<dynamic>? ?? [];
    if (choices.isEmpty) throw LlmException('empty response');
    final choice = choices.first as Map<String, dynamic>;
    final msg = choice['message'] as Map<String, dynamic>?;
    final finish = choice['finish_reason'] as String?;
    final content = msg?['content'];
    String text;
    if (content is String) {
      text = content;
    } else if (content is List) {
      text = content.whereType<Map<String, dynamic>>().map((e) => e['text'] as String? ?? '').join();
    } else {
      throw LlmException('unexpected response shape');
    }
    if (text.trim().isEmpty) {
      // Reasoning models (DeepSeek v4, doubao-thinking…) may burn the whole
      // budget on reasoning_content and return an empty answer.
      final reasoning = msg?['reasoning_content'];
      final usage = j['usage'] as Map<String, dynamic>?;
      _log.w('llm', 'empty content, finish_reason=$finish, usage=$usage');
      if (reasoning is String && reasoning.contains('{')) {
        _log.i('llm', 'falling back to JSON found inside reasoning_content');
        return reasoning;
      }
      if (finish == 'length') {
        throw LlmException('reply truncated: the model used all $maxTokens tokens on reasoning. '
            'Pick a non-thinking model or raise the limit.');
      }
    }
    return text;
  }

  Map<String, dynamic> _noThinkingParams() => switch (provider) {
        LlmProvider.deepseek => {'thinking': {'type': 'disabled'}},
        LlmProvider.volcengine => {'thinking': {'type': 'disabled'}},
        LlmProvider.dashscope => {'enable_thinking': false},
        _ => const {},
      };

  /// Extracts the first JSON object from a model reply (tolerates code fences).
  static Map<String, dynamic> parseJsonObject(String text) {
    var t = text.trim();
    t = t.replaceAll(RegExp(r'^```(?:json)?', multiLine: true), '').replaceAll('```', '');
    var start = t.indexOf('{');
    final end = t.lastIndexOf('}');
    // Prefer the last top-level object: reasoning text may contain drafts first.
    final lastStart = t.lastIndexOf('\n{');
    if (lastStart >= 0 && lastStart + 1 < end) start = lastStart + 1;
    if (start < 0 || end <= start) {
      _log.w('llm', 'no JSON object found in reply: $text');
      throw LlmException('no JSON object in reply');
    }
    final slice = t.substring(start, end + 1);
    late final dynamic decoded;
    try {
      decoded = jsonDecode(slice);
    } catch (e) {
      _log.w('llm', 'JSON decode failed ($e): $slice');
      rethrow;
    }
    if (decoded is! Map<String, dynamic>) throw LlmException('reply is not a JSON object');
    return decoded;
  }

  static String _short(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;
}
