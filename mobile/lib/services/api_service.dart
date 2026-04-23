import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

int? currentViewUserId;
String? currentViewUserName;

/// Central HTTP client for Zellia. Intercepts 401 and notifies [onUnauthorized].
class ApiService {
  ApiService({
    required String baseUrl,
    this.onUnauthorized,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), '');

  static const String tokenKey = 'ever_well_token';

  final String baseUrl;
  final void Function()? onUnauthorized;

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
    final preview = res.body.length > 300 ? '${res.body.substring(0, 300)}...' : res.body;
    debugPrint('[API][$method][${res.statusCode}] $url');
    debugPrint('[API][$method][RESP] $preview');
  }

  Future<Map<String, String>> _headers({bool jsonBody = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(tokenKey);
    return {
      if (jsonBody) 'Content-Type': 'application/json; charset=utf-8',
      if (jsonBody) 'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> saveToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(tokenKey);
    } else {
      await prefs.setString(tokenKey, token);
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  Future<http.Response> get(String path) async {
    final url = _url(path);
    _logRequest('GET', url);
    final res = await http.get(url, headers: await _headers(jsonBody: false));
    _logResponse('GET', url, res);
    _handleUnauthorized(res);
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
    _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> postForm(String path, Map<String, String> fields) async {
    final url = _url(path);
    _logRequest('POST_FORM', url, body: fields);
    final token = await getToken();
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final res = await http.post(url, headers: headers, body: fields);
    _logResponse('POST_FORM', url, res);
    _handleUnauthorized(res);
    return res;
  }

  Future<http.Response> delete(String path) async {
    final url = _url(path);
    _logRequest('DELETE', url);
    final res = await http.delete(url, headers: await _headers(jsonBody: false));
    _logResponse('DELETE', url, res);
    _handleUnauthorized(res);
    return res;
  }

  void _handleUnauthorized(http.Response response) {
    if (response.statusCode == 401) {
      onUnauthorized?.call();
    }
  }
}

class MedicationPlanCreateDto {
  MedicationPlanCreateDto({
    required this.name,
    required this.dosage,
    required this.startDate,
    required this.endDate,
    required this.timesADay,
  });

  final String name;
  final String dosage;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> timesADay;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dosage': dosage,
      'start_date': DateFormat('yyyy-MM-dd').format(startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(endDate),
      'times_a_day': timesADay.join(','),
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
  });

  final int planId;
  final String name;
  final String dosage;
  final String scheduledTime;
  final DateTime takenDate;
  final int? logId;
  final bool isTaken;
  final String? checkedAt;

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
      throw Exception('createMedicationPlan failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<List<TodayMedicationItemDto>> getTodayMedications({int? targetUserId}) async {
    final path = _withQuery('/medications/today', {'target_user_id': targetUserId});
    final res = await get(path);
    if (res.statusCode != 200) {
      throw Exception('getTodayMedications failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => TodayMedicationItemDto.fromJson(e as Map<String, dynamic>)).toList();
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
    final takenDateOnly = DateTime(takenDate.year, takenDate.month, takenDate.day);
    final payload = {
      'taken_date': DateFormat('yyyy-MM-dd').format(takenDateOnly),
      'taken_time': '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
      'is_taken': isTaken,
    };
    final res = await post('/medications/$planId/log', body: payload);
    if (res.statusCode != 200) {
      throw Exception('toggleMedicationLog failed: ${res.statusCode} ${res.body}');
    }
  }

  Future<void> stopMedicationPlan(int planId) async {
    final res = await delete('/medications/plan/$planId');
    if (res.statusCode != 204) {
      throw Exception('stopMedicationPlan failed: ${res.statusCode} ${res.body}');
    }
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
      measuredAt: DateTime.parse(json['measured_at'] as String),
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
      measuredAt: DateTime.parse(json['measured_at'] as String),
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
        'measured_at': measuredAt.toIso8601String(),
      },
    );
    if (res.statusCode != 201) {
      throw Exception('createBloodPressure failed: ${res.statusCode} ${res.body}');
    }
    return BloodPressureRecordDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
      throw Exception('getBloodPressureHistory failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => BloodPressureRecordDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteBloodPressureRecord(int id) async {
    final res = await delete('/vitals/bp/$id');
    if (res.statusCode != 204) {
      throw Exception('deleteBloodPressureRecord failed: ${res.statusCode} ${res.body}');
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
        'measured_at': measuredAt.toIso8601String(),
      },
    );
    if (res.statusCode != 201) {
      throw Exception('createBloodSugar failed: ${res.statusCode} ${res.body}');
    }
    return BloodSugarRecordDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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
      throw Exception('getBloodSugarHistory failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => BloodSugarRecordDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteBloodSugarRecord(int id) async {
    final res = await delete('/vitals/bs/$id');
    if (res.statusCode != 204) {
      throw Exception('deleteBloodSugarRecord failed: ${res.statusCode} ${res.body}');
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
  });

  final int linkId;
  final int elderId;
  final String elderUsername;
  final String caregiverUsername;
  final String? elderAlias;

  factory ApprovedElderDto.fromJson(Map<String, dynamic> json) {
    return ApprovedElderDto(
      linkId: json['link_id'] as int,
      elderId: json['elder_id'] as int,
      elderUsername: json['elder_username'] as String,
      caregiverUsername: json['caregiver_username'] as String? ?? '',
      elderAlias: json['elder_alias'] as String?,
    );
  }
}

class ApprovedCaregiverDto {
  ApprovedCaregiverDto({
    required this.linkId,
    required this.caregiverId,
    required this.caregiverUsername,
    required this.elderAlias,
    required this.caregiverAlias,
  });

  final int linkId;
  final int caregiverId;
  final String caregiverUsername;
  final String? elderAlias;
  final String? caregiverAlias;

  factory ApprovedCaregiverDto.fromJson(Map<String, dynamic> json) {
    return ApprovedCaregiverDto(
      linkId: json['link_id'] as int,
      caregiverId: json['caregiver_id'] as int,
      caregiverUsername: json['caregiver_username'] as String,
      elderAlias: json['elder_alias'] as String?,
      caregiverAlias: json['caregiver_alias'] as String?,
    );
  }
}

extension ApiServiceFamily on ApiService {
  Future<FamilyInviteCodeDto> getMyInviteCode() async {
    final res = await get('/family/invite-code');
    if (res.statusCode != 200) {
      throw Exception('getMyInviteCode failed: ${res.statusCode} ${res.body}');
    }
    return FamilyInviteCodeDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FamilyLinkDto> applyFamilyLinkByCode(String inviteCode, {String? elderAlias}) async {
    final res = await post('/family/apply', body: {
      'invite_code': inviteCode,
      'elder_alias': elderAlias,
    });
    if (res.statusCode != 201 && res.statusCode != 200) {
      throw Exception('applyFamilyLinkByCode failed: ${res.statusCode} ${res.body}');
    }
    return FamilyLinkDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<FamilyLinkDto>> getPendingFamilyRequests() async {
    final res = await get('/family/requests');
    if (res.statusCode != 200) {
      throw Exception('getPendingFamilyRequests failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => FamilyLinkDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FamilyLinkDto> decideFamilyRequest({
    required int linkId,
    required bool approved,
    String? caregiverAlias,
  }) async {
    final res = await post('/family/requests/$linkId/decision', body: {
      'approved': approved,
      'caregiver_alias': caregiverAlias,
    });
    if (res.statusCode != 200) {
      throw Exception('decideFamilyRequest failed: ${res.statusCode} ${res.body}');
    }
    return FamilyLinkDto.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<ApprovedElderDto>> getApprovedElders() async {
    final res = await get('/family/approved-elders');
    if (res.statusCode != 200) {
      throw Exception('getApprovedElders failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => ApprovedElderDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ApprovedCaregiverDto>> getApprovedCaregivers() async {
    final res = await get('/family/guardians');
    if (res.statusCode != 200) {
      throw Exception('getApprovedCaregivers failed: ${res.statusCode} ${res.body}');
    }
    final data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => ApprovedCaregiverDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> unbindFamilyLink(int linkId) async {
    final res = await delete('/family/unbind/$linkId');
    if (res.statusCode != 204) {
      throw Exception('unbindFamilyLink failed: ${res.statusCode} ${res.body}');
    }
  }
}
