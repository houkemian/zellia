import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';
import 'voice_reminder_storage_service.dart';

/// Schedules on-device medication reminders with optional PRO family voice sounds.
class MedicationReminderScheduleService {
  MedicationReminderScheduleService(this._notifications);

  final FlutterLocalNotificationsPlugin _notifications;
  final VoiceReminderStorageService _voiceStorage =
      VoiceReminderStorageService.instance;

  static const int _notificationIdBase = 40000;
  final Set<int> _activeNotificationIds = {};

  int _notificationId(int planId, String scheduledTime) {
    return _notificationIdBase + planId * 100 + scheduledTime.hashCode % 97;
  }

  String _androidChannelId(int planId, String scheduledTime) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return 'med_voice_${planId}_${scheduledTime.replaceAll(':', '')}_$stamp';
  }

  Future<void> syncFromTodayItems(List<TodayMedicationItemDto> items) async {
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

    for (final item in items) {
      if (!item.notifyMissed) continue;

      String? soundRef;
      if (item.voiceUrl != null && item.voiceUrl!.trim().isNotEmpty) {
        await _voiceStorage.ensureDownloaded(
          planId: item.planId,
          voiceUrl: item.voiceUrl!,
        );
        soundRef = await _voiceStorage.notificationSoundReference(item.planId);
      }

      await _scheduleOne(item: item, soundRef: soundRef);
    }
  }

  Future<void> _scheduleOne({
    required TodayMedicationItemDto item,
    required String? soundRef,
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
      if (soundRef != null && soundRef.isNotEmpty) {
        final channelId = _androidChannelId(item.planId, item.scheduledTime);
        final AndroidNotificationSound androidSound;
        if (Platform.isAndroid) {
          androidSound = UriAndroidNotificationSound(
            Uri.file(soundRef).toString(),
          );
        } else {
          androidSound = const RawResourceAndroidNotificationSound('notification');
        }
        androidDetails = AndroidNotificationDetails(
          channelId,
          'Medication voice reminder',
          channelDescription: 'Custom family voice for ${item.name}',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: androidSound,
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
        iosDetails = DarwinNotificationDetails(
          sound: soundRef,
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
      }

      await _notifications.zonedSchedule(
        notificationId,
        '服药提醒',
        '该服用 ${item.name}（${item.dosage}）',
        tzScheduled,
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
          'med schedule: failed plan=${item.planId} ${item.scheduledTime}: $e\n$st',
        );
      }
    }
  }
}
