import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:home_widget/home_widget.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'l10n/generated/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/today_screen.dart';
import 'screens/weekly_summary_list_screen.dart';
import 'screens/weekly_summary_screen.dart';
import 'services/api_service.dart';
import 'services/home_widget_service.dart';
import 'services/local_database_service.dart';
import 'services/push_notification_service.dart';
import 'services/sync_manager.dart';
import 'services/revenuecat_service.dart';
import 'services/widget_background_callback.dart';
import 'widgets/accessibility_theme.dart';

Future<void> _configureLocalTimezone() async {
  tz_data.initializeTimeZones();
  try {
    final name = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(name));
  } catch (e) {
    if (kDebugMode) {
      debugPrint('timezone init failed, using UTC: $e');
    }
    tz.setLocalLocation(tz.getLocation('UTC'));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureLocalTimezone();
  await Firebase.initializeApp();
  await HomeWidgetService.initialize();
  await HomeWidget.registerInteractivityCallback(homeWidgetInteractivityCallback);
  HomeWidgetService.registerApiHooks();
  await LocalDatabaseService.instance.database;
  await RevenueCatService.instance.init();
  runApp(const ZelliaApp());
}

/// Dev default; override with `--dart-define=API_BASE=http://10.0.2.2:8000` for Android emulator.
const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://zellia-api.dothings.one/',
);

class ZelliaApp extends StatefulWidget {
  const ZelliaApp({super.key});

  @override
  State<ZelliaApp> createState() => _ZelliaAppState();
}

class _ZelliaAppState extends State<ZelliaApp> {
  final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

  late final ApiService _api = ApiService(
    baseUrl: kDefaultApiBase,
    onUnauthorized: _handleUnauthorized,
  );

  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    PushNotificationService.registerWeeklySummaryHandler(_openWeeklySummary);
    _restoreSession();
  }

  void _openWeeklySummary(int elderId, String? weekStart) {
    final nav = _rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => WeeklySummaryScreen(
          api: _api,
          elderId: elderId,
          weekStart: weekStart,
          isFrozen: false,
        ),
      ),
    );
  }

  Future<void> _restoreSession() async {
    await _api.restoreLegacyJwt();
    final loggedIn =
        FirebaseAuth.instance.currentUser != null || _api.hasLegacySession;
    if (loggedIn) {
      await PushNotificationService.instance.initialize(_api);
      await SyncManager.instance.initialize(_api);
      try {
        final profile = await _api.getCurrentUserProfile();
        await RevenueCatService.instance.login(profile.id.toString());
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[RevenueCat] session restore login failed: $e');
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _loggedIn = loggedIn;
      _checking = false;
    });
  }

  void _handleUnauthorized() {
    unawaited(_performLogout());
  }

  /// Clears session and switches [MaterialApp] home to [LoginScreen].
  Future<void> _performLogout() async {
    currentViewUserId = null;
    currentViewUserName = null;
    try {
      await RevenueCatService.instance.logout();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[RevenueCat] logout failed: $e');
      }
    }
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Firebase signOut failed: $e');
      }
    }
    try {
      await _api.clearLegacyJwt();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('clearLegacyJwt failed: $e');
      }
    }
    SyncManager.instance.dispose();
    final nav = _rootNavigatorKey.currentState;
    if (nav != null && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    }
    if (!mounted) return;
    setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Zellia',
      theme: buildZelliaTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _checking
          ? Builder(
              builder: (context) {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          width: 96,
                          height: 96,
                        ),
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF0E6A55),
                        ),
                      ],
                    ),
                  ),
                );
              },
            )
          : _loggedIn
          ? TodayScreen(
              api: _api,
              onLogout: _performLogout,
            )
          : LoginScreen(
              api: _api,
              onLoggedIn: () async {
                final firebaseUser = FirebaseAuth.instance.currentUser;
                if (firebaseUser == null && !_api.hasLegacySession) {
                  if (!mounted) return;
                  setState(() => _loggedIn = false);
                  return;
                }
                await PushNotificationService.instance.initialize(_api);
                await SyncManager.instance.initialize(_api);
                try {
                  final profile = await _api.getCurrentUserProfile();
                  await RevenueCatService.instance.login(profile.id.toString());
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('[RevenueCat] post-login failed: $e');
                  }
                }
                if (!mounted) return;
                setState(() => _loggedIn = true);
              },
            ),
    );
  }
}
