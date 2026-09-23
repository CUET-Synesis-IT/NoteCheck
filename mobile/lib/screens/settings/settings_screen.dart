import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/scan_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import '../auth/server_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _editName(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final controller = TextEditingController(text: auth.user?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().length < 2 || !context.mounted) return;
    try {
      await auth.updateName(name);
      if (context.mounted) showSnack(context, 'Name updated');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await confirmDialog(context, title: 'Sign out?', message: 'You will need your password to sign back in.', confirmLabel: 'Sign out', destructive: false);
    if (!ok || !context.mounted) return;
    context.read<ScanProvider>().reset();
    context.read<AdminProvider>().reset();
    await context.read<AuthProvider>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final user = auth.user;
    final health = settings.health;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          // ------------------------------------------------ profile
          NcCard(
            onTap: () => _editName(context),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primary.withValues(alpha: 0.2),
                  child: Text(user?.initials ?? '?', style: t.titleLarge?.copyWith(color: scheme.primary)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '', style: t.titleLarge),
                      Text(user?.email ?? '', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (auth.isAdmin ? NcColors.amber : scheme.primary).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text((user?.role ?? 'user').toUpperCase(), style: t.labelSmall?.copyWith(color: auth.isAdmin ? NcColors.amber : scheme.primary, letterSpacing: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ------------------------------------------------ connection
          const SectionHeader('Connection'),
          NcCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_rounded),
                  title: const Text('API server'),
                  subtitle: Text(settings.serverUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showServerSheet(context),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(health.ready ? Icons.check_circle_rounded : Icons.cloud_off_rounded, color: health.ready ? NcColors.genuine : (health.online ? NcColors.amber : scheme.error)),
                  title: Text(health.ready ? 'Connected · model ready' : (health.online ? 'Connected · model not loaded' : 'Server unreachable')),
                  subtitle: Text(
                    health.online
                        ? 'API v${health.version} · ${health.device.toUpperCase()} · TTA ${health.ttaEnabled ? 'on' : 'off'} · threshold ${(health.threshold * 100).toStringAsFixed(0)}%'
                        : (health.error ?? 'Check the address and that the backend is running.'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: settings.checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: settings.checkHealth),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ------------------------------------------------ scanning
          const SectionHeader('Scanning'),
          NcCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              secondary: const Icon(Icons.crop_rounded),
              title: const Text('Auto-crop by default'),
              subtitle: const Text('Locate the note and drop the background before analysis'),
              value: settings.autoCrop,
              onChanged: settings.setAutoCrop,
            ),
          ),
          const SizedBox(height: 22),

          // ------------------------------------------------ appearance
          const SectionHeader('Appearance'),
          NcCard(
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android_rounded), label: Text('System')),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
          ),
          const SizedBox(height: 22),

          // ------------------------------------------------ security
          const SectionHeader('Account'),
          NcCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showChangePassword(context),
                ),
                const Divider(indent: 16, endIndent: 16),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: scheme.error),
                  title: Text('Sign out', style: TextStyle(color: scheme.error)),
                  onTap: () => _signOut(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // ------------------------------------------------ about
          const SectionHeader('About the model'),
          NcCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NoteCheck 1.0.0', style: t.titleMedium),
                          Text('Bangladeshi banknote counterfeit detection', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _fact(context, 'Architecture', 'DeiT-Tiny vision transformer (deit_tiny_patch16_224), fine-tuned'),
                _fact(context, 'Training data', '10,412 images · JaalTaka + Bangladeshi Taka datasets'),
                _fact(context, 'Test accuracy', '97.88% · precision 97.94% · recall 97.88% · ROC-AUC 99.65%'),
                _fact(context, 'Error profile', 'APCER 6.13% (fakes passed) · BPCER 0.00% (genuine flagged)'),
                _fact(context, 'Pipeline', 'EXIF fix → OpenCV note localisation → perspective warp → 224 px → DeiT with 0°/180° test-time augmentation'),
                const SizedBox(height: 6),
                Text(
                  'Predictions are statistical estimates and not a substitute for physical verification of security features.',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, String k, String v) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 104, child: Text(k, style: t.labelMedium?.copyWith(color: scheme.onSurfaceVariant))),
          Expanded(child: Text(v, style: t.bodySmall)),
        ],
      ),
    );
  }

  Future<void> _showChangePassword(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _ChangePasswordSheet(),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Password changed');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Change password', style: t.titleLarge),
            const SizedBox(height: 16),
            TextFormField(
              controller: _current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password', prefixIcon: Icon(Icons.lock_outline_rounded)),
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password', prefixIcon: Icon(Icons.lock_reset_rounded)),
              validator: (v) {
                final s = v ?? '';
                if (s.length < 8) return 'At least 8 characters';
                if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[^A-Za-z]').hasMatch(s)) return 'Mix letters with numbers or symbols';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.check_rounded)),
              validator: (v) => v != _next.text ? 'Passwords do not match' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[const SizedBox(height: 12), InlineError(_error!)],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Text('Update password'),
            ),
          ],
        ),
      ),
    );
  }
}
