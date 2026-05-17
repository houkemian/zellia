import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';
import 'family_voice_notification_helper.dart';
import 'voice_reminder_storage_service.dart';

/// Schedules on-device medication reminders with optional PRO family voice sounds.
class MedicationReminderScheduleService {
  MedicationReminderScheduleService(this._notifications);

  final FlutterLocalNotificationsPlugin _notifications;
  final VoiceReminderStorageService _voiceStorage =
      VoiceReminderStorageService.instance;

  static const int _notificationIdBase = 40000;
  final Set<int> _activeNotificationIds = {};
  AndroidScheduleMode? _cachedAndroidScheduleMode;

  Future<AndroidScheduleMode> _androidScheduleMode() async {
    if (!Platform.isAndroid) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final cached = _cachedAndroidScheduleMode;
    if (cached != null) return cached;

    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    try {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final canExact = await android.canScheduleExactNotifications();
        if (canExact == true) {
          mode = AndroidScheduleMode.exactAllowWhileIdle;
        } else {
          final granted = await android.requestExactAlarmsPermission();
          if (granted == true) {
            mode = AndroidScheduleMode.exactAllowWhileIdle;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('med schedule: exact alarm permission check failed: $e');
      }
    }
    _cachedAndroidScheduleMode = mode;
    if (kDebugMode && mode == AndroidScheduleMode.inexactAllowWhileIdle) {
      debugPrint(
        'med schedule: using inexact alarms (grant exact alarms in system settings for precise times)',
      );
    }
    return mode;
  }

  int _notificationId(int planId, String scheduledTime) {
    return _notificationIdBase + planId * 100 + scheduledTime.hashCode % 97;
  }

  Future<void> syncFromTodayItems(
    List<TodayMedicationItemDto> items, {
    required int ownerUserId,
  }) async {
    final nextIds = <int>{};
    for (final item in items) {
      if (!item.notifyMissed) continue;
      nextIds.add(_notificationId(item.planId, item.scheduledTime));
    }
    for (final oldId in _activeNotificationIds.toList()) {
      if (!nextIds.contains(oldId)) {
        await _notifications.cancel(oldId);
      }
    }
    _activeNotificationIds
      ..clear()
      ..addAll(nextIds);

    String? sharedSoundRef;
    String? sharedAndroidContentUri;
    String? sharedVoiceUrl;
    int? sharedCaregiverId;
    for (final item in items) {
      final url = item.voiceUrl?.trim();
      if (url != null && url.isNotEmpty) {
        sharedVoiceUrl = url;
        sharedCaregiverId = item.familyVoiceCaregiverId;
        break;
      }
    }
    if (sharedVoiceUrl != null && sharedCaregiverId != null) {
      await _voiceStorage.ensureDownloaded(
        caregiverUserId: sharedCaregiverId,
        elderUserId: ownerUserId,
        voiceUrl: sharedVoiceUrl,
      );
      sharedSoundRef = await _voiceStorage.notificationSoundReference(
        caregiverUserId: sharedCaregiverId,
        elderUserId: ownerUserId,
      );
      if (Platform.isAndroid) {
        sharedAndroidContentUri = await _voiceStorage.androidNotificationContentUri(
          caregiverUserId: sharedCaregiverId,
          elderUserId: ownerUserId,
        );
      }
      if (kDebugMode) {
        final urlPreview = sharedVoiceUrl.length > 80
            ? '${sharedVoiceUrl.substring(0, 80)}…'
            : sharedVoiceUrl;
        debugPrint(
          '[Notification][sound] sync elder=$ownerUserId caregiver=$sharedCaregiverId '
          'voiceUrl=$urlPreview localSoundRef=${sharedSoundRef ?? "none"}',
        );
      }
    } else if (kDebugMode) {
      debugPrint('[Notification][sound] sync: no family voice URL on plans');
    }

    _cachedAndroidScheduleMode = null;
    await _androidScheduleMode();

    for (final item in items) {
      if (!item.notifyMissed) continue;
      await _scheduleOne(
        item: item,
        soundRef: sharedSoundRef,
        androidContentUri: sharedAndroidContentUri,
        caregiverUserId: sharedCaregiverId,
      );
    }
  }

  Future<void> _scheduleOne({
    required TodayMedicationItemDto item,
    required String? soundRef,
    String? androidContentUri,
    int? caregiverUserId,
  }) async {
    try {
      final parts = item.scheduledTime.split(':');
      final hour = int.parse(parts.first);
      final minute = int.parse(parts.length > 1 ? parts[1] : '0');
      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      final tzScheduled = tz.TZDateTime.from(scheduled, tz.local);
      final notificationId = _notificationId(item.planId, item.scheduledTime);

      AndroidNotificationDetails androidDetails;
      String soundKind = 'default';
      if (soundRef != null && soundRef.isNotEmpty && Platform.isAndroid) {
        final androidSound = await FamilyVoiceNotificationHelper
            .ensureAndroidVoiceChannel(
          _notifications,
          soundPath: soundRef,
          contentUri: androidContentUri,
        );
        if (androidSound != null) {
          soundKind = 'family_voice_uri';
          androidDetails = AndroidNotificationDetails(
            FamilyVoiceNotificationHelper.channelId,
            '亲情语音服药提醒',
            channelDescription: '家人录制的服药提醒铃声',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: androidSound,
          );
        } else {
          soundKind = 'default_fallback_missing_file';
          androidDetails = const AndroidNotificationDetails(
            'medication_reminder',
            'Medication reminders',
            channelDescription: 'Scheduled medication reminders',
            importance: Importance.max,
            priority: Priority.high,
          );
        }
      } else if (soundRef != null && soundRef.isNotEmpty && Platform.isIOS) {
        soundKind = 'ios_family_voice';
        androidDetails = const AndroidNotificationDetails(
          'medication_reminder',
          'Medication reminders',
          importance: Importance.max,
          priority: Priority.high,
        );
      } else {
        androidDetails = const AndroidNotificationDetails(
          'medication_reminder',
          'Medication reminders',
          channelDescription: 'Scheduled medication reminders',
          importance: Importance.max,
          priority: Priority.high,
        );
      }

      DarwinNotificationDetails? iosDetails;
      if (Platform.isIOS && soundRef != null && soundRef.isNotEmpty) {
        soundKind = 'ios_family_voice';
        iosDetails = DarwinNotificationDetails(
          sound: soundRef,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
      }

      if (kDebugMode) {
        debugPrint(
          '[Notification][sound] schedule plan=${item.planId} '
          '${item.scheduledTime} kind=$soundKind ref=$soundRef '
          'at=$tzScheduled',
        );
      }

      final scheduleMode = await _androidScheduleMode();
      try {
        await _notifications.zonedSchedule(
          notificationId,
          '服药提醒',
          '该服用 ${item.name}（${item.dosage}）',
          tzScheduled,
          NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        if (kDebugMode) {
          debugPrint(
            '[Notification][sound] scheduled ok id=$notificationId kind=$soundKind',
          );
        }
      } on PlatformException catch (e) {
        if (e.code != 'exact_alarms_not_permitted' || !Platform.isAndroid) {
          rethrow;
        }
        _cachedAndroidScheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;
        await _notifications.zonedSchedule(
          notificationId,
          '服药提醒',
          '该服用 ${item.name}（${item.dosage}）',
          tzScheduled,
          NotificationDetails(
            android: androidDetails,
            iOS: iosDetails,
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'med schedule: failed plan=${item.planId} ${item.scheduledTime}: $e\n$st',
        );
      }
    }
  }
}
