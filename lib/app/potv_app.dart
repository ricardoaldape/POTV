import 'package:flutter/material.dart';

import 'app_router.dart';
import 'app_theme.dart';

class PotvApp extends StatelessWidget {
  const PotvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'POTV',
      debugShowCheckedModeBanner: false,
      theme: PotvTheme.dark(),
      routerConfig: potvRouter,
    );
  }
}
