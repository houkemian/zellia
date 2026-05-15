import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'home_widget_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // app may have initialized already, ignore
  }
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  ApiService? _api;

  Future<void> initialize(ApiService api) async {
    if (_initialized) return;
    try {
      _api = api;
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Firebase initialize failed: $e');
      }
      _initialized = true;
      return;
    }

    // FCM needs Google Play services (e.g. MISSING_INSTANCEID_SERVICE on GMS-less
    // devices). Never throw — app startup must not hang on push registration.
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const initSettings = InitializationSettings(android: androidSettings);
      await _localNotifications.initialize(initSettings);

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _syncDeviceToken(api, token);
      }

      messaging.onTokenRefresh.listen((newToken) async {
        await _syncDeviceToken(api, newToken);
      });

      FirebaseMessaging.onMessage.listen((message) async {
        final notification = message.notification;
        if (notification != null) {
          final android = notification.android;
          if (android != null) {
            final copy = _medicationReminderCopy(message);
            final channelId = message.data['type'] == 'caregiver_poke'
                ? 'medication_reminder'
                : 'zellia_alerts_channel';
            final channelName = channelId == 'medication_reminder'
                ? 'Medication reminders'
                : 'Zellia Alerts';
            await _localNotifications.show(
              notification.hashCode,
              copy.$1,
              copy.$2,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  channelId,
                  channelName,
                  channelDescription:
                      'Abnormal vitals and missed medication reminders',
                  importance: Importance.max,
                  priority: Priority.high,
                ),
              ),
            );
          }
        }
        final api = _api;
        if (api != null &&
            (notification != null || message.data.isNotEmpty)) {
          unawaited(HomeWidgetService.refreshAllCachedMembers(api));
        }
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'Push / FCM unavailable (often no Google Play services): $e',
        );
        debugPrint('$st');
      }
    }

    _initialized = true;
  }

  /// Prefer [caregiver_nickname] from FCM data (alias or profile nickname), not login username.
  static (String title, String body) _medicationReminderCopy(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? 'Zellia';
    var body = notification?.body ?? '';
    final data = message.data;
    if (data['type'] == 'caregiver_poke') {
      final nickname = (data['caregiver_nickname'] ?? '').trim();
      final planName = (data['plan_name'] ?? '').trim();
      if (nickname.isNotEmpty && planName.isNotEmpty) {
        body = '您的子女 $nickname 提醒您服用 $planName';
      }
    }
    return (title, body);
  }

  /// Server may be down (502) or unreachable; do not fail app startup.
  Future<void> _syncDeviceToken(ApiService api, String fcmToken) async {
    try {
      await api.upsertDeviceToken(
        fcmToken: fcmToken,
        deviceLabel: defaultTargetPlatform.name,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Device token sync failed (will retry on token refresh): $e');
        debugPrint('$st');
      }
    }
  }
}
