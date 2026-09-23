import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scan_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/scan_tile.dart';
import '../history/history_screen.dart';
import 'admin_users_screen.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().isAdmin;
    final scans = context.watch<ScanProvider>();
    final stats = scans.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'Manage users',
              icon: const Icon(Icons.manage_accounts_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen())),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await scans.refreshStats();
          if (isAdmin && context.mounted) await context.read<AdminProvider>().refresh();
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            const SectionHeader('Your scans', subtitle: 'Private statistics for this account'),
            _PersonalStats(stats: stats).animate().fadeIn(duration: 300.ms),
            if (isAdmin) ...[
              const SizedBox(height: 24),
              const _AdminDashboard(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PersonalStats extends StatelessWidget {
  const _PersonalStats({required this.stats});

  final UserStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final total = stats.totalScans;
    return Column(
      children: [
        NcCard(
          child: Row(
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: total == 0
                    ? Center(child: Icon(Icons.donut_large_rounded, size: 48, color: scheme.onSurfaceVariant))
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              sectionsSpace: 3,
                              centerSpaceRadius: 36,
                              startDegreeOffset: -90,
                              sections: [
                                PieChartSectionData(value: stats.genuineCount.toDouble(), color: NcColors.genuine, radius: 22, showTitle: false),
                                PieChartSectionData(value: stats.counterfeitCount.toDouble(), color: NcColors.counterfeit, radius: 22, showTitle: false),
                              ],
                            ),
                            duration: 700.ms,
                            curve: Curves.easeOutCubic,
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('$total', style: t.titleLarge),
                              Text('scans', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _legend(context, NcColors.genuine, 'Genuine', stats.genuineCount, total),
                    const SizedBox(height: 10),
                    _legend(context, NcColors.counterfeit, 'Counterfeit', stats.counterfeitCount, total),
                    const SizedBox(height: 12),
                    Text('Last scan ${Fmt.relative(stats.lastScanAt)}', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: StatTile(label: 'Fake rate', value: Fmt.percent(stats.counterfeitRate), icon: Icons.warning_amber_rounded, accent: NcColors.amber)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Avg confidence', value: Fmt.percent(stats.avgConfidence), icon: Icons.track_changes_rounded)),
            const SizedBox(width: 12),
            Expanded(child: StatTile(label: 'Avg latency', value: Fmt.ms(stats.avgLatencyMs), icon: Icons.speed_rounded)),
          ],
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, Color color, String label, int count, int total) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: t.bodyMedium)),
        Text('$count', style: t.titleSmall),
        const SizedBox(width: 6),
        Text('(${Fmt.percent(pct, decimals: 0)})', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard();

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final api = context.read<ApiClient>();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final o = admin.overview;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Fleet overview',
          subtitle: 'All users · admin only',
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7d')),
              ButtonSegment(value: 14, label: Text('14d')),
              ButtonSegment(value: 30, label: Text('30d')),
            ],
            selected: {admin.days},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => admin.setDays(s.first),
          ),
        ),
        if (admin.error != null) InlineError(admin.error!, onRetry: admin.refresh),
        if (o == null && admin.loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (o != null) ...[
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.75,
            children: [
              StatTile(label: 'Total scans', value: '${o.totalScans}', icon: Icons.document_scanner_rounded, caption: '${o.scansLast24h} in last 24 h'),
              StatTile(label: 'Counterfeits', value: '${o.counterfeitCount}', icon: Icons.gpp_bad_rounded, accent: NcColors.counterfeit, caption: '${Fmt.percent(o.counterfeitRate)} of scans'),
              StatTile(label: 'Users', value: '${o.totalUsers}', icon: Icons.group_rounded, accent: NcColors.genuine, caption: '${o.adminCount} admin${o.adminCount == 1 ? '' : 's'}'),
              StatTile(label: 'Avg latency', value: Fmt.ms(o.avgLatencyMs), icon: Icons.speed_rounded, accent: NcColors.amber),
            ],
          ),
          const SizedBox(height: 14),
          NcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Scans per day', style: t.titleMedium),
                    const Spacer(),
                    _dot(NcColors.genuine, 'genuine', t),
                    const SizedBox(width: 10),
                    _dot(NcColors.counterfeit, 'fake', t),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(height: 180, child: _DailyBarChart(days: o.byDay)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionHeader('Recent scans (all users)'),
          if (admin.recentScans.isEmpty)
            Text('No scans recorded yet.', style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
          else
            for (final s in admin.recentScans) ...[
              ScanTile(api: api, scan: s, showUser: true, onTap: () => showScanDetails(context, s, admin: true)),
              const SizedBox(height: 10),
            ],
        ],
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  Widget _dot(Color c, String label, TextTheme t) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: t.labelSmall),
        ],
      );
}

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({required this.days});

  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final maxY = days.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final labelEvery = days.length > 10 ? (days.length / 6).ceil() : 1;

    return BarChart(
      BarChartData(
        maxY: (maxY == 0 ? 4 : maxY * 1.25).toDouble(),
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
          getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant, strokeWidth: 1, dashArray: [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxY <= 4 ? 1 : (maxY / 4).ceilToDouble(),
              getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= days.length || i % labelEvery != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(days.length <= 7 ? Fmt.weekday(days[i].date) : Fmt.day(days[i].date), style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => scheme.surfaceContainerHighest,
            getTooltipItem: (group, _, rod, __) {
              final d = days[group.x];
              return BarTooltipItem(
                '${Fmt.day(d.date)}\n${d.count} scans · ${d.counterfeit} fake',
                TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12),
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].count.toDouble(),
                  width: days.length > 14 ? 6 : 12,
                  borderRadius: BorderRadius.circular(4),
                  rodStackItems: [
                    BarChartRodStackItem(0, days[i].genuine.toDouble(), NcColors.genuine),
                    BarChartRodStackItem(days[i].genuine.toDouble(), days[i].count.toDouble(), NcColors.counterfeit),
                  ],
                  backDrawRodData: BackgroundBarChartRodData(show: true, toY: (maxY == 0 ? 4 : maxY * 1.25).toDouble(), color: scheme.surfaceContainerHigh.withValues(alpha: 0.5)),
                ),
              ],
            ),
        ],
      ),
      duration: 500.ms,
      curve: Curves.easeOutCubic,
    );
  }
}
