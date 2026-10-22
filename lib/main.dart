import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shell.dart';
import 'design/theme.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
  runApp(const RootgistApp());
}

class RootgistApp extends StatelessWidget {
  const RootgistApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ROOTGIST',
      debugShowCheckedModeBanner: false,
      theme: rgTheme,
      routerConfig: router,
    );
  }
}
