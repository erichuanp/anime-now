import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_log.dart';

class TavilyException implements Exception {
  final String message;
  TavilyException(this.message);
  @override
  String toString() => 'Tavily: $message';
}

class TavilyHit {
  final String title;
  final String url;
  final String content;
  TavilyHit({required this.title, required this.url, required this.content});
}

class TavilyResponse {
  final String? answer;
  final List<TavilyHit> results;
  TavilyResponse({this.answer, required this.results});
}

class TavilyApi {
  TavilyApi(this.apiKey, {http.Client? client}) : _client = client ?? LoggingClient(tag: 'http.tavily');

  final String apiKey;
  final http.Client _client;
  int calls = 0;

  Future<TavilyResponse> search(String query, {int maxResults = 6}) async {
    calls++;
    final res = await _client
        .post(
          Uri.parse('https://api.tavily.com/search'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'query': query,
            'search_depth': 'basic',
            'max_results': maxResults,
            'include_answer': true,
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw TavilyException('API key rejected (${res.statusCode})');
    }
    if (res.statusCode == 432 || res.statusCode == 429) {
      throw TavilyException('quota exceeded or rate limited (${res.statusCode})');
    }
    if (res.statusCode != 200) {
      throw TavilyException('HTTP ${res.statusCode}: ${res.body}');
    }
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final results = (j['results'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .map((e) => TavilyHit(
              title: e['title'] as String? ?? '',
              url: e['url'] as String? ?? '',
              content: e['content'] as String? ?? '',
            ))
        .toList();
    AppLog.instance.d('tavily', 'query "$query" → ${results.length} results, answer=${j['answer']}\n'
        '${results.map((r) => '  - ${r.title} <${r.url}>\n    ${r.content}').join('\n')}');
    return TavilyResponse(answer: j['answer'] as String?, results: results);
  }
}
