import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scan_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import '../auth/server_sheet.dart';
import 'result_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, this.onViewHistory});

  final VoidCallback? onViewHistory;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  Uint8List? _bytes;
  String _filename = 'note.jpg';
  String? _error;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 92,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _filename = file.name.isEmpty ? 'note.jpg' : file.name;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not open the image: $e');
    }
  }

  Future<void> _analyze() async {
    final bytes = _bytes;
    if (bytes == null) return;
    setState(() => _error = null);
    final scans = context.read<ScanProvider>();
    final settings = context.read<SettingsProvider>();
    try {
      final prediction = await scans.analyze(bytes, autoCrop: settings.autoCrop, filename: _filename);
      if (!mounted) return;
      await Navigator.of(context).push(
        PageRouteBuilder(
          transitionDuration: 380.ms,
          reverseTransitionDuration: 260.ms,
          pageBuilder: (_, __, ___) => ResultScreen(prediction: prediction, original: bytes),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.05), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );
      if (mounted) setState(() => _bytes = null);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Unexpected error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final settings = context.watch<SettingsProvider>();
    final scans = context.watch<ScanProvider>();
    final user = context.watch<AuthProvider>().user;
    final health = settings.health;
    final analyzing = scans.analyzing;
    final stats = scans.stats;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hello, ${user?.name.split(' ').first ?? 'there'}', style: t.headlineSmall),
                          Text('Verify a banknote in seconds', style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    ServerStatusChip(
                      online: health.online,
                      ready: health.ready,
                      checking: settings.checking && !health.online,
                      onTap: () => showServerSheet(context),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              sliver: SliverToBoxAdapter(
                child: AnimatedSwitcher(
                  duration: 300.ms,
                  child: _bytes == null
                      ? _Dropzone(key: const ValueKey('drop'), onCamera: () => _pick(ImageSource.camera), onGallery: () => _pick(ImageSource.gallery))
                      : _Preview(
                          key: const ValueKey('preview'),
                          bytes: _bytes!,
                          analyzing: analyzing,
                          autoCrop: settings.autoCrop,
                          onAutoCrop: settings.setAutoCrop,
                          onReplace: analyzing ? null : () => setState(() => _bytes = null),
                        ),
                ),
              ),
            ),
            if (_error != null)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(child: InlineError(_error!)),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              sliver: SliverToBoxAdapter(
                child: FilledButton.icon(
                  onPressed: _bytes == null || analyzing || !health.ready ? null : _analyze,
                  icon: analyzing
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                      : const Icon(Icons.verified_user_rounded),
                  label: Text(
                    analyzing
                        ? 'Analysing…'
                        : !health.ready
                            ? (health.online ? 'Model is loading' : 'Server offline')
                            : 'Verify authenticity',
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  'Your activity',
                  trailing: TextButton(onPressed: widget.onViewHistory, child: const Text('History')),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: StatTile(label: 'Scans', value: '${stats.totalScans}', icon: Icons.document_scanner_rounded)),
                    const SizedBox(width: 12),
                    Expanded(child: StatTile(label: 'Genuine', value: '${stats.genuineCount}', icon: Icons.verified_rounded, accent: NcColors.genuine)),
                    const SizedBox(width: 12),
                    Expanded(child: StatTile(label: 'Fakes', value: '${stats.counterfeitCount}', icon: Icons.gpp_bad_rounded, accent: NcColors.counterfeit)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              sliver: SliverToBoxAdapter(
                child: NcCard(
                  gradient: LinearGradient(
                    colors: [scheme.primary.withValues(alpha: 0.16), NcColors.genuine.withValues(alpha: 0.10)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tips_and_updates_rounded, color: scheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tips for a reliable scan', style: t.titleSmall),
                            const SizedBox(height: 4),
                            Text(
                              'Lay the note flat on a plain, contrasting surface. Fill most of the frame, avoid glare and shadows, and keep the note in focus. '
                              'Last scan: ${Fmt.relative(stats.lastScanAt)}.',
                              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dropzone extends StatelessWidget {
  const _Dropzone({super.key, required this.onCamera, required this.onGallery});

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Column(
      children: [
        NcCard(
          padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [scheme.primary.withValues(alpha: 0.3), NcColors.genuine.withValues(alpha: 0.25)]),
                ),
                child: Icon(Icons.payments_rounded, size: 42, color: scheme.primary),
              )
                  .animate(onPlay: (c) => c.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.06, 1.06), duration: 1600.ms, curve: Curves.easeInOut),
              const SizedBox(height: 18),
              Text('Add a banknote photo', style: t.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Take a picture or choose one from your gallery. The note is located and cropped automatically.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: onCamera,
                icon: const Icon(Icons.photo_camera_rounded),
                label: const Text('Camera'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.photo_library_rounded),
                label: const Text('Gallery'),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    super.key,
    required this.bytes,
    required this.analyzing,
    required this.autoCrop,
    required this.onAutoCrop,
    this.onReplace,
  });

  final Uint8List bytes;
  final bool analyzing;
  final bool autoCrop;
  final ValueChanged<bool> onAutoCrop;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return NcCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Container(
              color: scheme.surfaceContainerLowest,
              constraints: const BoxConstraints(minHeight: 200, maxHeight: 320),
              child: Stack(
                fit: StackFit.passthrough,
                children: [
                  Center(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                  Positioned.fill(child: ScannerOverlay(active: analyzing)),
                  if (analyzing)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: scheme.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                          child: Text('Locating note · extracting patches · classifying', style: t.labelSmall),
                        ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.6, end: 1, duration: 900.ms),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.crop_rounded, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Auto-crop note', style: t.titleSmall),
                    Text('Removes the table / background before analysis', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Switch(value: autoCrop, onChanged: analyzing ? null : onAutoCrop),
            ],
          ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onReplace,
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text('Choose a different photo'),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.98, 0.98), end: const Offset(1, 1));
  }
}
