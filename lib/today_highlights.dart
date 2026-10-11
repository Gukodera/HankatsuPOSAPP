import 'package:flutter/material.dart';
import 'pos_api.dart';

class TodayHighlights extends StatefulWidget {
  final PosApi api;
  final int refresh;
  const TodayHighlights({super.key, required this.api, required this.refresh});

  @override
  State<TodayHighlights> createState() => _TodayHighlightsState();
}

class _TodayHighlightsState extends State<TodayHighlights> {
  Json? report;
  bool loading = true, failed = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(TodayHighlights oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh || oldWidget.api != widget.api) {
      load();
    }
  }

  Future<void> load() async {
    final token = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      // Let the server choose the current business day and authorized scope.
      final value = Json.from(
        await widget.api.call('report', {'period': 'daily'}),
      );
      if (mounted && token == generation) {
        setState(() {
          report = value;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          failed = true;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final best = List<Json>.from(report?['best'] ?? []);
    final buckets = List<Json>.from(report?['buckets'] ?? []);
    final hours = List<int>.filled(24, 0);
    for (final bucket in buckets) {
      final hour = int.tryParse('${bucket['bucket']}');
      if (hour != null && hour >= 0 && hour < 24) {
        hours[hour] = (bucket['total_minor'] as num).toInt();
      }
    }
    final peak = hours.fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8CCD4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_outlined, color: Color(0xFFE32646)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  "Today's highlights",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Refresh highlights',
                onPressed: loading ? null : load,
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          if (loading)
            const LinearProgressIndicator()
          else if (failed)
            const Text(
              'Highlights unavailable. Tap refresh to try again.',
              style: TextStyle(color: Color(0xFF82757B)),
            )
          else if (report != null) ...[
            Text(
              '${report!["scope"]} • ${report!["date"] ?? "Today"} • Asia/Manila',
              style: const TextStyle(fontSize: 12, color: Color(0xFF82757B)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                metric('Net sales', moneyMinor(report!['net_minor'])),
                metric('Transactions', '${report!["count"]}'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              best.isEmpty
                  ? 'Your first sale starts the story.'
                  : 'Best seller: ${best.first["product_name"]} • ${best.first["qty"]} sold',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Hourly gross sales • Best seller by gross units',
              style: TextStyle(fontSize: 11, color: Color(0xFF82757B)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < 24; i++)
                    Expanded(
                      child: Tooltip(
                        message:
                            '${i.toString().padLeft(2, "0")}:00 • ${moneyMinor(hours[i])}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Container(
                            height: peak == 0 || hours[i] == 0
                                ? 3
                                : 3 + 45 * hours[i] / peak,
                            decoration: BoxDecoration(
                              color: hours[i] == 0
                                  ? const Color(0xFFFCE2E8)
                                  : const Color(0xFFE32646),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [Text('00:00'), Text('12:00'), Text('23:00')],
            ),
          ],
        ],
      ),
    );
  }

  Widget metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xFF82757B)),
      ),
      Text(
        value,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: Color(0xFFE32646),
        ),
      ),
    ],
  );
}
