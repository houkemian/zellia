import 'package:flutter/material.dart';

import 'l10n/generated/app_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/today_screen.dart';
import 'services/api_service.dart';
import 'widgets/accessibility_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZelliaApp());
}

/// Dev default; override with `--dart-define=API_BASE=http://10.0.2.2:8000` for Android emulator.
const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://10.1.50.211:8001',
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
    final token = await _api.getToken();
    if (!mounted) return;
    setState(() {
      _loggedIn = token != null && token.isNotEmpty;
      _checking = false;
    });
  }

  void _handleUnauthorized() {
    _api.saveToken(null).then((_) {
      if (!mounted) return;
      setState(() => _loggedIn = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: buildZelliaTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _checking
          ? Scaffold(
              body: Center(
                child: Text(AppLocalizations.of(context)!.loading),
              ),
            )
          : _loggedIn
              ? TodayScreen(api: _api, onLogout: () => setState(() => _loggedIn = false))
              : LoginScreen(
                  api: _api,
                  onLoggedIn: () => setState(() => _loggedIn = true),
                ),
    );
  }
}
