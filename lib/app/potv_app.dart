import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_theme.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../providers/user_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PotvApp extends StatelessWidget {
  const PotvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final account = ref.watch(userAccountProvider);
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
      },
    );
  }
}
