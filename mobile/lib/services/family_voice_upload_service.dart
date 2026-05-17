import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Caregiver flow: presign from API → PUT bytes to R2 → PATCH metadata.
class FamilyVoiceUploadService {
  FamilyVoiceUploadService(this._api);

  final ApiService _api;
  final Dio _dio = Dio();

  Future<void> uploadRecordedVoice({
    required int planId,
    required int targetUserId,
    required File recordingFile,
  }) async {
    if (!await recordingFile.exists()) {
      throw StateError('Recording file not found');
    }
    final bytes = await recordingFile.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Recording is empty');
    }

    late final VoiceUploadUrlDto presign;
    try {
      presign = await _api.getVoiceUploadUrl(
        planId: planId,
        userId: targetUserId,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('family voice: presign failed: $e\n$st');
      }
      rethrow;
    }

    try {
      final putResponse = await _dio.put<void>(
        presign.uploadUrl,
        data: bytes,
        options: Options(
          headers: {'Content-Type': presign.contentType},
          validateStatus: (code) => code != null && code >= 200 && code < 300,
        ),
      );
      if (putResponse.statusCode == null ||
          putResponse.statusCode! < 200 ||
          putResponse.statusCode! >= 300) {
        throw StateError('R2 upload failed: HTTP ${putResponse.statusCode}');
      }
    } on DioException catch (e, st) {
      if (kDebugMode) {
        debugPrint('family voice: R2 PUT failed: ${e.message}\n$st');
      }
      throw StateError('Upload to storage failed: ${e.message}');
    }

    try {
      await _api.patchMedicationPlanVoice(
        planId: planId,
        voiceUrl: presign.voiceUrl,
        targetUserId: targetUserId,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('family voice: PATCH failed: $e\n$st');
      }
      rethrow;
    }
  }
}
