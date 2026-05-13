import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

int? currentViewUserId;
String? currentViewUserName;

/// Central HTTP client for Zellia. Intercepts 401 and notifies [onUnauthorized].
class ApiService {
  ApiService({required String baseUrl, this.onUnauthorized})
    : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  static const _legacyJwtPrefsKey = 'zellia_legacy_jwt';

  final String baseUrl;
  final void Function()? onUnauthorized;

  /// JWT from family activation when the API cannot mint a Firebase custom token.
  String? _legacyJwt;

  Uri _url(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }

  String _withQuery(String path, Map<String, Object?> query) {
    final filtered = <String, String>{};
    for (final entry in query.entries) {
      final value = entry.value;
      if (value != null) {
        filtered[entry.key] = value.toString();
      }
    }
    if (filtered.isEmpty) return path;
    final uri = Uri(path: path, queryParameters: filtered);
    return uri.toString();
  }

  String debugUrl(String path) => _url(path).toString();

  void _logRequest(String method, Uri url, {Object? body}) {
    if (!kDebugMode) return;
    debugPrint('[API][$method] $url');
    if (body != null) {
      debugPrint('[API][$method][BODY] $body');
    }
  }

  void _logResponse(String method, Uri url, http.Response res) {
    if (!kDebugMode) return;
    final preview = res.body.length > 300
        ? '${res.body.substring(0, 300)}...'
        : res.body;
    debugPrint('[API][$method][${res.statusCode}] $url');
    debugPrint('[API][$method][RESP] $preview');
  }

  Future<String?> _bearerToken() async {
    final fb = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (fb != null && fb.isNotEmpty) return fb;
    final legacy = _legacyJwt;
    if (legacy != null && legacy.isNotEmpty) return legacy;
    return null;
  }

  Future<Map<String, String>> _headers({bool jsonBody = true}) async {
    final token = await _bearerToken();
    return {
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
      if (jsonBody) 'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> restoreLegacyJwt() async {
    final prefs = await SharedPreferences.getInstance();
    _legacyJwt = prefs.getString(_legacyJwtPrefsKey);
  }

  Future<void> setLegacyJwt(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_legacyJwtPrefsKey);
      _legacyJwt = null;
    } else {
      await prefs.setString(_legacyJwtPrefsKey, token);
      _legacyJwt = token;
    }
  }

  Future<void> clearLegacyJwt() async {
    await setLegacyJwt(null);
  }

  bool get hasLegacySession =>
      _legacyJwt != null && _legacyJwt!.isNotEmpty;

  Future<void> saveToken(String? token) async {
    await setLegacyJwt(token);
  }

  Future<String?> getToken() async {
    return _bearerToken();
  }

  Future<http.Response> get(String path) async {
    final url = _url(path);
    _logRequest('GET', url);
    final res = await http.get(url, headers: await _headers(jsonBody: false));
    _logResponse('GET', url, res);
    await _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> post(String path, {Object? body}) async {
    final url = _url(path);
    _logRequest('POST', url, body: body);
    final res = await http.post(
      url,
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _logResponse('POST', url, res);
    await _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> postForm(
    String path,
    Map<String, String> fields,
  ) async {
    final url = _url(path);
    _logRequest('POST_FORM', url, body: fields);
    final token = await _bearerToken();
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final res = await http.post(url, headers: headers, body: fields);
    _logResponse('POST_FORM', url, res);
    await _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> delete(String path) async {
    final url = _url(path);
    _logRequest('DELETE', url);
    final res = await http.delete(
      url,
      headers: await _headers(jsonBody: false),
    );
    _logResponse('DELETE', url, res);
    await _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> put(String path, {Object? body}) async {
    final url = _url(path);
    _logRequest('PUT', url, body: body);
    final res = await http.put(
      url,
      headers: await _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    _logResponse('PUT', url, res);
    await _handleUnauthorized(res);
    return res;
  }

  Future<void> _handleUnauthorized(http.Response response) async {
    if (response.statusCode == 401) {
      await clearLegacyJwt();
      onUnauthorized?.call();
    }
  }

  /// Deprecated: app session now directly uses Firebase ID token.
  Future<String> firebaseProxyLogin({
    required String provider,
    required String idToken,
    String? accessToken,
  }) async {
    final res = await post(
      '/auth/firebase-login',
      body: {
        'provider': provider,
        'id_token': idToken,
        if (accessToken != null && accessToken.isNotEmpty)
          'access_token': accessToken,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('firebaseProxyLogin failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw Exception('firebaseProxyLogin failed: invalid token response');
    }
    return token;
  }
}

class MedicationPlanCreateDto {
  MedicationPlanCreateDto({
    required this.name,
    required this.dosage,
    required this.startDate,
    required this.endDate,
    required this.timesADay,
    this.notifyMissed = true,
    this.notifyDelayMinutes = 60,
  });

  final String name;
  final String dosage;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> timesADay;
  final bool notifyMissed;
  final int notifyDelayMinutes;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dosage': dosage,
      'start_date': DateFormat('yyyy-MM-dd').format(startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(endDate),
      'times_a_day': timesADay.join(','),
      'notify_missed': notifyMissed,
      'notify_delay_minutes': notifyDelayMinutes,
    };
  }
}

class TodayMedicationItemDto {
  TodayMedicationItemDto({
    required this.planId,
    required this.name,
    required this.dosage,
    required this.scheduledTime,
    required this.takenDate,
    required this.logId,
    required this.isTaken,
    required this.checkedAt,
    required this.notifyMissed,
    required this.notifyDelayMinutes,
  });

  final int planId;
  final String name;
  final String dosage;
  final String scheduledTime;
  final DateTime takenDate;
  final int? logId;
  final bool isTaken;
  final String? checkedAt;
  final bool notifyMissed;
  final int notifyDelayMinutes;

  factory TodayMedicationItemDto.fromJson(Map<String, dynamic> json) {
    return TodayMedicationItemDto(
      planId: json['plan_id'] as int,
      name: json['name'] as String,
      dosage: json['dosage'] as String,
      scheduledTime: json['scheduled_time'] as String,
      takenDate: DateTime.parse(json['taken_date'] as String),
      logId: json['log_id'] as int?,
      isTaken: (json['is_taken'] as bool?) ?? false,
      checkedAt: json['checked_at'] as String?,
      notifyMissed: (json['notify_missed'] as bool?) ?? true,
      notifyDelayMinutes: (json['notify_delay_minutes'] as int?) ?? 60,
    );
  }
}

extension ApiServiceMedications on ApiService {
  Future<void> createMedicationPlan(
    MedicationPlanCreateDto payload, {
    int? targetUserId,
  }) async {
    final body = payload.toJson();
    if (targetUserId != null) {
      body['target_user_id'] = targetUserId;
    }
    final res = await post('/medications/plan', body: body);
    if (res.statusCode != 201) {
      throw Exception(
        'createMedicationPlan failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<List<TodayMedicationItemDto>> getTodayMedications({
    int? targetUserId,
  }) async {
    final path = _withQuery('/medications/today', {
      'target_user_id': targetUserId,
    });
    final res = await get(path);
    if (res.statusCode != 200) {
      throw Exception(
        'getTodayMedications failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => TodayMedicationItemDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> toggleMedicationLog({
    required int planId,
    required DateTime takenDate,
    required String scheduledTime,
    required bool isTaken,
  }) async {
    final hhmm = scheduledTime.split(':');
    final hour = int.parse(hhmm.first);
    final minute = int.parse(hhmm.last);
    final takenDateOnly = DateTime(
      takenDate.year,
      takenDate.month,
      takenDate.day,
    );
    final payload = {
      'taken_date': DateFormat('yyyy-MM-dd').format(takenDateOnly),
      'taken_time':
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
      'is_taken': isTaken,
    };
    final res = await post('/medications/$planId/log', body: payload);
    if (res.statusCode != 200) {
      throw Exception(
        'toggleMedicationLog failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<void> stopMedicationPlan(int planId) async {
    final res = await delete('/medications/plan/$planId');
    if (res.statusCode != 204) {
      throw Exception(
        'stopMedicationPlan failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<Map<String, dynamic>> pokeElder(int planId) async {
    final res = await post('/medications/$planId/poke');
    if (res.statusCode != 200) {
      throw Exception('pokeElder failed: ${res.statusCode} ${res.body}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

class BloodPressureRecordDto {
  BloodPressureRecordDto({
    required this.id,
    required this.userId,
    required this.systolic,
    required this.diastolic,
    required this.heartRate,
    required this.measuredAt,
  });

  final int id;
  final int userId;
  final int systolic;
  final int diastolic;
  final int? heartRate;
  final DateTime measuredAt;

  factory BloodPressureRecordDto.fromJson(Map<String, dynamic> json) {
    return BloodPressureRecordDto(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      systolic: json['systolic'] as int,
      diastolic: json['diastolic'] as int,
      heartRate: json['heart_rate'] as int?,
      measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
    );
  }
}

class BloodSugarRecordDto {
  BloodSugarRecordDto({
    required this.id,
    required this.userId,
    required this.level,
    required this.condition,
    required this.measuredAt,
  });

  final int id;
  final int userId;
  final double level;
  final String condition;
  final DateTime measuredAt;

  factory BloodSugarRecordDto.fromJson(Map<String, dynamic> json) {
    return BloodSugarRecordDto(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      level: (json['level'] as num).toDouble(),
      condition: json['condition'] as String,
      measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
    );
  }
}

extension ApiServiceVitals on ApiService {
  Future<BloodPressureRecordDto> createBloodPressure({
    required int systolic,
    required int diastolic,
    int? heartRate,
    required DateTime measuredAt,
  }) async {
    final res = await post(
      '/vitals/bp',
      body: {
        'systolic': systolic,
        'diastolic': diastolic,
        'heart_rate': heartRate,
        'measured_at': measuredAt.toUtc().toIso8601String(),
      },
    );
    if (res.statusCode != 201) {
      throw Exception(
        'createBloodPressure failed: ${res.statusCode} ${res.body}',
      );
    }
    return BloodPressureRecordDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<List<BloodPressureRecordDto>> getBloodPressureHistory({
    int page = 1,
    int pageSize = 20,
    int? targetUserId,
  }) async {
    final path = _withQuery('/vitals/bp', {
      'page': page,
      'page_size': pageSize,
      'target_user_id': targetUserId,
    });
    final res = await get(path);
    if (res.statusCode != 200) {
      throw Exception(
        'getBloodPressureHistory failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => BloodPressureRecordDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteBloodPressureRecord(int id) async {
    final res = await delete('/vitals/bp/$id');
    if (res.statusCode != 204) {
      throw Exception(
        'deleteBloodPressureRecord failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<BloodSugarRecordDto> createBloodSugar({
    required double level,
    required String condition,
    required DateTime measuredAt,
  }) async {
    final res = await post(
      '/vitals/bs',
      body: {
        'level': level,
        'condition': condition,
        'measured_at': measuredAt.toUtc().toIso8601String(),
      },
    );
    if (res.statusCode != 201) {
      throw Exception('createBloodSugar failed: ${res.statusCode} ${res.body}');
    }
    return BloodSugarRecordDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<List<BloodSugarRecordDto>> getBloodSugarHistory({
    int page = 1,
    int pageSize = 20,
    int? targetUserId,
  }) async {
    final path = _withQuery('/vitals/bs', {
      'page': page,
      'page_size': pageSize,
      'target_user_id': targetUserId,
    });
    final res = await get(path);
    if (res.statusCode != 200) {
      throw Exception(
        'getBloodSugarHistory failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => BloodSugarRecordDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> deleteBloodSugarRecord(int id) async {
    final res = await delete('/vitals/bs/$id');
    if (res.statusCode != 204) {
      throw Exception(
        'deleteBloodSugarRecord failed: ${res.statusCode} ${res.body}',
      );
    }
  }
}

class FamilyInviteCodeDto {
  FamilyInviteCodeDto({required this.inviteCode});

  final String inviteCode;

  factory FamilyInviteCodeDto.fromJson(Map<String, dynamic> json) {
    return FamilyInviteCodeDto(inviteCode: json['invite_code'] as String);
  }
}

class FamilyQrTokenDto {
  FamilyQrTokenDto({required this.qrPayload, required this.expiresIn});

  final String qrPayload;
  final int expiresIn;

  factory FamilyQrTokenDto.fromJson(Map<String, dynamic> json) {
    return FamilyQrTokenDto(
      qrPayload: (json['qr_payload'] as String?) ?? '',
      expiresIn: (json['expires_in'] as int?) ?? 180,
    );
  }
}

class ScanQrBindResultDto {
  ScanQrBindResultDto({
    required this.success,
    required this.linkId,
    required this.status,
    required this.elderId,
    required this.elderUsername,
    required this.elderNickname,
  });

  final bool success;
  final int linkId;
  final String status;
  final int elderId;
  final String elderUsername;
  final String? elderNickname;

  factory ScanQrBindResultDto.fromJson(Map<String, dynamic> json) {
    return ScanQrBindResultDto(
      success: (json['success'] as bool?) ?? false,
      linkId: json['link_id'] as int,
      status: (json['status'] as String?) ?? 'PENDING',
      elderId: json['elder_id'] as int,
      elderUsername: (json['elder_username'] as String?) ?? '',
      elderNickname: json['elder_nickname'] as String?,
    );
  }
}

class ProxyRegisterResultDto {
  ProxyRegisterResultDto({
    required this.elderUserId,
    required this.username,
    required this.activationCode,
  });

  final int elderUserId;
  final String username;
  final String activationCode;

  factory ProxyRegisterResultDto.fromJson(Map<String, dynamic> json) {
    return ProxyRegisterResultDto(
      elderUserId: json['elder_user_id'] as int,
      username: (json['username'] as String?) ?? '',
      activationCode: (json['activation_code'] as String?) ?? '',
    );
  }
}

class ActivateElderResultDto {
  ActivateElderResultDto({
    required this.username,
    this.firebaseCustomToken,
    this.accessToken,
  });

  final String username;
  final String? firebaseCustomToken;
  final String? accessToken;
}

class CurrentUserProfileDto {
  CurrentUserProfileDto({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.avatarUrl,
    this.isPremium = false,
    this.premiumExpiresAt,
    this.proIsFamilyShare = false,
  });

  final int id;
  final String username;
  final String nickname;
  final String email;
  final String? avatarUrl;
  final bool isPremium;
  final DateTime? premiumExpiresAt;
  final bool proIsFamilyShare;

  factory CurrentUserProfileDto.fromJson(Map<String, dynamic> json) {
    final rawExpires = json['premium_expires_at'];
    DateTime? expiresAt;
    if (rawExpires is String && rawExpires.trim().isNotEmpty) {
      expiresAt = DateTime.tryParse(rawExpires)?.toLocal();
    }
    return CurrentUserProfileDto(
      id: json['id'] as int,
      username: (json['username'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      avatarUrl: json['avatar_url'] as String?,
      isPremium: json['is_premium'] as bool? ?? false,
      premiumExpiresAt: expiresAt,
      proIsFamilyShare: json['pro_is_family_share'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'nickname': nickname,
      'email': email,
      'avatar_url': avatarUrl,
    };
  }
}

class FamilyLinkDto {
  FamilyLinkDto({
    required this.id,
    required this.linkId,
    required this.elderId,
    required this.caregiverId,
    required this.status,
    required this.permissions,
    required this.elderUsername,
    required this.caregiverUsername,
    required this.elderAlias,
    required this.caregiverAlias,
    required this.elderAvatarUrl,
    required this.caregiverAvatarUrl,
    this.caregiverNickname,
    this.caregiverEmail,
  });

  final int id;
  final int linkId;
  final int elderId;
  final int caregiverId;
  final String status;
  final String permissions;
  final String elderUsername;
  final String caregiverUsername;
  final String? elderAlias;
  final String? caregiverAlias;
  final String? elderAvatarUrl;
  final String? caregiverAvatarUrl;
  final String? caregiverNickname;
  final String? caregiverEmail;

  factory FamilyLinkDto.fromJson(Map<String, dynamic> json) {
    return FamilyLinkDto(
      id: json['id'] as int,
      linkId: (json['link_id'] as int?) ?? (json['id'] as int),
      elderId: json['elder_id'] as int,
      caregiverId: json['caregiver_id'] as int,
      status: json['status'] as String,
      permissions: json['permissions'] as String,
      elderUsername: json['elder_username'] as String? ?? '',
      caregiverUsername: json['caregiver_username'] as String? ?? '',
      elderAlias: json['elder_alias'] as String?,
      caregiverAlias: json['caregiver_alias'] as String?,
      elderAvatarUrl: json['elder_avatar_url'] as String?,
      caregiverAvatarUrl: json['caregiver_avatar_url'] as String?,
      caregiverNickname: json['caregiver_nickname'] as String?,
      caregiverEmail: json['caregiver_email'] as String?,
    );
  }
}

class ApprovedElderDto {
  ApprovedElderDto({
    required this.linkId,
    required this.elderId,
    required this.elderUsername,
    required this.caregiverUsername,
    required this.elderAlias,
    required this.elderAvatarUrl,
    required this.receiveWeeklyReport,
    required this.elderIsProxy,
    this.elderHasActivePro = false,
    this.elderProShareLockedOther = false,
  });

  final int linkId;
  final int elderId;
  final String elderUsername;
  final String caregiverUsername;
  final String? elderAlias;
  final String? elderAvatarUrl;
  final bool receiveWeeklyReport;
  final bool elderIsProxy;
  final bool elderHasActivePro;
  final bool elderProShareLockedOther;

  factory ApprovedElderDto.fromJson(Map<String, dynamic> json) {
    return ApprovedElderDto(
      linkId: json['link_id'] as int,
      elderId: json['elder_id'] as int,
      elderUsername: json['elder_username'] as String,
      caregiverUsername: json['caregiver_username'] as String? ?? '',
      elderAlias: json['elder_alias'] as String?,
      elderAvatarUrl: json['elder_avatar_url'] as String?,
      receiveWeeklyReport: (json['receive_weekly_report'] as bool?) ?? true,
      elderIsProxy: (json['elder_is_proxy'] as bool?) ?? false,
      elderHasActivePro: (json['elder_has_active_pro'] as bool?) ?? false,
      elderProShareLockedOther: (json['elder_pro_share_locked_other'] as bool?) ?? false,
    );
  }
}

class ApprovedCaregiverDto {
  ApprovedCaregiverDto({
    required this.linkId,
    required this.caregiverId,
    required this.caregiverUsername,
    required this.caregiverNickname,
    required this.elderAlias,
    required this.caregiverAlias,
    required this.caregiverAvatarUrl,
  });

  final int linkId;
  final int caregiverId;
  final String caregiverUsername;
  final String? caregiverNickname;
  final String? elderAlias;
  final String? caregiverAlias;
  final String? caregiverAvatarUrl;

  factory ApprovedCaregiverDto.fromJson(Map<String, dynamic> json) {
    return ApprovedCaregiverDto(
      linkId: json['link_id'] as int,
      caregiverId: json['caregiver_id'] as int,
      caregiverUsername: json['caregiver_username'] as String,
      caregiverNickname: json['caregiver_nickname'] as String?,
      elderAlias: json['elder_alias'] as String?,
      caregiverAlias: json['caregiver_alias'] as String?,
      caregiverAvatarUrl: json['caregiver_avatar_url'] as String?,
    );
  }
}

class ProShareSharedUserDto {
  ProShareSharedUserDto({
    required this.userId,
    this.nickname,
    this.avatarUrl,
    this.isProxy = false,
  });

  final int userId;
  final String? nickname;
  final String? avatarUrl;
  final bool isProxy;

  factory ProShareSharedUserDto.fromJson(Map<String, dynamic> json) {
    return ProShareSharedUserDto(
      userId: json['user_id'] as int,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isProxy: (json['is_proxy'] as bool?) ?? false,
    );
  }
}

class ProShareStatusDto {
  ProShareStatusDto({
    required this.maxShares,
    required this.usedShares,
    required this.sharedUsers,
  });

  final int maxShares;
  final int usedShares;
  final List<ProShareSharedUserDto> sharedUsers;

  factory ProShareStatusDto.fromJson(Map<String, dynamic> json) {
    final raw = json['shared_users'] as List<dynamic>? ?? [];
    return ProShareStatusDto(
      maxShares: (json['max_shares'] as int?) ?? 0,
      usedShares: (json['used_shares'] as int?) ?? 0,
      sharedUsers: raw
          .map((e) => ProShareSharedUserDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

extension ApiServiceFamily on ApiService {
  Future<ProxyRegisterResultDto> proxyRegisterElder({
    required String nickname,
    String? elderAlias,
  }) async {
    final res = await post(
      '/auth/proxy-register',
      body: {
        'nickname': nickname.trim(),
        'elder_alias': elderAlias?.trim(),
      },
    );
    if (res.statusCode != 201) {
      throw Exception('proxyRegisterElder failed: ${res.statusCode} ${res.body}');
    }
    return ProxyRegisterResultDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Public (no auth). Validates code + expiry on server before showing password step.
  Future<void> validateActivationCode(String activationCode) async {
    final res = await post(
      '/auth/activate/validate',
      body: {'activation_code': activationCode.trim().toUpperCase()},
    );
    if (res.statusCode != 200) {
      throw Exception(
        'validateActivationCode failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  Future<ActivateElderResultDto> activateElderAccount({
    required String activationCode,
    required String newPassword,
  }) async {
    final res = await post(
      '/auth/activate',
      body: {
        'activation_code': activationCode.trim().toUpperCase(),
        'new_password': newPassword,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('activateElderAccount failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final customToken = data['firebase_custom_token'] as String?;
    final jwt = data['access_token'] as String?;
    final username = data['username'] as String?;
    if (username == null || username.isEmpty) {
      throw Exception('activateElderAccount failed: invalid username response');
    }
    final hasFirebase = customToken != null && customToken.isNotEmpty;
    final hasJwt = jwt != null && jwt.isNotEmpty;
    if (!hasFirebase && !hasJwt) {
      throw Exception('activateElderAccount failed: no auth token in response');
    }
    return ActivateElderResultDto(
      username: username,
      firebaseCustomToken: hasFirebase ? customToken : null,
      accessToken: hasJwt ? jwt : null,
    );
  }

  Future<ProShareStatusDto> getProShareStatus() async {
    final res = await get('/pro/shares/my');
    if (res.statusCode != 200) {
      throw Exception('getProShareStatus failed: ${res.statusCode} ${res.body}');
    }
    return ProShareStatusDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<void> addProShare(int targetUserId) async {
    final res = await post(
      '/pro/shares',
      body: {'target_user_id': targetUserId},
    );
    if (res.statusCode != 201) {
      throw Exception('addProShare failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> removeProShare(int targetUserId) async {
    final res = await delete('/pro/shares/$targetUserId');
    if (res.statusCode != 204) {
      throw Exception('removeProShare failed: ${res.statusCode} ${res.body}');
    }
  }

  /// Username + password login for family-code accounts (e.g. zellia_2511).
  /// Returns a Firebase Custom Token so the caller can use signInWithCustomToken.
  /// Falls back to a backend JWT (accessToken) if the server cannot mint a custom token.
  Future<ActivateElderResultDto> loginWithUsername({
    required String username,
    required String password,
  }) async {
    final res = await post(
      '/auth/username-token',
      body: {'username': username.trim(), 'password': password},
    );
    if (res.statusCode == 401) {
      throw Exception('incorrect_credentials');
    }
    if (res.statusCode != 200) {
      throw Exception('loginWithUsername failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final customToken = data['firebase_custom_token'] as String?;
    final jwt = data['access_token'] as String?;
    final usernameResult = (data['username'] as String?) ?? username;
    final hasFirebase = customToken != null && customToken.isNotEmpty;
    final hasJwt = jwt != null && jwt.isNotEmpty;
    if (!hasFirebase && !hasJwt) {
      throw Exception('loginWithUsername failed: no auth token in response');
    }
    return ActivateElderResultDto(
      username: usernameResult,
      firebaseCustomToken: hasFirebase ? customToken : null,
      accessToken: hasJwt ? jwt : null,
    );
  }

  Future<void> resetElderPassword({
    required int elderId,
    required String tempPassword,
  }) async {
    final res = await post(
      '/family/reset-elder-password',
      body: {
        'elder_id': elderId,
        'temp_password': tempPassword,
      },
    );
    if (res.statusCode != 200) {
      throw Exception('resetElderPassword failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<CurrentUserProfileDto> getCurrentUserProfile() async {
    final res = await get('/auth/me');
    if (res.statusCode != 200) {
      throw Exception(
        'getCurrentUserProfile failed: ${res.statusCode} ${res.body}',
      );
    }
    return CurrentUserProfileDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<CurrentUserProfileDto> updateCurrentUserProfile({
    required String nickname,
    required String email,
    String? avatarUrl,
  }) async {
    final res = await put(
      '/auth/me',
      body: {'nickname': nickname, 'email': email, 'avatar_url': avatarUrl},
    );
    if (res.statusCode != 200) {
      throw Exception(
        'updateCurrentUserProfile failed: ${res.statusCode} ${res.body}',
      );
    }
    return CurrentUserProfileDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<FamilyInviteCodeDto> getMyInviteCode() async {
    final res = await get('/family/invite-code');
    if (res.statusCode != 200) {
      throw Exception('getMyInviteCode failed: ${res.statusCode} ${res.body}');
    }
    return FamilyInviteCodeDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<FamilyQrTokenDto> getFamilyQrToken() async {
    final res = await get('/family/qr-token');
    if (res.statusCode != 200) {
      throw Exception('getFamilyQrToken failed: ${res.statusCode} ${res.body}');
    }
    return FamilyQrTokenDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<FamilyLinkDto> applyFamilyLinkByCode(
    String inviteCode, {
    String? elderAlias,
  }) async {
    final res = await post(
      '/family/apply',
      body: {'invite_code': inviteCode, 'elder_alias': elderAlias},
    );
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception(
        'applyFamilyLinkByCode failed: ${res.statusCode} ${res.body}',
      );
    }
    return FamilyLinkDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<ScanQrBindResultDto> scanFamilyQr({
    required String token,
    String? familyAlias,
  }) async {
    final res = await post(
      '/family/scan-qr',
      body: {'token': token.trim(), 'family_alias': familyAlias?.trim()},
    );
    if (res.statusCode != 200) {
      throw Exception('scanFamilyQr failed: ${res.statusCode} ${res.body}');
    }
    return ScanQrBindResultDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<List<FamilyLinkDto>> getPendingFamilyRequests() async {
    final res = await get('/family/requests');
    if (res.statusCode != 200) {
      throw Exception(
        'getPendingFamilyRequests failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => FamilyLinkDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FamilyLinkDto> decideFamilyRequest({
    required int linkId,
    required bool approved,
    String? caregiverAlias,
  }) async {
    final res = await post(
      '/family/requests/$linkId/decision',
      body: {'approved': approved, 'caregiver_alias': caregiverAlias},
    );
    if (res.statusCode != 200) {
      throw Exception(
        'decideFamilyRequest failed: ${res.statusCode} ${res.body}',
      );
    }
    return FamilyLinkDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ApprovedElderDto>> getApprovedElders() async {
    final res = await get('/family/approved-elders');
    if (res.statusCode != 200) {
      throw Exception(
        'getApprovedElders failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => ApprovedElderDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ApprovedCaregiverDto>> getApprovedCaregivers() async {
    final res = await get('/family/guardians');
    if (res.statusCode != 200) {
      throw Exception(
        'getApprovedCaregivers failed: ${res.statusCode} ${res.body}',
      );
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => ApprovedCaregiverDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> unbindFamilyLink(int linkId) async {
    final res = await delete('/family/unbind/$linkId');
    if (res.statusCode != 204) {
      throw Exception('unbindFamilyLink failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<ApprovedElderDto> setWeeklyReportSubscription({
    required int linkId,
    required bool enabled,
  }) async {
    final res = await post(
      '/family/links/$linkId/weekly-report',
      body: {'receive_weekly_report': enabled},
    );
    if (res.statusCode != 200) {
      throw Exception(
        'setWeeklyReportSubscription failed: ${res.statusCode} ${res.body}',
      );
    }
    return ApprovedElderDto.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }
}

extension ApiServiceReports on ApiService {
  Future<Map<String, dynamic>> getClinicalSummaryReport({
    int days = 30,
    int? targetUserId,
  }) async {
    final path = _withQuery('/reports/clinical-summary', {
      'days': days,
      'target_user_id': targetUserId,
    });
    final res = await get(path);
    if (res.statusCode != 200) {
      if (res.statusCode == 403) {
        var msg = '此功能仅限 PRO 用户使用';
        try {
          final map = jsonDecode(res.body) as Map<String, dynamic>;
          final detail = map['detail'];
          if (detail is String && detail.isNotEmpty) msg = detail;
        } catch (_) {}
        throw Exception(msg);
      }
      throw Exception(
        'getClinicalSummaryReport failed: ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}

extension ApiServiceNotifications on ApiService {
  Future<void> upsertDeviceToken({
    String? fcmToken,
    String? wxpusherUid,
    String? deviceLabel,
  }) async {
    final res = await post(
      '/notifications/device-token',
      body: {
        'fcm_token': fcmToken,
        'wxpusher_uid': wxpusherUid,
        'device_label': deviceLabel,
      },
    );
    if (res.statusCode != 200) {
      throw Exception(
        'upsertDeviceToken failed: ${res.statusCode} ${res.body}',
      );
    }
  }
}

