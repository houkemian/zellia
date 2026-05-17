import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'family_voice_notification_helper.dart';
import 'home_widget_service.dart';
import 'medication_reminder_schedule_service.dart';
import 'voice_reminder_storage_service.dart';

@pragma('vm:entry-point')
void _onBackgroundNotificationResponse(NotificationResponse response) {
  if (kDebugMode) {
    debugPrint(
      '[Notification][sound] background tap id=${response.id} '
      'payload=${response.payload}',
    );
  }
}

void _logLocalNotificationEvent(
  String source,
  NotificationResponse response,
) {
  if (!kDebugMode) return;
  debugPrint(
    '[Notification][sound] $source id=${response.id} '
    'actionId=${response.actionId} payload=${response.payload}',
  );
}

final FlutterLocalNotificationsPlugin _backgroundLocalNotifications =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await PushNotificationService.showIncomingMessage(
    message,
    notifications: _backgroundLocalNotifications,
    source: 'background',
    initializePlugin: true,
  );
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  /// Must match AndroidManifest `default_notification_channel_id`.
  static const String fcmDefaultChannelId = 'zellia_alerts_channel';
  static const String fcmMedicationPokeChannelId = 'medication_reminder';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  late final MedicationReminderScheduleService _medicationScheduler =
      MedicationReminderScheduleService(_localNotifications);
  bool _initialized = false;
  ApiService? _api;

  MedicationReminderScheduleService get medicationScheduler =>
      _medicationScheduler;

  static int? _elderIdFromMessage(RemoteMessage message) {
    final raw = message.data['elder_id'];
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  /// Display FCM (data-only poke uses local notification + family voice when cached).
  static Future<void> showIncomingMessage(
    RemoteMessage message, {
    required FlutterLocalNotificationsPlugin notifications,
    required String source,
    bool initializePlugin = false,
    ApiService? api,
  }) async {
    final data = message.data;
    final notification = message.notification;
    final title =
        notification?.title ?? data['title'] as String? ?? 'Zellia';
    var body = notification?.body ?? data['body'] as String? ?? '';
    if (data['type'] == 'caregiver_poke') {
      final nickname = (data['caregiver_nickname'] ?? '').toString().trim();
      final planName = (data['plan_name'] ?? '').toString().trim();
      if (nickname.isNotEmpty && planName.isNotEmpty) {
        body = '您的家人 $nickname 提醒您服用 $planName';
      }
    }

    if (initializePlugin) {
      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await notifications.initialize(initSettings);
      final android = notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          fcmDefaultChannelId,
          'Zellia Alerts',
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          fcmMedicationPokeChannelId,
          'Medication reminders',
          importance: Importance.max,
        ),
      );
    }

    final isPoke = data['type'] == 'caregiver_poke';
    var soundKind = 'default';
    NotificationDetails details;

    if (isPoke) {
      final elderId = _elderIdFromMessage(message);
      if (elderId != null) {
        final storage = VoiceReminderStorageService.instance;
        if (!await storage.hasLocalVoiceForUser(elderId) && api != null) {
          try {
            final signed = await api.getVoiceDownloadUrl(userId: elderId);
            await storage.ensureDownloaded(
              userId: elderId,
              voiceUrl: signed.downloadUrl,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('[Notification][sound] poke prefetch failed: $e');
            }
          }
        }
        final built = await FamilyVoiceNotificationHelper.build(
          notifications: notifications,
          elderUserId: elderId,
          defaultAndroidChannelId: fcmMedicationPokeChannelId,
          defaultAndroidChannelName: 'Medication reminders',
          defaultAndroidChannelDescription:
              'Family caregiver medication reminders',
        );
        details = built.details;
        soundKind = built.soundKind;
      } else {
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            fcmMedicationPokeChannelId,
            'Medication reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        );
      }
    } else {
      details = const NotificationDetails(
        android: AndroidNotificationDetails(
          fcmDefaultChannelId,
          'Zellia Alerts',
          channelDescription:
              'Abnormal vitals and missed medication reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      );
    }

    if (kDebugMode) {
      debugPrint(
        '[Notification][sound] FCM $source show type=${data['type']} '
        'channel=${isPoke ? fcmMedicationPokeChannelId : fcmDefaultChannelId} '
        'sound=$soundKind elderId=${_elderIdFromMessage(message)}',
      );
    }

    final id = message.hashCode & 0x7fffffff;
    await notifications.show(id, title, body, details);
  }

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
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          _logLocalNotificationEvent('foreground/local', response);
        },
        onDidReceiveBackgroundNotificationResponse:
            _onBackgroundNotificationResponse,
      );

      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
      await _ensureAndroidNotificationChannels(androidPlugin);

      final iosPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _syncDeviceToken(api, token);
      }

      messaging.onTokenRefresh.listen((newToken) async {
        await _syncDeviceToken(api, newToken);
      });

      FirebaseMessaging.onMessage.listen((message) async {
        await showIncomingMessage(
          message,
          notifications: _localNotifications,
          source: 'foreground',
          api: _api,
        );
        final apiRef = _api;
        if (apiRef != null &&
            (message.notification != null || message.data.isNotEmpty)) {
          unawaited(HomeWidgetService.refreshAllCachedMembers(apiRef));
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

  static Future<void> _ensureAndroidNotificationChannels(
    AndroidFlutterLocalNotificationsPlugin? android,
  ) async {
    if (android == null) return;
    try {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          fcmDefaultChannelId,
          'Zellia Alerts',
          description: 'Abnormal vitals and general health alerts',
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          fcmMedicationPokeChannelId,
          'Medication reminders',
          description: 'Family caregiver medication reminders',
          importance: Importance.max,
        ),
      );
      if (kDebugMode) {
        debugPrint(
          '[Notification] Android channels ready: '
          '$fcmDefaultChannelId, $fcmMedicationPokeChannelId',
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Notification] createNotificationChannel failed: $e');
      }
    }
  }

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
