import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/api_service.dart';
import '../services/family_voice_upload_service.dart';

/// Bottom sheet: hold to record (max 10s), preview, save → R2 direct upload.
class FamilyVoiceRecorderSheet extends StatefulWidget {
  const FamilyVoiceRecorderSheet({
    super.key,
    required this.api,
    required this.planId,
    required this.targetUserId,
    required this.planName,
  });

  final ApiService api;
  final int planId;
  final int targetUserId;
  final String planName;

  static Future<bool?> show(
    BuildContext context, {
    required ApiService api,
    required int planId,
    required int targetUserId,
    required String planName,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: FamilyVoiceRecorderSheet(
          api: api,
          planId: planId,
          targetUserId: targetUserId,
          planName: planName,
        ),
      ),
    );
  }

  @override
  State<FamilyVoiceRecorderSheet> createState() =>
      _FamilyVoiceRecorderSheetState();
}

class _FamilyVoiceRecorderSheetState extends State<FamilyVoiceRecorderSheet> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  static const _maxSeconds = 10;

  String? _recordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _saving = false;
  String? _error;
  Timer? _recordTimer;
  int _recordElapsed = 0;

  @override
  void dispose() {
    _recordTimer?.cancel();
    unawaited(_recorder.dispose());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<bool> _ensureMicrophonePermission() async {
    try {
      var status = await Permission.microphone.status;
      if (status.isGranted) return true;
      status = await Permission.microphone.request();
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        setState(() => _error = '请在系统设置中开启麦克风权限');
      } else {
        setState(() => _error = '需要麦克风权限才能录制亲情语音');
      }
      return false;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('mic permission error: $e\n$st');
      }
      setState(() => _error = '无法请求麦克风权限: $e');
      return false;
    }
  }

  Future<void> _startRecording() async {
    if (_isRecording || _saving) return;
    setState(() {
      _error = null;
      _recordingPath = null;
    });

    if (!await _ensureMicrophonePermission()) return;

    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = '录音设备不可用');
        return;
      }
      final path = '${Directory.systemTemp.path}/zellia_voice_${widget.planId}_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );
      setState(() {
        _isRecording = true;
        _recordElapsed = 0;
        _recordingPath = path;
      });
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) return;
        setState(() => _recordElapsed++);
        if (_recordElapsed >= _maxSeconds) {
          await _stopRecording();
        }
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('record start failed: $e\n$st');
      }
      setState(() => _error = '开始录音失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    _recordTimer?.cancel();
    try {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _recordingPath = path ?? _recordingPath;
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('record stop failed: $e\n$st');
      }
      setState(() {
        _isRecording = false;
        _error = '停止录音失败: $e';
      });
    }
  }

  Future<void> _togglePreview() async {
    final path = _recordingPath;
    if (path == null || !File(path).existsSync()) {
      setState(() => _error = '请先录制一段语音');
      return;
    }
    try {
      if (_isPlaying) {
        await _player.stop();
        setState(() => _isPlaying = false);
        return;
      }
      await _player.play(DeviceFileSource(path));
      setState(() => _isPlaying = true);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _isPlaying = false);
      });
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('preview failed: $e\n$st');
      }
      setState(() => _error = '播放预览失败: $e');
    }
  }

  Future<void> _save() async {
    final path = _recordingPath;
    if (path == null || !File(path).existsSync()) {
      setState(() => _error = '请先按住录音按钮录制');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await FamilyVoiceUploadService(widget.api).uploadRecordedVoice(
        planId: widget.planId,
        targetUserId: widget.targetUserId,
        recordingFile: File(path),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('voice save failed: $e\n$st');
      }
      setState(() => _error = '保存失败: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '🎙️ 亲情语音提醒',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0C5B49),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '为「${widget.planName}」录制最多 $_maxSeconds 秒语音，长辈服药时将听到您的声音。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
                onLongPressCancel: () => _stopRecording(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording
                        ? theme.colorScheme.error
                        : const Color(0xFF0E6A55),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _isRecording
                    ? '录音中 $_recordElapsed / $_maxSeconds 秒…'
                    : '按住录音，松开结束',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_saving || _isRecording) ? null : _togglePreview,
                    icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                    label: Text(_isPlaying ? '停止' : '预览'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '上传中…' : '保存'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
