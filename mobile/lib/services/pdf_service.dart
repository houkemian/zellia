import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../utils/time_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

enum _VitalStatus { high, low, normal }

class ClinicalReportPdfLabels {
  const ClinicalReportPdfLabels._({
    required this.title,
    required this.userLabel,
    required this.periodTemplate,
    required this.medicationAdherence,
    required this.averageBloodPressure,
    required this.averageHeartRate,
    required this.noData,
    required this.bloodPressureSection,
    required this.bloodSugarSection,
    required this.dateTime,
    required this.bloodPressureColumn,
    required this.heartRateColumn,
    required this.bloodSugarColumn,
    required this.timingColumn,
    required this.statusColumn,
    required this.emptyPeriodHint,
    required this.statusHigh,
    required this.statusLow,
    required this.statusNormal,
    required this.shareText,
    required this.shareSubject,
  });

  final String title;
  final String userLabel;
  final String periodTemplate;
  final String medicationAdherence;
  final String averageBloodPressure;
  final String averageHeartRate;
  final String noData;
  final String bloodPressureSection;
  final String bloodSugarSection;
  final String dateTime;
  final String bloodPressureColumn;
  final String heartRateColumn;
  final String bloodSugarColumn;
  final String timingColumn;
  final String statusColumn;
  final String emptyPeriodHint;
  final String statusHigh;
  final String statusLow;
  final String statusNormal;
  final String shareText;
  final String shareSubject;

  static ClinicalReportPdfLabels forLanguageCode(String languageCode) {
    return languageCode.toLowerCase().startsWith('zh') ? chinese : english;
  }

  static const chinese = ClinicalReportPdfLabels._(
    title: 'Zellia 个人健康报告',
    userLabel: '用户',
    periodTemplate: '报告周期：近 {days} 天（{start} 至 {end}）',
    medicationAdherence: '用药依从性',
    averageBloodPressure: '平均血压',
    averageHeartRate: '平均心率',
    noData: '暂无数据',
    bloodPressureSection: '血压记录（近 {days} 天）',
    bloodSugarSection: '血糖记录（近 {days} 天）',
    dateTime: '日期时间',
    bloodPressureColumn: '血压 (mmHg)',
    heartRateColumn: '心率 (bpm)',
    bloodSugarColumn: '血糖 (mmol/L)',
    timingColumn: '时段',
    statusColumn: '状态',
    emptyPeriodHint: '该周期暂无记录。',
    statusHigh: '偏高',
    statusLow: '偏低',
    statusNormal: '正常',
    shareText: 'Zellia 临床随访报告 - {name}',
    shareSubject: 'Zellia 临床随访报告',
  );

  static const english = ClinicalReportPdfLabels._(
    title: 'Zellia Personal Health Report',
    userLabel: 'User',
    periodTemplate: 'Report period: last {days} days ({start} to {end})',
    medicationAdherence: 'Medication adherence',
    averageBloodPressure: 'Average blood pressure',
    averageHeartRate: 'Average heart rate',
    noData: 'No data',
    bloodPressureSection: 'Blood pressure (last {days} days)',
    bloodSugarSection: 'Blood sugar (last {days} days)',
    dateTime: 'Date & time',
    bloodPressureColumn: 'BP (mmHg)',
    heartRateColumn: 'HR (bpm)',
    bloodSugarColumn: 'Glucose (mmol/L)',
    timingColumn: 'Timing',
    statusColumn: 'Status',
    emptyPeriodHint: 'No records in this period.',
    statusHigh: 'High',
    statusLow: 'Low',
    statusNormal: 'Normal',
    shareText: 'Zellia Clinical Follow-up Report - {name}',
    shareSubject: 'Zellia Clinical Follow-up Report',
  );

  String subtitle(String userName, int days, String start, String end) {
    final period = periodTemplate
        .replaceAll('{days}', '$days')
        .replaceAll('{start}', start)
        .replaceAll('{end}', end);
    final nameSep = this == chinese ? '：' : ': ';
    return '$userLabel$nameSep$userName | $period';
  }

  String sectionTitle(String template, int days) {
    return template.replaceAll('{days}', '$days');
  }

  String shareMessage(String name) => shareText.replaceAll('{name}', name);

  String statusLabel(_VitalStatus status) => switch (status) {
    _VitalStatus.high => statusHigh,
    _VitalStatus.low => statusLow,
    _VitalStatus.normal => statusNormal,
  };

  String conditionLabel(String condition) {
    final normalized = condition.toLowerCase();
    if (this == chinese) {
      return switch (normalized) {
        'fasting' => '空腹',
        'post_meal_1h' => '餐后1小时',
        'post_meal_2h' => '餐后2小时',
        'bedtime' => '睡前',
        _ => condition,
      };
    }
    return switch (normalized) {
      'fasting' => 'Fasting',
      'post_meal_1h' => 'Post-meal 1h',
      'post_meal_2h' => 'Post-meal 2h',
      'bedtime' => 'Bedtime',
      _ => condition,
    };
  }
}

Future<Uint8List> buildClinicalReportPdfBytes(
  Map<String, dynamic> data,
  String patientName, {
  String languageCode = 'zh',
}) {
  return PdfService().buildClinicalReportPdfBytes(
    data,
    patientName,
    languageCode: languageCode,
  );
}

Future<void> shareClinicalReportBytes(
  Uint8List bytes,
  String patientName, {
  String languageCode = 'zh',
}) {
  return PdfService().shareClinicalReportBytes(
    bytes,
    patientName,
    languageCode: languageCode,
  );
}

Future<String> saveClinicalReportToDevice(
  Uint8List bytes,
  String patientName, {
  String languageCode = 'zh',
}) {
  return PdfService().saveClinicalReportToDevice(
    bytes,
    patientName,
    languageCode: languageCode,
  );
}

class PdfService {
  Future<Uint8List> buildClinicalReportPdfBytes(
    Map<String, dynamic> data,
    String patientName, {
    String languageCode = 'zh',
  }) async {
    final labels = ClinicalReportPdfLabels.forLanguageCode(languageCode);
    final isChinese = languageCode.toLowerCase().startsWith('zh');
    final baseFont = isChinese
        ? await PdfGoogleFonts.notoSansSCRegular()
        : await PdfGoogleFonts.notoSansRegular();
    final boldFont = isChinese
        ? await PdfGoogleFonts.notoSansSCBold()
        : await PdfGoogleFonts.notoSansBold();
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
    final subtitle = labels.subtitle(
      reportPatientName,
      reportDays,
      periodStart,
      periodEnd,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 40),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        build: (context) => [
          pw.Text(
            labels.title,
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
                    label: labels.medicationAdherence,
                    value: '${adherencePercent.toStringAsFixed(1)}%',
                    emphasis: true,
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _metricBlock(
                    label: labels.averageBloodPressure,
                    value: (avgSystolic != null && avgDiastolic != null)
                        ? '${avgSystolic.toStringAsFixed(1)}/${avgDiastolic.toStringAsFixed(1)} mmHg'
                        : labels.noData,
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: _metricBlock(
                    label: labels.averageHeartRate,
                    value: avgHeartRate != null
                        ? '${avgHeartRate.toStringAsFixed(1)} bpm'
                        : labels.noData,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 24),
          pw.Text(
            labels.sectionTitle(labels.bloodPressureSection, reportDays),
            style: pw.TextStyle(font: boldFont, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          _buildBpTable(bpRecords, boldFont, labels),
          pw.SizedBox(height: 20),
          pw.Text(
            labels.sectionTitle(labels.bloodSugarSection, reportDays),
            style: pw.TextStyle(font: boldFont, fontSize: 14),
          ),
          pw.SizedBox(height: 8),
          _buildBsTable(bsRecords, boldFont, labels),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> shareClinicalReportBytes(
    Uint8List bytes,
    String patientName, {
    String languageCode = 'zh',
  }) async {
    final labels = ClinicalReportPdfLabels.forLanguageCode(languageCode);
    final file = await _writeReportToTempFile(bytes);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: labels.shareMessage(patientName),
      subject: labels.shareSubject,
    );
  }

  Future<String> saveClinicalReportToDevice(
    Uint8List bytes,
    String patientName, {
    String languageCode = 'zh',
  }) async {
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
    String patientName, {
    String languageCode = 'zh',
  }) async {
    final bytes = await buildClinicalReportPdfBytes(
      data,
      patientName,
      languageCode: languageCode,
    );
    await shareClinicalReportBytes(
      bytes,
      patientName,
      languageCode: languageCode,
    );
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

  pw.Widget _buildBpTable(
    List<dynamic> rows,
    pw.Font boldFont,
    ClinicalReportPdfLabels labels,
  ) {
    if (rows.isEmpty) {
      return _emptyHint(labels.emptyPeriodHint);
    }
    final headerStyle = pw.TextStyle(font: boldFont, fontSize: 10);
    const baseCellStyle = pw.TextStyle(fontSize: 10);
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _tableCell(labels.dateTime, style: headerStyle),
          _tableCell(labels.bloodPressureColumn, style: headerStyle),
          _tableCell(labels.heartRateColumn, style: headerStyle),
          _tableCell(labels.statusColumn, style: headerStyle),
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
              labels.statusLabel(bpStatus),
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

  pw.Widget _buildBsTable(
    List<dynamic> rows,
    pw.Font boldFont,
    ClinicalReportPdfLabels labels,
  ) {
    if (rows.isEmpty) {
      return _emptyHint(labels.emptyPeriodHint);
    }
    final headerStyle = pw.TextStyle(font: boldFont, fontSize: 10);
    const baseCellStyle = pw.TextStyle(fontSize: 10);
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _tableCell(labels.dateTime, style: headerStyle),
          _tableCell(labels.bloodSugarColumn, style: headerStyle),
          _tableCell(labels.timingColumn, style: headerStyle),
          _tableCell(labels.statusColumn, style: headerStyle),
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
            _tableCell(labels.conditionLabel(condition), style: baseCellStyle),
            _tableCell(
              labels.statusLabel(status),
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

  pw.Widget _emptyHint(String message) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        message,
        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
      ),
    );
  }

  String _formatDateTime(String? value) {
    if (value == null || value.isEmpty) return '-';
    return TimeUtils.formatLocalTime(value, pattern: 'yyyy-MM-dd HH:mm');
  }

  _VitalStatus _bpStatus(int systolic, int diastolic, int? heartRate) {
    final hasHigh =
        systolic > 140 ||
        diastolic > 90 ||
        (heartRate != null && heartRate > 100);
    final hasLow =
        systolic < 90 || diastolic < 60 || (heartRate != null && heartRate < 50);
    if (hasHigh) return _VitalStatus.high;
    if (hasLow) return _VitalStatus.low;
    return _VitalStatus.normal;
  }

  _VitalStatus _bsStatus(double level, String condition) {
    final normalized = condition.toLowerCase();
    final high = switch (normalized) {
      'fasting' || '空腹' => 6.1,
      'post_meal_1h' || 'post-meal 1h' || '餐后1h' => 7.8,
      'post_meal_2h' || 'post-meal 2h' || '餐后2h' => 7.8,
      'bedtime' || '睡前' => 10.0,
      _ => 10.0,
    };
    if (level < 3.9) return _VitalStatus.low;
    if (level > high) return _VitalStatus.high;
    return _VitalStatus.normal;
  }

  PdfColor _statusColor(_VitalStatus status) {
    return switch (status) {
      _VitalStatus.high => PdfColors.red700,
      _VitalStatus.low => PdfColors.blue700,
      _VitalStatus.normal => PdfColors.green700,
    };
  }
}
