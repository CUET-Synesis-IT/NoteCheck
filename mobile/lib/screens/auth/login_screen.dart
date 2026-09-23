import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/common.dart';
import 'server_sheet.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    try {
      if (_register) {
        await auth.register(_name.text, _email.text, _password.text);
      } else {
        await auth.signIn(_email.text, _password.text);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final settings = context.watch<SettingsProvider>();
    final auth = context.watch<AuthProvider>();
    final health = settings.health;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: Container(
              width: 340,
              height: 340,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [scheme.primary.withValues(alpha: 0.28), scheme.primary.withValues(alpha: 0)]),
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [NcColors.genuine.withValues(alpha: 0.18), NcColors.genuine.withValues(alpha: 0)]),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const AppLogo(size: 56),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('NoteCheck', style: t.headlineSmall),
                                Text('Counterfeit banknote detection', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),
                      const SizedBox(height: 28),
                      Text(
                        _register ? 'Create your account' : 'Welcome back',
                        style: t.headlineMedium,
                      ).animate(key: ValueKey(_register)).fadeIn(duration: 300.ms),
                      const SizedBox(height: 6),
                      Text(
                        _register
                            ? 'Register to start verifying notes and keep a private scan history.'
                            : 'Sign in to scan banknotes with the DeiT vision transformer.',
                        style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 24),
                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            AnimatedSize(
                              duration: 250.ms,
                              curve: Curves.easeOut,
                              child: _register
                                  ? Padding(
                                      padding: const EdgeInsets.only(bottom: 14),
                                      child: TextFormField(
                                        controller: _name,
                                        textCapitalization: TextCapitalization.words,
                                        textInputAction: TextInputAction.next,
                                        decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                                        validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your name' : null,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.alternate_email_rounded)),
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) return 'Enter your email';
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) return 'Enter a valid email';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) {
                                final s = v ?? '';
                                if (s.isEmpty) return 'Enter your password';
                                if (_register) {
                                  if (s.length < 8) return 'At least 8 characters';
                                  if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'[^A-Za-z]').hasMatch(s)) {
                                    return 'Mix letters with numbers or symbols';
                                  }
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        InlineError(_error!),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: auth.busy ? null : _submit,
                        child: auth.busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                            : Text(_register ? 'Create account' : 'Sign in'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: auth.busy
                            ? null
                            : () => setState(() {
                                  _register = !_register;
                                  _error = null;
                                }),
                        child: Text(_register ? 'Already have an account? Sign in' : 'New here? Create an account'),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: ServerStatusChip(
                          online: health.online,
                          ready: health.ready,
                          checking: settings.checking && !health.online,
                          onTap: () => showServerSheet(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          settings.serverUrl,
                          style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
