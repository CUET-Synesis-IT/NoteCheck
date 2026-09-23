import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../widgets/common.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(size: 96)
                .animate()
                .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1), duration: 600.ms, curve: Curves.easeOutBack)
                .fadeIn(duration: 400.ms),
            const SizedBox(height: 22),
            Text('NoteCheck', style: t.headlineMedium).animate().fadeIn(delay: 250.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
            const SizedBox(height: 6),
            Text('Banknote authenticity, verified by AI', style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
                .animate()
                .fadeIn(delay: 400.ms, duration: 400.ms),
            const SizedBox(height: 40),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 3,
                borderRadius: BorderRadius.circular(3),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ).animate().fadeIn(delay: 600.ms),
          ],
        ),
      ),
    );
  }
}
