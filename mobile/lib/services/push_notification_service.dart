import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

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

  Future<void> initialize(ApiService api) async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Firebase initialize failed: $e');
      }
      return;
    }

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
      final android = notification?.android;
      if (notification == null || android == null) return;
      await _localNotifications.show(
        notification.hashCode,
        notification.title ?? 'Zellia',
        notification.body ?? '',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'zellia_alerts_channel',
            'Zellia Alerts',
            channelDescription:
                'Abnormal vitals and missed medication reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    });

    _initialized = true;
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
