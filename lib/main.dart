import 'dart:async';

import 'analytics/posthog_sink.dart';
import 'data/repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shell.dart';
import 'data/licenses.dart';
import 'data/storage.dart';
import 'design/theme.dart';
import 'design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
  );
  await initStorage();
  registerAppLicenses(); // 설정 → 오픈소스 라이선스(글꼴·아이콘 고지)
  runApp(const RootgistApp());
}

class RootgistApp extends StatefulWidget {
  const RootgistApp({super.key});

  @override
  State<RootgistApp> createState() => _RootgistAppState();
}

// 화면 바탕(설정 › 읽기 설정)을 바꾸면 앱 전체를 다시 그린다. 색 토큰이 getter라 모든 요소의 build를
// 다시 부르면(핫 리로드의 reassemble과 같은 일, 입력 잠금 없이) 열린 화면·스크롤 위치는 그대로 새 색이 된다.
class _RootgistAppState extends State<RootgistApp> with WidgetsBindingObserver {
  Timer? _analyticsTimer;
  bool _navigationScheduled = false;

  void _navigationChanged() {
    if (_navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationScheduled = false;
      if (!mounted) return;
      analytics.navigation(
        // Top state includes imperative push/pop; currentConfiguration.uri may remain the underlying shell URI.
        router.routerDelegate.state.uri,
        exploreTab: exploreTab.value,
        updates: newsTab.value == 1,
      );
    });
  }

  void _consentChanged() =>
      analytics.setEnabled(analyticsCollectionEnabled.value);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      analytics.setActive(state == AppLifecycleState.resumed);

  void _repaint() {
    void dirty(Element e) {
      e.markNeedsBuild();
      e.visitChildren(dirty);
    }

    (context as Element).visitChildren(dirty);
    setState(() {}); // 테마(바탕색)도 새로
  }

  @override
  void initState() {
    super.initState();
    backdrop.addListener(_repaint);
    WidgetsBinding.instance.addObserver(this);
    router.routerDelegate.addListener(_navigationChanged);
    exploreTab.addListener(_navigationChanged);
    newsTab.addListener(_navigationChanged);
    analyticsCollectionEnabled.addListener(_consentChanged);
    analytics.setActive(
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _consentChanged();
    _navigationChanged();
    _analyticsTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => analytics.checkpoint(),
    );
  }

  @override
  void dispose() {
    _analyticsTimer?.cancel();
    analytics.setActive(false);
    WidgetsBinding.instance.removeObserver(this);
    router.routerDelegate.removeListener(_navigationChanged);
    exploreTab.removeListener(_navigationChanged);
    newsTab.removeListener(_navigationChanged);
    analyticsCollectionEnabled.removeListener(_consentChanged);
    backdrop.removeListener(_repaint);
    super.dispose();
  }

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
