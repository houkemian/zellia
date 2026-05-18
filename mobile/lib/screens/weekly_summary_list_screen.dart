import 'package:flutter/material.dart';

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
      final items = await widget.api.getWeeklySummaryList(
        targetUserId: widget.elderId,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openItem(WeeklySummaryListItemDto item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => WeeklySummaryScreen(
          api: widget.api,
          elderId: widget.elderId,
          elderDisplayName: widget.elderDisplayName,
          dataUrl: item.url,
          isFrozen: item.isFrozen,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: Text(_text('历史健康周报', 'Weekly reports')),
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
                      child: Text(_text('重试', 'Retry')),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = _items[index];
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
                      item.weekLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF1D2B45),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      item.isFrozen
                          ? _text('云端快照 · 免数据库查询', 'Cloud snapshot')
                          : _text('实时统计 · 本周进行中', 'Live · in progress'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6F7F99),
                      ),
                    ),
                    trailing: Icon(
                      item.isFrozen ? Icons.cloud_done_outlined : Icons.auto_graph,
                      color: item.isFrozen
                          ? const Color(0xFF5BCFB0)
                          : const Color(0xFF18A686),
                    ),
                    onTap: () => _openItem(item),
                  ),
                );
              },
            ),
    );
  }
}
