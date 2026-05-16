import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import '../main.dart' show kDefaultApiBase;
import 'api_service.dart';
import 'home_widget_service.dart';

/// Invoked from the Android widget refresh button via [HomeWidget.registerInteractivityCallback].
@pragma('vm:entry-point')
Future<void> homeWidgetInteractivityCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (uri?.host != 'refresh') return;

  final memberId = uri?.queryParameters['memberId']?.trim();
  if (memberId == null || memberId.isEmpty) return;

  try {
    await Firebase.initializeApp();
    await HomeWidgetService.initialize();
    final api = ApiService(baseUrl: kDefaultApiBase);
    await api.restoreLegacyJwt();
    final hasSession =
        FirebaseAuth.instance.currentUser != null || api.hasLegacySession;
    if (!hasSession) return;

    await HomeWidgetService.instance.refreshMemberFromWidget(memberId, api: api);
  } catch (e, st) {
    debugPrint('[HomeWidget] background refresh failed: $e');
    debugPrint('$st');
  }
}
