import 'dart:async';

import 'package:flutter/material.dart';
import 'package:potv/ui/branding/potv_animated_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/user_providers.dart';
import '../ui/onboarding/onboarding_screen.dart';
import '../ui/subscription/subscription_locked_screen.dart';
import 'app_router.dart';
import 'app_theme.dart';

class PotvApp extends ConsumerStatefulWidget {
  const PotvApp({super.key});

  @override
  ConsumerState<PotvApp> createState() => _PotvAppState();
}

class _PotvAppState extends ConsumerState<PotvApp> with WidgetsBindingObserver {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Even without navigation, access locks shortly after the server expiry.
    _expiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(userAccountProvider) != null) {
      unawaited(ref.read(userAccountProvider.notifier).refreshSubscription());
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

    if (!account.hasViewingAccess) {
      return MaterialApp(
        title: 'POTV',
        debugShowCheckedModeBanner: false,
        theme: PotvTheme.dark(),
        home: SubscriptionLockedScreen(account: account),
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
    backgroundColor: Colors.black,
    body: PotvLoadingFlag(width: 200),
  );
}
