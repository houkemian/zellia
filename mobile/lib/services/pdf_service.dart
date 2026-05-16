import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../utils/time_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

Future<Uint8List> buildClinicalReportPdfBytes(
  Map<String, dynamic> data,
  String patientName,
) {
  return PdfService().buildClinicalReportPdfBytes(data, patientName);
}

Future<void> shareClinicalReportBytes(Uint8List bytes, String patientName) {
  return PdfService().shareClinicalReportBytes(bytes, patientName);
}

Future<String> saveClinicalReportToDevice(Uint8List bytes, String patientName) {
  return PdfService().saveClinicalReportToDevice(bytes, patientName);
}

class PdfService {
  Future<Uint8List> buildClinicalReportPdfBytes(
    Map<String, dynamic> data,
    String patientName,
  ) async {
    final baseFont = await PdfGoogleFonts.notoSansSCRegular();
    final boldFont = await PdfGoogleFonts.notoSansSCBold();
    final pdf = pw.Document();
    final period = (data['period'] as Map<String, dynamic>? ?? const {});
    final patient = (data['patient'] as Map<String, dynamic>? ?? const {});
    final medicationAdherence =
        (data['medication_adherence'] as Map<String, dynamic>? ?? const {});
    final bpSummary =
        (data['blood_pressure_summary'] as Map<String, dynamic>? ?? const {});
    final bpRecords =
        (data['blood_pressure_records'] as List<dynamic>? ?? const []);
    final bsRecords =
        (data['blood_sugar_records'] as List<dynamic>? ?? const []);
    final reportDays = (data['days'] as num?)?.toInt() ?? 30;

    final adherencePercent =
        (medicationAdherence['percent'] as num?)?.toDouble() ?? 0;
    final avgSystolic = (bpSummary['average_systolic'] as num?)?.toDouble();
    final avgDiastolic = (bpSummary['average_diastolic'] as num?)?.toDouble();
    final avgHeartRate = (bpSummary['average_heart_rate'] as num?)?.toDouble();
    final periodStart = period['start_date']?.toString() ?? '';
    final periodEnd = period['end_date']?.toString() ?? '';
    final patientNickname = (patient['nickname'] as String?)?.trim();
    final reportPatientName =
        (patientNickname != null && patientNickname.isNotEmpty)
        ? patientNickname
        : patientName;
    final subtitle =
        '患者：$reportPatientName | 报告周期：近 $reportDays 天（$periodStart 至 $periodEnd）';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (context) => [
          pw.Text(
            'Zellia 个人健康报告',
            style: pw.TextStyle(font: boldFont, fontSize: 24),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            subtitle,
            style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _metricBlock(
                    label: '用药依从性',
                    value: '${adherencePercent.toStringAsFixed(1)}%',
                    emphasis: true,
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _metricBlock(
                    label: '平均血压',
                    value: (avgSystolic != null && avgDiastolic != null)
                        ? '${avgSystolic.toStringAsFixed(1)}/${avgDiastolic.toStringAsFixed(1)} mmHg'
                        : '暂无数据',
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _metricBlock(
                    label: '平均心率',
                    value: avgHeartRate != null
                        ? '${avgHeartRate.toStringAsFixed(1)} bpm'
                        : '暂无数据',
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            '血压记录（近 30 天）',
            style: pw.TextStyle(font: boldFont, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          _buildBpTable(bpRecords, boldFont),
          pw.SizedBox(height: 20),
          pw.Text(
            '血糖记录（近 30 天）',
            style: pw.TextStyle(font: boldFont, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          _buildBsTable(bsRecords, boldFont),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> shareClinicalReportBytes(Uint8List bytes, String patientName) async {
    final file = await _writeReportToTempFile(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Zellia 临床随访报告 - $patientName',
      subject: 'Zellia 临床随访报告',
    );
  }

  Future<String> saveClinicalReportToDevice(Uint8List bytes, String patientName) async {
    final now = DateTime.now();
    final fileTimestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final safeName = patientName.replaceAll(RegExp(r'[\\/:*?"<>| ]+'), '_');
    final fileName = 'zellia_clinical_report_${safeName}_$fileTimestamp.pdf';
    final baseDir = await _pickSaveDirectory();
    final file = File('${baseDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> generateAndShareClinicalReport(
    Map<String, dynamic> data,
    String patientName,
  ) async {
    final bytes = await buildClinicalReportPdfBytes(data, patientName);
    await shareClinicalReportBytes(bytes, patientName);
  }

  Future<File> _writeReportToTempFile(Uint8List bytes) async {
    final now = DateTime.now();
    final fileTimestamp = DateFormat('yyyyMMdd_HHmmss').format(now);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/zellia_clinical_report_$fileTimestamp.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<Directory> _pickSaveDirectory() async {
    final externalDir = await getExternalStorageDirectory();
    if (externalDir != null) {
      return externalDir;
    }
    return getApplicationDocumentsDirectory();
  }

  pw.Widget _metricBlock({
    required String label,
    required String value,
    bool emphasis = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: emphasis ? 22 : 16,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildBpTable(List<dynamic> rows, pw.Font boldFont) {
    if (rows.isEmpty) {
      return _emptyHint();
    }
    final headerStyle = pw.TextStyle(font: boldFont, fontSize: 10);
    const baseCellStyle = pw.TextStyle(fontSize: 10);
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _tableCell('日期时间', style: headerStyle),
          _tableCell('血压 (mmHg)', style: headerStyle),
          _tableCell('心率 (bpm)', style: headerStyle),
          _tableCell('状态', style: headerStyle),
        ],
      ),
    ];
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final systolic = (row['systolic'] as num?)?.toInt() ?? 0;
      final diastolic = (row['diastolic'] as num?)?.toInt() ?? 0;
      final hr = (row['heart_rate'] as num?)?.toInt();
      final measuredAt = _formatDateTime(row['measured_at']?.toString());
      final bpStatus = _bpStatus(systolic, diastolic, hr);
      final valueColor = _statusColor(bpStatus);
      tableRows.add(
        pw.TableRow(
          children: [
            _tableCell(measuredAt, style: baseCellStyle),
            _tableCell(
              '$systolic/$diastolic',
              style: baseCellStyle.copyWith(color: valueColor),
            ),
            _tableCell(
              hr?.toString() ?? '-',
              style: baseCellStyle.copyWith(color: valueColor),
            ),
            _tableCell(
              bpStatus,
              style: baseCellStyle.copyWith(
                color: valueColor,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.1),
        3: pw.FlexColumnWidth(1.0),
      },
      children: tableRows,
    );
  }

  pw.Widget _buildBsTable(List<dynamic> rows, pw.Font boldFont) {
    if (rows.isEmpty) {
      return _emptyHint();
    }
    final headerStyle = pw.TextStyle(font: boldFont, fontSize: 10);
    const baseCellStyle = pw.TextStyle(fontSize: 10);
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _tableCell('日期时间', style: headerStyle),
          _tableCell('血糖 (mmol/L)', style: headerStyle),
          _tableCell('时段', style: headerStyle),
          _tableCell('状态', style: headerStyle),
        ],
      ),
    ];
    for (final raw in rows) {
      final row = raw as Map<String, dynamic>;
      final level = (row['level'] as num?)?.toDouble() ?? 0;
      final condition = row['condition']?.toString() ?? '-';
      final measuredAt = _formatDateTime(row['measured_at']?.toString());
      final status = _bsStatus(level, condition);
      final valueColor = _statusColor(status);
      tableRows.add(
        pw.TableRow(
          children: [
            _tableCell(measuredAt, style: baseCellStyle),
            _tableCell(
              level.toStringAsFixed(1),
              style: baseCellStyle.copyWith(color: valueColor),
            ),
            _tableCell(_conditionText(condition), style: baseCellStyle),
            _tableCell(
              status,
              style: baseCellStyle.copyWith(
                color: valueColor,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.4),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.0),
      },
      children: tableRows,
    );
  }

  pw.Widget _tableCell(String text, {required pw.TextStyle style}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(text, style: style),
    );
  }

  pw.Widget _emptyHint() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        '该周期暂无记录。',
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
    );
  }

  String _formatDateTime(String? value) {
    if (value == null || value.isEmpty) return '-';
    return TimeUtils.formatLocalTime(value, pattern: 'yyyy-MM-dd HH:mm');
  }

  String _bpStatus(int systolic, int diastolic, int? heartRate) {
    final hasHigh =
        systolic > 140 ||
        diastolic > 90 ||
        (heartRate != null && heartRate > 100);
    final hasLow =
        systolic < 90 || diastolic < 60 || (heartRate != null && heartRate < 50);
    if (hasHigh) return '偏高';
    if (hasLow) return '偏低';
    return '正常';
  }

  String _bsStatus(double level, String condition) {
    final normalized = condition.toLowerCase();
    final high = switch (normalized) {
      'fasting' || '空腹' => 6.1,
      'post_meal_1h' || 'post-meal 1h' || '餐后1h' => 7.8,
      'post_meal_2h' || 'post-meal 2h' || '餐后2h' => 7.8,
      'bedtime' || '睡前' => 10.0,
      _ => 10.0,
    };
    if (level < 3.9) return '偏低';
    if (level > high) return '偏高';
    return '正常';
  }

  String _conditionText(String condition) {
    final normalized = condition.toLowerCase();
    return switch (normalized) {
      'fasting' => '空腹',
      'post_meal_1h' => '餐后1小时',
      'post_meal_2h' => '餐后2小时',
      'bedtime' => '睡前',
      _ => condition,
    };
  }

  PdfColor _statusColor(String status) {
    return switch (status) {
      '偏高' => PdfColors.red700,
      '偏低' => PdfColors.blue700,
      '正常' => PdfColors.green700,
      _ => PdfColors.blueGrey900,
    };
  }
}
