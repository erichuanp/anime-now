import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'platform/host.dart';
import 'services/anime_store.dart';
import 'services/cover_cache.dart';
import 'services/app_log.dart';
import 'services/app_storage.dart';
import 'services/bangumi_hosts.dart';
import 'services/notifications.dart';
import 'services/settings.dart';
import 'ui/schedule_page.dart';
import 'ui/search_page.dart';
import 'ui/settings_page.dart';

Future<void> main() async {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLog.instance.e('flutter', details.exceptionAsString(), null, details.stack);
  };
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // Portrait only; the app never rotates. Desktop keeps the same shape
    // through the window itself (see MainFlutterWindow / window_shape).
    if (isMobile) await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final storage = await AppStorage.resolve();
    await AppLog.instance.init(storage.dir);
    tzdata.initializeTimeZones();
    final settings = await AppSettings.load(storage);
    final store = await AnimeStore.load(storage);
    AppLog.instance.i('app', 'cold start (new process); local tz offset=${DateTime.now().timeZoneOffset} (${DateTime.now().timeZoneName})');
    runApp(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStorage>.value(value: storage),
        ChangeNotifierProvider<AppSettings>.value(value: settings),
        ChangeNotifierProvider<AnimeStore>.value(value: store),
        ChangeNotifierProvider<BangumiHosts>.value(value: BangumiHosts.instance),
        ChangeNotifierProvider<CoverCache>.value(value: CoverCache.instance),
      ],
      child: const AnimeNowApp(),
    ));
    // Local notifications follow the list + settings; permission is re-checked
    // on every sync (and on resume, see HomeShell).
    void resync() => unawaited(NotificationService.instance.sync(settings, store));
    settings.addListener(resync);
    store.addListener(resync);
    resync();
    // Covers load one at a time in anime.json order (the mirror queues
    // globally); anything already on disk is reused without a request.
    void covers() => CoverCache.instance.ensureAll(store.items.map((e) => e.coverUrl));
    store.addListener(covers);
    BangumiHosts.instance.addListener(CoverCache.instance.retryFailed);
    covers();
  }, (error, stack) {
    try {
      AppLog.instance.e('zone', 'uncaught error', error, stack);
    } catch (_) {}
    debugPrint('[AnimeNow] uncaught: $error\n$stack');
  });
}

/// Keep in sync with pubspec.yaml `version` (YYYY.M.D+N → YYYY.M.D.N).
const appVersion = '2026.9.3.1';

class AppColors {
  static const seed = Color(0xFFF48FB1);
  static const background = Color(0xFFFFF3F7);
  static const surface = Color(0xFFFFFFFF);
  static const accent = Color(0xFFEC407A);
  static const bannerYellow = Color(0xFFFFF4C2);
  static const addGreen = Color(0xFF43A047);
}

class AnimeNowApp extends StatelessWidget {
  const AnimeNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      surface: AppColors.surface,
    );
    return MaterialApp(
      title: 'Anime Now',
      debugShowCheckedModeBanner: false,
      locale: settings.localeOverride,
      supportedLocales: const [Locale('zh', 'CN'), Locale('zh', 'TW'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 1,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFFFFE4EE),
          indicatorColor: const Color(0xFFF8BBD0),
          surfaceTintColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          // Icons must not prop the field up to 48dp.
          prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 28),
          suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 28),
          iconColor: const Color(0xFF7A4E5E),
          prefixIconColor: const Color(0xFF7A4E5E),
          labelStyle: const TextStyle(fontSize: 13),
          hintStyle: const TextStyle(fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        textTheme: const TextTheme(bodyLarge: TextStyle(fontSize: 14)), // TextField default style
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Lifecycle trace so the log shows resume-from-background vs cold start.
  /// (The log file is only recreated in main(), i.e. on a new process.)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    AppLog.instance.i('lifecycle', state.name);
    if (state == AppLifecycleState.resumed) {
      // The user may have toggled the notification permission in system settings.
      unawaited(NotificationService.instance.sync(context.read<AppSettings>(), context.read<AnimeStore>()));
      context.read<CoverCache>().retryFailed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [SchedulePage(), SearchPage(), SettingsPage()],
      ),
      extendBody: true, // pages scroll underneath the floating pill
      bottomNavigationBar: _FloatingNavBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          (Icons.schedule_outlined, Icons.schedule), // clock: the weekly schedule
          (Icons.search_outlined, Icons.search),
          (Icons.settings_outlined, Icons.settings),
        ],
      ),
    );
  }
}

/// Floating pill navigation (iOS 26 Apple Music style): pink rounded base
/// split into three equal thirds, icon only. The selected third is filled
/// white edge to edge (clipped by the pill's rounded ends).
class _FloatingNavBar extends StatelessWidget {
  const _FloatingNavBar({required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, IconData)> items;

  static const double _height = 45;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final width = MediaQuery.of(context).size.width;
    final horizontal = width * 0.19; // pill ≈ 62% of screen width
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 0, horizontal, bottomInset + 12),
      child: Container(
        height: _height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_height / 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 5)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_height / 2),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: ColoredBox(
              color: const Color(0xFFF9C4D6).withValues(alpha: 0.94),
              child: Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child: AnimatedContainer(
                          // Only the newly selected third fades in; the one being
                          // left snaps back so it never looks like it was pressed.
                          duration: i == index ? const Duration(milliseconds: 160) : Duration.zero,
                          curve: Curves.easeOut,
                          color: i == index ? Colors.white : Colors.transparent,
                          alignment: Alignment.center,
                          child: Icon(
                            i == index ? items[i].$2 : items[i].$1,
                            size: 22,
                            color: i == index ? AppColors.accent : const Color(0xFF7A4E5E),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
