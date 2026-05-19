import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';
import 'weekly_summary_screen.dart';

class WeeklySummaryListScreen extends StatefulWidget {
  const WeeklySummaryListScreen({
    super.key,
    required this.api,
    required this.elderId,
    required this.elderDisplayName,
  });

  final ApiService api;
  final int elderId;
  final String elderDisplayName;

  @override
  State<WeeklySummaryListScreen> createState() => _WeeklySummaryListScreenState();
}

class _WeeklySummaryListScreenState extends State<WeeklySummaryListScreen> {
  List<WeeklySummaryListItemDto> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _log(String message) {
    if (kDebugMode) {
      debugPrint('[WeeklySummaryList] $message');
    }
  }

  DateTime _isoWeekMonday(int year, int week) {
    final jan4 = DateTime.utc(year, 1, 4);
    final weekOneMonday = jan4.subtract(Duration(days: jan4.weekday - 1));
    return weekOneMonday.add(Duration(days: (week - 1) * 7));
  }

  String _formatMonthDay(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day';
  }

  String _weekLabel(WeeklySummaryListItemDto item, AppLocalizations l10n) {
    if (!item.isFrozen) {
      return l10n.weeklySummaryCurrentWeekInProgress;
    }
    final year = item.isoYear;
    final week = item.isoWeek;
    if (year == null || week == null) {
      return item.weekLabel;
    }
    final start = _isoWeekMonday(year, week);
    final end = start.add(const Duration(days: 6));
    return l10n.weeklySummaryWeekLabel(
      year,
      week,
      _formatMonthDay(start),
      _formatMonthDay(end),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _log(
      'load start elderId=${widget.elderId} '
      'displayName=${widget.elderDisplayName}',
    );
    try {
      final allItems = await widget.api.getWeeklySummaryList(
        targetUserId: widget.elderId,
      );
      _log('API returned ${allItems.length} item(s)');
      for (var i = 0; i < allItems.length; i++) {
        final item = allItems[i];
        _log(
          '[$i] weekLabel=${item.weekLabel} '
          'isFrozen=${item.isFrozen} snapshotExists=${item.snapshotExists} '
          'iso=${item.isoYear}-W${item.isoWeek} url=${item.url}',
        );
      }
      if (!mounted) return;
      setState(() => _items = allItems);
    } catch (e, st) {
      _log('load failed: $e');
      _log('$st');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openItem(WeeklySummaryListItemDto item) {
    final url = item.url.trim();
    _log(
      'open item weekLabel=${item.weekLabel} isFrozen=${item.isFrozen} url=$url',
    );

    final canViewSnapshot = item.canViewSnapshot;
    final isFrozenSnapshot = canViewSnapshot &&
        (url.startsWith('http://') || url.startsWith('https://')) &&
        !url.contains('/reports/weekly-summary');

    final isHistoricalWeek =
        item.isFrozen && item.isoYear != null && item.isoWeek != null;

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WeeklySummaryScreen(
          api: widget.api,
          elderId: widget.elderId,
          elderDisplayName: widget.elderDisplayName,
          dataUrl: isHistoricalWeek && !canViewSnapshot
              ? null
              : (url.isEmpty ? null : url),
          isFrozen: isFrozenSnapshot,
          isoYear: isHistoricalWeek && !canViewSnapshot ? item.isoYear : null,
          isoWeek: isHistoricalWeek && !canViewSnapshot ? item.isoWeek : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text(l10n.weeklySummaryListTitle),
        backgroundColor: const Color(0xFFF6F8FB),
        elevation: 0,
        foregroundColor: const Color(0xFF1D2B45),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: Text(l10n.weeklySummaryRetry),
                    ),
                  ],
                ),
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.weeklySummaryListEmpty,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF8A99B3),
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
                final canView = item.canViewSnapshot;
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5EBF3)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: Text(
                      _weekLabel(item, l10n),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF1D2B45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      canView
                          ? l10n.weeklySummaryCloudSnapshot
                          : item.isFrozen
                          ? l10n.weeklySummaryNotGeneratedYet
                          : l10n.weeklySummaryLiveInProgress,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6F7F99),
                      ),
                    ),
                    trailing: canView
                        ? const Icon(
                            Icons.cloud_done_outlined,
                            color: Color(0xFF5BCFB0),
                          )
                        : SizedBox(
                            height: 38,
                            child: OutlinedButton(
                              onPressed: () => _openItem(item),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                side: const BorderSide(color: Color(0xFF18A686)),
                                foregroundColor: const Color(0xFF18A686),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(l10n.weeklySummaryGenerate),
                            ),
                          ),
                    onTap: canView ? () => _openItem(item) : null,
                  ),
                );
              },
            ),
    );
  }
}
