import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/scan_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/scan_tile.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.pixels > _controller.position.maxScrollExtent - 300) {
        context.read<ScanProvider>().loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete(Scan scan) async {
    final scans = context.read<ScanProvider>();
    try {
      await scans.deleteScan(scan.id);
      if (mounted) showSnack(context, 'Scan #${scan.id} deleted');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scans = context.watch<ScanProvider>();
    final api = context.read<ApiClient>();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final items = scans.scans;

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(Fmt.plural(scans.total, 'scan'), style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant))),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SegmentedButton<ScanFilter>(
              segments: const [
                ButtonSegment(value: ScanFilter.all, label: Text('All')),
                ButtonSegment(value: ScanFilter.genuine, label: Text('Genuine'), icon: Icon(Icons.verified_rounded, size: 16, color: NcColors.genuine)),
                ButtonSegment(value: ScanFilter.counterfeit, label: Text('Fakes'), icon: Icon(Icons.gpp_bad_rounded, size: 16, color: NcColors.counterfeit)),
              ],
              selected: {scans.filter},
              showSelectedIcon: false,
              onSelectionChanged: (s) => scans.setFilter(s.first),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await scans.refreshHistory();
          await scans.refreshStats();
        },
        child: scans.loadingHistory && items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                      if (scans.historyError != null)
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: InlineError(scans.historyError!, onRetry: scans.refreshHistory))
                      else
                        EmptyState(
                          icon: Icons.history_toggle_off_rounded,
                          title: scans.filter == ScanFilter.all ? 'No scans yet' : 'Nothing here',
                          message: scans.filter == ScanFilter.all
                              ? 'Verified notes will appear here with their stored preview.'
                              : 'No ${scans.filter == ScanFilter.genuine ? 'genuine' : 'counterfeit'} results in your history.',
                        ),
                    ],
                  )
                : ListView.separated(
                    controller: _controller,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length + (scans.hasMore ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      if (i >= items.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
                        );
                      }
                      final scan = items[i];
                      return Dismissible(
                        key: ValueKey('scan-${scan.id}'),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => confirmDialog(
                          context,
                          title: 'Delete scan #${scan.id}?',
                          message: 'This removes the result and its stored image.',
                        ),
                        onDismissed: (_) => _delete(scan),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                          child: Icon(Icons.delete_rounded, color: scheme.error),
                        ),
                        child: ScanTile(
                          api: api,
                          scan: scan,
                          onTap: () => showScanDetails(context, scan),
                        ).animate(delay: (30 * (i % 12)).ms).fadeIn(duration: 250.ms).slideX(begin: 0.04, end: 0),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Bottom sheet with the larger stored image and the full breakdown.
Future<void> showScanDetails(BuildContext context, Scan scan, {bool admin = false}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _ScanDetailSheet(scan: scan, admin: admin),
  );
}

class _ScanDetailSheet extends StatelessWidget {
  const _ScanDetailSheet({required this.scan, required this.admin});

  final Scan scan;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final color = scheme.verdict(scan.isGenuine);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.95,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              VerdictBadge(genuine: scan.isGenuine),
              const Spacer(),
              Text('Scan #${scan.id}', style: t.titleMedium),
            ],
          ),
          const SizedBox(height: 14),
          Hero(
            tag: 'scan-${scan.id}',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: scheme.surfaceContainerLowest,
                constraints: const BoxConstraints(minHeight: 160, maxHeight: 280),
                child: scan.hasImage
                    ? Image.network(
                        api.scanImageUrl(scan.id),
                        headers: api.authHeaders,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const SizedBox(height: 160, child: Icon(Icons.broken_image_outlined)),
                        loadingBuilder: (_, child, p) => p == null ? child : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
                      )
                    : const SizedBox(height: 160, child: Icon(Icons.image_not_supported_outlined)),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              ConfidenceRing(value: scan.confidence, color: color, size: 110, stroke: 10, label: 'CONF.'),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    ProbabilityBar(label: 'Genuine', value: scan.genuineProb, color: NcColors.genuine),
                    const SizedBox(height: 12),
                    ProbabilityBar(label: 'Counterfeit', value: scan.counterfeitProb, color: NcColors.counterfeit),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _row(context, Icons.schedule_rounded, 'Scanned', Fmt.dateTime(scan.createdAt)),
          _row(context, Icons.speed_rounded, 'Latency', Fmt.ms(scan.latencyMs)),
          _row(context, Icons.crop_rounded, 'Region', scan.wasCropped ? 'Auto-cropped note' : 'Full frame'),
          if (admin && scan.userEmail != null) _row(context, Icons.person_outline_rounded, 'User', '${scan.userEmail} (#${scan.userId})'),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label, style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          const Spacer(),
          Flexible(child: Text(value, style: t.titleSmall, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
