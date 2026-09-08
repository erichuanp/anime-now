import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../l10n/strings.dart';
import '../util/time_utils.dart';
import 'anime_store.dart';
import 'app_log.dart';
import 'settings.dart';

/// Local "episode is airing now" notifications.
///
/// One-shot exact alarms for the next [weeksAhead] occurrences of every
/// non-ended anime (slot chosen by the time-basis setting), refreshed by
/// [sync] whenever the list / settings change, on resume, and once per day.
/// The setting can only be ON while the system permission is granted:
/// [sync] flips it OFF when the user revoked it in system settings.
///
/// Backed by the OS scheduler everywhere: alarms on Android,
/// `UNUserNotificationCenter` on macOS, scheduled toasts on Windows. Windows
/// has no permission prompt, so [isPermitted] is always true there.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  /// Kept small on purpose: macOS (like iOS) caps an app at 64 pending
  /// requests and silently drops the rest, so a wide window would quietly
  /// starve the anime at the end of the list.
  static const weeksAhead = 2;
  static const _channelId = 'anime_airing';
  static final _log = AppLog.instance;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _syncing = false;
  bool _again = false;
  String _lastSignature = '';

  AndroidFlutterLocalNotificationsPlugin? get _android => Platform.isAndroid
      ? _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      : null;

  MacOSFlutterLocalNotificationsPlugin? get _macos => Platform.isMacOS
      ? _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
      : null;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked from the settings switch, not on startup.
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
          windows: WindowsInitializationSettings(
            appName: 'Anime Now',
            appUserModelId: 'com.erichuanp.animenow',
            guid: '8a816df3-8f4a-4186-9169-75d4fa4efaa9',
          ),
        ),
      );
      _ready = true;
      _log.d('notif', 'plugin initialised');
    } catch (e) {
      _log.w('notif', 'init failed: $e');
    }
  }

  /// System-level "app may post notifications". Windows has no such switch.
  Future<bool> isPermitted() async {
    if (Platform.isWindows) return true;
    try {
      if (Platform.isMacOS) return (await _macos?.checkPermissions())?.isEnabled ?? false;
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (e) {
      _log.w('notif', 'permission check failed: $e');
      return false;
    }
  }

  /// Shows the system prompt (Android 13+, macOS); returns the resulting state.
  Future<bool> requestPermission() async {
    await init();
    if (Platform.isWindows) return true;
    try {
      final r = Platform.isMacOS
          ? await _macos?.requestPermissions(alert: true, sound: true)
          : await _android?.requestNotificationsPermission();
      _log.i('notif', 'permission request → $r');
      if (r == true) return true;
      return await isPermitted();
    } catch (e) {
      _log.w('notif', 'permission request failed: $e');
      return false;
    }
  }

  /// Reconciles the setting with the system permission, then (re)schedules.
  /// Cheap when nothing relevant changed since the last call.
  Future<void> sync(AppSettings settings, AnimeStore store, {bool force = false}) async {
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await _syncOnce(settings, store, force);
      } while (_again);
    } catch (e, st) {
      _log.e('notif', 'sync failed', e, st);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce(AppSettings settings, AnimeStore store, bool force) async {
    await init();
    if (!_ready) return;
    if (!settings.notifications) {
      if (_lastSignature.isNotEmpty || force) {
        await _plugin.cancelAll();
        _lastSignature = '';
        _log.d('notif', 'disabled: all cancelled');
      }
      return;
    }
    if (!await isPermitted()) {
      _log.i('notif', 'permission revoked in system settings → switch off');
      await _plugin.cancelAll();
      _lastSignature = '';
      await settings.setNotifications(false); // notifies → sync runs again, sees OFF
      return;
    }
    final sig = _signature(settings, store);
    if (!force && sig == _lastSignature) return;

    await _plugin.cancelAll();
    final s = S(settings.language);
    var mode = AndroidScheduleMode.exactAllowWhileIdle;
    try {
      if (await _android?.canScheduleExactNotifications() == false) mode = AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {}
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        s.notifChannel,
        channelDescription: s.pushNotificationsHelp,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.event,
      ),
      macOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
      windows: const WindowsNotificationDetails(),
    );
    var scheduled = 0;
    final lines = <String>[];
    for (final e in store.items) {
      if (e.isEnded) continue;
      final sorted = sortedBroadcasts(e);
      if (sorted.isEmpty) continue;
      final b = settings.timeBasis == TimeBasis.earliest ? sorted.first : sorted.last;
      final times = nextOccurrences(b, count: weeksAhead, lastAirDate: e.lastAirDate);
      final title = e.titleFor(settings.language);
      for (var k = 0; k < times.length; k++) {
        try {
          await _plugin.zonedSchedule(
            id: e.id * 10 + k,
            title: s.notifTitle,
            body: title,
            scheduledDate: tz.TZDateTime.from(times[k], tz.UTC),
            notificationDetails: details,
            androidScheduleMode: mode,
          );
          scheduled++;
        } catch (err) {
          _log.w('notif', 'schedule #${e.id}/$k failed: $err');
          if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
            mode = AndroidScheduleMode.inexactAllowWhileIdle; // no exact-alarm permission on this device
            k--;
          }
        }
      }
      if (times.isNotEmpty) lines.add('  #${e.id} $title ${b.platform} → ${fmtDateTime(times.first)} (+${times.length - 1})');
    }
    _lastSignature = sig;
    _log.i('notif', 'scheduled $scheduled notifications (${mode.name}, lang=${settings.language}, basis=${settings.timeBasis.name}):\n${lines.join('\n')}');
  }

  /// Everything the schedule depends on, plus the date so the 2-week window
  /// rolls forward at most once a day.
  String _signature(AppSettings settings, AnimeStore store) {
    final b = StringBuffer('${settings.language}|${settings.timeBasis.name}|${fmtDate(DateTime.now())}|');
    for (final e in store.items) {
      b.write('${e.id}:${e.lastAirDate}:${e.broadcasts.length};');
    }
    return b.toString();
  }
}
