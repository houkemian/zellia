import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'l10n/generated/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/today_screen.dart';
import 'services/api_service.dart';
import 'services/push_notification_service.dart';
import 'services/revenuecat_service.dart';
import 'widgets/accessibility_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
  late final ApiService _api = ApiService(
    baseUrl: kDefaultApiBase,
    onUnauthorized: _handleUnauthorized,
  );

  bool _checking = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    if (loggedIn) {
      try {
        await PushNotificationService.instance.initialize(_api);
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('[Push] initialize failed during session restore: $e');
          debugPrint('$st');
        }
      }
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
    FirebaseAuth.instance.signOut().then((_) {
      if (!mounted) return;
      setState(() => _loggedIn = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) =>
          AppLocalizations.of(context)?.appTitle ?? 'Zellia',
      theme: buildZelliaTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _checking
          ? Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context);
                return Scaffold(
                  body: Center(child: Text(l10n?.loading ?? 'Loading...')),
                );
              },
            )
          : _loggedIn
          ? TodayScreen(
              api: _api,
              onLogout: () => setState(() => _loggedIn = false),
            )
          : LoginScreen(
              api: _api,
              onLoggedIn: () async {
                final firebaseUser = FirebaseAuth.instance.currentUser;
                if (firebaseUser == null) {
                  if (!mounted) return;
                  setState(() => _loggedIn = false);
                  return;
                }
                try {
                  await PushNotificationService.instance.initialize(_api);
                } catch (e, st) {
                  if (kDebugMode) {
                    debugPrint('[Push] initialize failed after login: $e');
                    debugPrint('$st');
                  }
                }
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
