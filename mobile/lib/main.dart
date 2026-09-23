import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/theme.dart';
import 'providers/admin_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/scan_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_shell.dart';
import 'screens/splash_screen.dart';
import 'services/session_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(NoteCheckApp(api: ApiClient(baseUrl: ApiClient.defaultBaseUrl), store: SessionStore()));
}

class NoteCheckApp extends StatelessWidget {
  const NoteCheckApp({super.key, required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => SettingsProvider(api: api, store: store)),
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api, store: store)),
        ChangeNotifierProxyProvider<AuthProvider, ScanProvider>(
          create: (ctx) => ScanProvider(api: api, onUnauthorized: () => ctx.read<AuthProvider>().handleUnauthorized()),
          update: (_, __, previous) => previous!,
        ),
        ChangeNotifierProvider(create: (_) => AdminProvider(api: api)),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) => MaterialApp(
          title: 'NoteCheck',
          debugShowCheckedModeBanner: false,
          theme: NcTheme.light(),
          darkTheme: NcTheme.dark(),
          themeMode: settings.themeMode,
          home: const _Root(),
        ),
      ),
    );
  }
}

/// Boots settings + session once, then routes on auth status.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _booted = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final settings = context.read<SettingsProvider>();
    final auth = context.read<AuthProvider>();
    await settings.load();
    await Future.wait([
      auth.bootstrap(),
      Future.delayed(const Duration(milliseconds: 900)), // let the splash animate
    ]);
    if (mounted) setState(() => _booted = true);
  }

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AuthProvider>().status;
    final Widget child;
    if (!_booted || status == AuthStatus.unknown) {
      child = const SplashScreen(key: ValueKey('splash'));
    } else if (status == AuthStatus.signedIn) {
      child = const HomeShell(key: ValueKey('home'));
    } else {
      child = const LoginScreen(key: ValueKey('login'));
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      child: child,
    );
  }
}
