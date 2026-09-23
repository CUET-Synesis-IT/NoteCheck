import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../providers/scan_provider.dart';
import '../../widgets/common.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.prediction, required this.original});

  final Prediction prediction;
  final Uint8List original;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _showCropped = true;

  @override
  void initState() {
    super.initState();
    HapticFeedback.mediumImpact();
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Delete this scan?',
      message: 'The result and stored note image will be removed from your history.',
    );
    if (!ok || !mounted) return;
    try {
      await context.read<ScanProvider>().deleteScan(widget.prediction.scanId);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Scan deleted');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prediction;
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final color = scheme.verdict(p.isGenuine);
    final hasCrop = p.noteImage != null;
    final imageBytes = _showCropped && hasCrop ? p.noteImage! : widget.original;
    final margin = (p.genuineProb - p.threshold).abs();
    final decisive = margin > 0.25;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        actions: [
          IconButton(tooltip: 'Delete scan', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          // ------------------------------------------------ verdict banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: color.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(p.isGenuine ? Icons.verified_rounded : Icons.gpp_bad_rounded, color: color, size: 36),
                ).animate().scale(begin: const Offset(0.4, 0.4), end: const Offset(1, 1), duration: 500.ms, curve: Curves.elasticOut),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.isGenuine ? 'GENUINE' : 'COUNTERFEIT', style: t.headlineSmall?.copyWith(color: color, letterSpacing: 1)),
                      const SizedBox(height: 2),
                      Text(
                        p.isGenuine
                            ? (decisive ? 'The note matches genuine security patterns.' : 'Likely genuine, but the margin is slim — re-scan in better light.')
                            : (decisive ? 'Security features do not match a genuine note.' : 'Suspicious. Re-scan the note flat and well lit to confirm.'),
                        style: t.bodySmall?.copyWith(color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 16),

          // ------------------------------------------------ image + toggle
          NcCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (hasCrop)
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, icon: Icon(Icons.crop_rounded, size: 16), label: Text('Analysed note')),
                      ButtonSegment(value: false, icon: Icon(Icons.photo_rounded, size: 16), label: Text('Original')),
                    ],
                    selected: {_showCropped},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _showCropped = s.first),
                    style: ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
                if (hasCrop) const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: scheme.surfaceContainerLowest,
                    constraints: const BoxConstraints(minHeight: 160, maxHeight: 300),
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        Center(
                          child: AnimatedSwitcher(
                            duration: 250.ms,
                            child: Image.memory(imageBytes, key: ValueKey(_showCropped), fit: BoxFit.contain, gaplessPlayback: true),
                          ),
                        ),
                        Positioned.fill(child: ScannerOverlay(active: false, color: color)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(p.wasCropped ? Icons.center_focus_strong_rounded : Icons.info_outline_rounded, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.wasCropped
                            ? 'Note located and perspective-corrected; background removed before analysis.'
                            : 'Analysed the full frame — no separate note outline was detected.',
                        style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(delay: 80.ms, duration: 350.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 16),

          // ------------------------------------------------ confidence
          NcCard(
            child: Row(
              children: [
                ConfidenceRing(value: p.confidence, color: color, size: 132, label: 'CONFIDENCE'),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProbabilityBar(label: 'Genuine', value: p.genuineProb, color: NcColors.genuine),
                      const SizedBox(height: 14),
                      ProbabilityBar(label: 'Counterfeit', value: p.counterfeitProb, color: NcColors.counterfeit),
                      const SizedBox(height: 10),
                      Text(
                        'Decision threshold ${Fmt.percent(p.threshold, decimals: 0)} genuine',
                        style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 160.ms, duration: 350.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 16),

          // ------------------------------------------------ meta
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            children: [
              StatTile(label: 'Latency', value: Fmt.ms(p.latencyMs), icon: Icons.speed_rounded),
              StatTile(label: 'Scan ID', value: '#${p.scanId}', icon: Icons.tag_rounded),
              StatTile(label: 'Region', value: p.wasCropped ? 'Auto-crop' : 'Full frame', icon: Icons.crop_free_rounded),
              StatTile(label: 'Model', value: 'DeiT-Tiny', icon: Icons.memory_rounded, caption: '224 px · ViT'),
            ],
          ).animate().fadeIn(delay: 240.ms, duration: 350.ms).slideY(begin: 0.08, end: 0),
          const SizedBox(height: 14),
          Text(
            'Scanned ${Fmt.dateTime(p.createdAt)}. Results are a statistical estimate (97.9% test accuracy); '
            'always confirm suspicious notes with physical security features.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.document_scanner_rounded),
            label: const Text('Scan another note'),
          ),
        ],
      ),
    );
  }
}
