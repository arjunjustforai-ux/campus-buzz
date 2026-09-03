import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Accessible charts: title, period, tooltips and a textual summary for screen readers.
class CbLineChart extends StatelessWidget {
  const CbLineChart({super.key, required this.title, required this.points, this.period, this.labels = const [], this.color = CbColors.lime, this.unit = '', this.height = 200});
  final String title; final String? period; final List<double> points; final List<String> labels; final Color color; final String unit; final double height;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (points.isEmpty) return _Frame(title: title, period: period, child: SizedBox(height: height, child: Center(child: Text('No data for this period', style: t.bodyMedium))));
    final maxY = points.reduce((a, b) => a > b ? a : b);
    final last = points.last, first = points.first;
    final summary = '$title: ${points.length} points, from ${_fmt(first)}$unit to ${_fmt(last)}$unit, peak ${_fmt(maxY)}$unit.';
    return _Frame(
      title: title, period: period, summary: summary,
      child: SizedBox(
        height: height,
        child: LineChart(LineChartData(
          minY: 0, maxY: maxY == 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: CbColors.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(_fmt(v), style: t.labelSmall))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: labels.isNotEmpty, reservedSize: 24, interval: (labels.length / 6).ceilToDouble().clamp(1, 999), getTitlesWidget: (v, _) { final i = v.toInt(); return i >= 0 && i < labels.length ? Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: t.labelSmall)) : const SizedBox.shrink(); })),
          ),
          lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipColor: (_) => CbColors.surface3, getTooltipItems: (spots) => spots.map((s) => LineTooltipItem('${s.x.toInt() < labels.length ? '${labels[s.x.toInt()]}: ' : ''}${_fmt(s.y)}$unit', t.labelMedium!.copyWith(color: CbColors.textPrimary))).toList())),
          lineBarsData: [LineChartBarData(spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i])], isCurved: true, curveSmoothness: 0.25, color: color, barWidth: 3, dotData: FlDotData(show: points.length < 20), belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.12)))],
        )),
      ),
    );
  }
}

class CbBarChart extends StatelessWidget {
  const CbBarChart({super.key, required this.title, required this.values, required this.labels, this.period, this.color = CbColors.orange, this.secondary, this.secondaryLabel, this.primaryLabel, this.height = 220, this.unit = ''});
  final String title; final String? period, secondaryLabel, primaryLabel, unit; final List<double> values; final List<double>? secondary; final List<String> labels; final Color color; final double height;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (values.isEmpty) return _Frame(title: title, period: period, child: SizedBox(height: height, child: Center(child: Text('No data for this period', style: t.bodyMedium))));
    final all = [...values, ...?secondary];
    final maxY = all.reduce((a, b) => a > b ? a : b);
    final top = values.indexOf(values.reduce((a, b) => a > b ? a : b));
    final summary = '$title: ${values.length} categories. Highest is ${labels.length > top ? labels[top] : ''} at ${_fmt(values[top])}$unit.';
    return _Frame(
      title: title, period: period, summary: summary,
      legend: secondary == null ? null : Row(children: [_dot(color, primaryLabel ?? 'Primary', t), const SizedBox(width: 12), _dot(CbColors.lime, secondaryLabel ?? 'Secondary', t)]),
      child: SizedBox(
        height: height,
        child: BarChart(BarChartData(
          maxY: maxY == 0 ? 1 : maxY * 1.15,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: CbColors.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(), rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, getTitlesWidget: (v, _) => Text(_fmt(v), style: t.labelSmall))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (v, _) { final i = v.toInt(); return i >= 0 && i < labels.length ? Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i].length > 8 ? '${labels[i].substring(0, 7)}…' : labels[i], style: t.labelSmall)) : const SizedBox.shrink(); })),
          ),
          barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipColor: (_) => CbColors.surface3, getTooltipItem: (g, gi, rod, ri) => BarTooltipItem('${labels[gi]}\n${_fmt(rod.toY)}$unit', t.labelMedium!.copyWith(color: CbColors.textPrimary)))),
          barGroups: [for (var i = 0; i < values.length; i++) BarChartGroupData(x: i, barRods: [BarChartRodData(toY: values[i], color: color, width: secondary == null ? 18 : 10, borderRadius: BorderRadius.circular(4)), if (secondary != null) BarChartRodData(toY: i < secondary!.length ? secondary![i] : 0, color: CbColors.lime, width: 10, borderRadius: BorderRadius.circular(4))])],
        )),
      ),
    );
  }
  Widget _dot(Color c, String label, TextTheme t) => Row(children: [Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 6), Text(label, style: t.labelSmall)]);
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child, this.period, this.summary, this.legend});
  final String title; final String? period, summary; final Widget child; final Widget? legend;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      label: summary ?? title,
      child: Container(
        decoration: BoxDecoration(color: CbColors.surface1, borderRadius: BorderRadius.circular(18), border: Border.all(color: CbColors.border)),
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(title, style: t.titleMedium)), if (period != null) Text(period!, style: t.labelSmall)]),
          if (legend != null) Padding(padding: const EdgeInsets.only(top: 6), child: legend),
          const SizedBox(height: 12),
          ExcludeSemantics(child: child),
          if (summary != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(summary!, style: t.bodySmall)),
        ]),
      ),
    );
  }
}

String _fmt(double v) => v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
