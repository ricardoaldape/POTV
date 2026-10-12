import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_providers.dart';
import '../ui/onboarding/onboarding_screen.dart';
import 'app_router.dart';
import 'app_theme.dart';

class PotvApp extends ConsumerWidget {
  const PotvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(authBootstrapProvider);
    final account = ref.watch(userAccountProvider);

    if (bootstrap.isLoading) {
      return MaterialApp(
        title: 'POTV',
        debugShowCheckedModeBanner: false,
        theme: PotvTheme.dark(),
        home: const _PotvSplash(),
      );
    }

    if (account == null) {
      return MaterialApp(
        title: 'POTV',
        debugShowCheckedModeBanner: false,
        theme: PotvTheme.dark(),
        home: const OnboardingScreen(),
      );
    }

    return MaterialApp.router(
      title: 'POTV',
      debugShowCheckedModeBanner: false,
      theme: PotvTheme.dark(),
      routerConfig: potvRouter,
    );
  }
}

class _PotvSplash extends StatelessWidget {
  const _PotvSplash();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'POTV',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 20),
              SizedBox.square(
                dimension: 26,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ],
          ),
        ),
      );
}
