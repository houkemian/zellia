import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_service.dart';
import '../services/pdf_service.dart';
import '../widgets/weekly_summary/weekly_summary_ring.dart';
import '../widgets/weekly_summary/weekly_summary_vitals_strip.dart';

class WeeklySummaryScreen extends StatefulWidget {
  const WeeklySummaryScreen({
    super.key,
    required this.api,
    required this.elderId,
    this.weekStart,
    this.elderDisplayName,
    this.dataUrl,
    this.isFrozen = false,
    this.isoYear,
    this.isoWeek,
  });

  final ApiService api;
  final int elderId;
  final String? weekStart;
  final String? elderDisplayName;
  /// Live: `/reports/weekly-summary?...` or frozen: full R2 HTTPS URL.
  final String? dataUrl;
  final bool isFrozen;
  final int? isoYear;
  final int? isoWeek;

  @override
  State<WeeklySummaryScreen> createState() => _WeeklySummaryScreenState();
}

class _WeeklySummaryScreenState extends State<WeeklySummaryScreen> {
  final PdfService _pdfService = PdfService();
  Map<String, dynamic>? _summary;
  bool _loading = true;
  String? _error;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _text(String zh, String en) {
    final locale = Localizations.localeOf(context).languageCode.toLowerCase();
    return locale.startsWith('zh') ? zh : en;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _resolveSummaryData();
      if (!mounted) return;
      setState(() => _summary = data);
    } on _FrozenSummaryMissingException {
      if (!mounted) return;
      setState(
        () => _error = _text('该周数据未生成', 'Report for this week is not available'),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (_isSnapshotUnavailableError(msg)) {
        setState(
          () => _error = _text('该周数据未生成', 'Report for this week is not available'),
        );
      } else {
        setState(() => _error = msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isAbsoluteHttpUrl(String url) {
    final lower = url.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  bool _isApiWeeklySummaryUrl(String url) {
    return url.contains('/reports/weekly-summary');
  }

  bool _shouldLoadFrozenSnapshot(String url) {
    return widget.isFrozen &&
        url.isNotEmpty &&
        _isAbsoluteHttpUrl(url) &&
        !_isApiWeeklySummaryUrl(url);
  }

  bool _isSnapshotUnavailableError(String message) {
    return message.contains('404') ||
        message.contains('400') ||
        message.contains('403') ||
        message.contains('not available') ||
        message.contains('未生成');
  }

  /// Live list uses relative API paths; frozen weeks use public R2 HTTPS URLs.
  Future<Map<String, dynamic>> _resolveSummaryData() async {
    final url = (widget.dataUrl ?? '').trim();

    if (_shouldLoadFrozenSnapshot(url)) {
      return _fetchFrozenSummaryFromR2(url);
    }

    if (url.startsWith('/')) {
      return _loadFromApiPath(url);
    }

    if (_isAbsoluteHttpUrl(url) && _isApiWeeklySummaryUrl(url)) {
      final uri = Uri.parse(url);
      final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      return _loadFromApiPath(path);
    }

    return widget.api.getWeeklySummaryReport(
      targetUserId: widget.elderId,
      days: 7,
      isoYear: widget.isoYear,
      isoWeek: widget.isoWeek,
    );
  }

  Future<Map<String, dynamic>> _loadFromApiPath(String path) async {
    final res = await widget.api.get(path);
    if (res.statusCode != 200) {
      throw Exception(
        'getWeeklySummaryReport failed: ${res.statusCode} ${res.body}',
      );
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _fetchFrozenSummaryFromR2(String url) async {
    final res = await http
        .get(
          Uri.parse(url),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }

    if (res.statusCode == 404 || res.statusCode == 400 || res.statusCode == 403) {
      throw _FrozenSummaryMissingException();
    }

    throw Exception('Frozen weekly summary HTTP ${res.statusCode}');
  }

  String _displayName(Map<String, dynamic> summary) {
    final patient = summary['patient'] as Map<String, dynamic>? ?? const {};
    final nickname = (patient['nickname'] as String?)?.trim();
    final username = (patient['username'] as String?)?.trim();
    if (nickname != null && nickname.isNotEmpty) return nickname;
    if (username != null && username.isNotEmpty) return username;
    return widget.elderDisplayName ?? _text('家人', 'Family member');
  }

  String _headline(Map<String, dynamic> summary) {
    final med = summary['medication'] as Map<String, dynamic>? ?? const {};
    final missed = (med['missed_count'] as num?)?.toInt() ?? 0;
    final pct = (med['adherence_percent'] as num?)?.toDouble() ?? 0;
    final bp = summary['blood_pressure'] as Map<String, dynamic>? ?? const {};
    final bs = summary['blood_sugar'] as Map<String, dynamic>? ?? const {};
    final abn =
        ((bp['abnormal_count'] as num?)?.toInt() ?? 0) +
        ((bs['abnormal_count'] as num?)?.toInt() ?? 0);

    if (missed == 0 && pct >= 95 && abn == 0) {
      return _text('本周悉心守护完成！', 'A caring week, well done!');
    }
    if (missed > 0) {
      return _text('多一点关注，多一份安心', 'A little more care goes a long way');
    }
    if (abn > 0) {
      return _text('本周有些波动，值得一起看看', 'Some changes worth reviewing together');
    }
    return _text('本周健康小结', 'This week\'s health summary');
  }

  String _periodLabel(Map<String, dynamic> summary) {
    final period = summary['period'] as Map<String, dynamic>? ?? const {};
    final start = period['start_date'] as String? ?? '';
    final end = period['end_date'] as String? ?? '';
    if (start.isEmpty || end.isEmpty) {
      return _text('过去 7 天', 'Past 7 days');
    }
    return '$start — $end';
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final reportData = await widget.api.getClinicalSummaryReport(
        days: 7,
        targetUserId: widget.elderId,
      );
      final patient = reportData['patient'] as Map<String, dynamic>? ?? const {};
      final nickname = (patient['nickname'] as String?)?.trim();
      final username = (patient['username'] as String?)?.trim();
      final name = (nickname != null && nickname.isNotEmpty)
          ? nickname
          : ((username != null && username.isNotEmpty)
                ? username
                : _displayName(_summary ?? const {}));
      final languageCode = Localizations.localeOf(context).languageCode;
      final bytes = await _pdfService.buildClinicalReportPdfBytes(
        reportData,
        name,
        languageCode: languageCode,
      );
      await _pdfService.shareClinicalReportBytes(
        bytes,
        name,
        languageCode: languageCode,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_text('导出失败: $e', 'Export failed: $e'))),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text(_text('本周健康总结', 'Weekly health summary')),
        backgroundColor: const Color(0xFFF6F8FB),
        elevation: 0,
        foregroundColor: const Color(0xFF1D2B45),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorBody(message: _error!, onRetry: _load, retryLabel: _text('重试', 'Retry'))
          : _buildContent(_summary!),
    );
  }

  Widget _buildContent(Map<String, dynamic> summary) {
    final med = summary['medication'] as Map<String, dynamic>? ?? const {};
    final bp = summary['blood_pressure'] as Map<String, dynamic>? ?? const {};
    final bs = summary['blood_sugar'] as Map<String, dynamic>? ?? const {};
    final pct = (med['adherence_percent'] as num?)?.toDouble() ?? 0;
    final taken = (med['taken_count'] as num?)?.toInt() ?? 0;
    final total = (med['total_tasks'] as num?)?.toInt() ?? 0;
    final missed = (med['missed_count'] as num?)?.toInt() ?? 0;
    final name = _displayName(summary);

    final sys = bp['average_systolic'];
    final dia = bp['average_diastolic'];
    final hr = bp['average_heart_rate'];
    final bpCount = (bp['record_count'] as num?)?.toInt() ?? 0;
    final bpAbn = (bp['abnormal_count'] as num?)?.toInt() ?? 0;

    final bsAvg = bs['average_level'];
    final bsCount = (bs['record_count'] as num?)?.toInt() ?? 0;
    final bsAbn = (bs['abnormal_count'] as num?)?.toInt() ?? 0;

    String bpValue;
    if (sys != null && dia != null) {
      bpValue = '${(sys as num).toStringAsFixed(0)}/${(dia as num).toStringAsFixed(0)}';
    } else {
      bpValue = _text('暂无记录', 'No readings');
    }

    String bsValue;
    if (bsAvg != null) {
      bsValue = '${(bsAvg as num).toStringAsFixed(1)} mmol/L';
    } else {
      bsValue = _text('暂无记录', 'No readings');
    }

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _headline(summary),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: const Color(0xFF1D2B45),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _text('$name · ${_periodLabel(summary)}', '$name · ${_periodLabel(summary)}'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5B6B88),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Card(
                    elevation: 0,
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE5EBF3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Text(
                            _text('用药完成率', 'Medication adherence'),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFF44546F),
                            ),
                          ),
                          const SizedBox(height: 16),
                          WeeklySummaryRing(percent: pct),
                          const SizedBox(height: 12),
                          Text(
                            _text(
                              '已打卡 $taken / 计划 $total',
                              'Taken $taken / planned $total',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6F7F99),
                            ),
                          ),
                          if (missed > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              _text('本周漏服 $missed 次', 'Missed $missed dose(s) this week'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFFE65100),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _text('体征概览', 'Vitals overview'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF44546F),
                    ),
                  ),
                  const SizedBox(height: 12),
                  WeeklySummaryVitalsStrip(
                    label: _text('平均血压', 'Average blood pressure'),
                    valueText: bpValue,
                    subtitle: bpCount > 0
                        ? _text(
                            '$bpCount 次记录 · 异常 $bpAbn 次',
                            '$bpCount reading(s) · $bpAbn abnormal',
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (hr != null)
                    WeeklySummaryVitalsStrip(
                      label: _text('平均心率', 'Average heart rate'),
                      valueText: '${(hr as num).toStringAsFixed(0)} bpm',
                      accentColor: const Color(0xFF90CAF9),
                    ),
                  if (hr != null) const SizedBox(height: 10),
                  WeeklySummaryVitalsStrip(
                    label: _text('平均血糖', 'Average blood sugar'),
                    valueText: bsValue,
                    subtitle: bsCount > 0
                        ? _text(
                            '$bsCount 次记录 · 异常 $bsAbn 次',
                            '$bsCount reading(s) · $bsAbn abnormal',
                          )
                        : null,
                    accentColor: const Color(0xFFFFCC80),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _text(
                        '数据仅供家庭健康管理与复诊参考，如有不适请及时就医。',
                        'For family wellness and clinical reference only. Seek care when needed.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF3D5A50),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _exportPdf,
                icon: _exporting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _text('导出为 PDF 发给医生', 'Export PDF for doctor'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrozenSummaryMissingException implements Exception {}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({
    required this.message,
    required this.onRetry,
    required this.retryLabel,
  });

  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
