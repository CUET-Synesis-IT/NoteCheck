import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';

/// Bottom sheet for pointing the app at a NoteCheck API instance.
Future<void> showServerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _ServerSheet(),
  );
}

class _ServerSheet extends StatefulWidget {
  const _ServerSheet();

  @override
  State<_ServerSheet> createState() => _ServerSheetState();
}

class _ServerSheetState extends State<_ServerSheet> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _result;
  bool? _ok;

  static const _presets = <String, String>{
    'Android emulator': 'http://10.0.2.2:8000',
    'Localhost (USB reverse)': 'http://127.0.0.1:8000',
  };

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<SettingsProvider>().serverUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _saving = true;
      _result = null;
    });
    final settings = context.read<SettingsProvider>();
    await settings.setServerUrl(_controller.text);
    final h = settings.health;
    if (!mounted) return;
    setState(() {
      _saving = false;
      _ok = h.online;
      _result = h.online
          ? 'Connected to NoteCheck API v${h.version} (${h.device.toUpperCase()}) — '
              '${h.modelLoaded ? 'model ready' : 'model not loaded'}'
          : (h.error ?? 'Server unreachable');
    });
  }

  Future<void> _save() async {
    final settings = context.read<SettingsProvider>();
    await settings.setServerUrl(_controller.text);
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, 'Server set to ${settings.serverUrl}');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('API server', style: t.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Address of the machine running the NoteCheck backend. On a real phone use your computer\'s LAN IP, e.g. http://192.168.0.10:8000.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _test(),
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: ApiClient.defaultBaseUrl,
              prefixIcon: Icon(Icons.dns_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _presets.entries)
                ActionChip(
                  label: Text(e.key),
                  avatar: const Icon(Icons.bolt_rounded, size: 16),
                  onPressed: () => setState(() => _controller.text = e.value),
                ),
            ],
          ),
          if (_result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_ok! ? NcColors.genuine : scheme.error).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(_ok! ? Icons.check_circle_rounded : Icons.wifi_off_rounded, color: _ok! ? NcColors.genuine : scheme.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_result!, style: t.bodySmall)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _test,
                  icon: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check_rounded),
                  label: const Text('Test'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save'))),
            ],
          ),
        ],
      ),
    );
  }
}
