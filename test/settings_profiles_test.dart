import 'dart:convert';
import 'dart:io';

import 'package:anime_now/services/app_storage.dart';
import 'package:anime_now/services/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('anime_now_cfg'));
  tearDown(() async => dir.delete(recursive: true));

  test('v1 flat config migrates into a per-provider profile and is rewritten as v2', () async {
    final storage = AppStorage.at(dir);
    await storage.writeJson('config.json', {
      'provider': 'deepseek',
      'baseUrl': 'https://api.deepseek.com',
      'model': 'deepseek-chat',
      'models': ['deepseek-chat', 'deepseek-reasoner'],
      'modelsValid': true,
      'llmKey': 'sk-plain-legacy',
      'tavilyKey': 'tvly-plain',
      'language': 'zht',
      'storagePromptDismissed': true,
    });
    final s = await AppSettings.load(storage);
    expect(s.provider, LlmProvider.deepseek);
    expect(s.baseUrl, 'https://api.deepseek.com');
    expect(s.model, 'deepseek-chat');
    expect(s.models.length, 2);
    expect(s.modelsValid, isTrue);
    expect(await s.llmKey(), 'sk-plain-legacy');
    expect(await s.tavilyKey(), 'tvly-plain');
    expect(s.language, 'zht');
    expect(s.notifications, isFalse);

    final written = jsonDecode(await storage.file('config.json').readAsString()) as Map<String, dynamic>;
    expect(written['configVersion'], 2);
    expect(written.containsKey('llmKey'), isFalse);
    expect(written.containsKey('storagePromptDismissed'), isFalse);
    final prof = (written['llm']['profiles'] as Map)['deepseek'] as Map;
    expect((prof['key'] as String).startsWith('enc:v1:'), isTrue); // never plaintext on disk
    expect((written['tavilyKey'] as String).startsWith('enc:v1:'), isTrue);
  });

  test('switching providers keeps each profile (key, model, base url)', () async {
    final storage = AppStorage.at(dir);
    final s = await AppSettings.load(storage);
    await s.setProvider(LlmProvider.deepseek);
    await s.setLlmKey('sk-deepseek');
    await s.setModel('deepseek-chat');
    await s.setProvider(LlmProvider.openai);
    expect(s.hasLlmKey, isFalse);
    expect(s.baseUrl, LlmProvider.openai.defaultBaseUrl);
    await s.setLlmKey('sk-openai');
    await s.setBaseUrl('https://relay.example.com/v1');
    await s.setProvider(LlmProvider.deepseek);
    expect(await s.llmKey(), 'sk-deepseek');
    expect(s.model, 'deepseek-chat');
    await s.setProvider(LlmProvider.openai);
    expect(await s.llmKey(), 'sk-openai');
    expect(s.baseUrl, 'https://relay.example.com/v1');

    // Survives a reload.
    final again = await AppSettings.load(storage);
    expect(again.provider, LlmProvider.openai);
    await again.setProvider(LlmProvider.deepseek);
    expect(await again.llmKey(), 'sk-deepseek');
    expect(again.model, 'deepseek-chat');
  });

  test('notifications flag round-trips and defaults to off', () async {
    final storage = AppStorage.at(dir);
    final s = await AppSettings.load(storage);
    expect(s.notifications, isFalse);
    await s.setNotifications(true);
    expect((await AppSettings.load(storage)).notifications, isTrue);
  });
}
