import 'dart:async';
import 'dart:ui' as ui;

import 'analytics/posthog_sink.dart';
import 'data/repository.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'app_shell.dart';
import 'data/licenses.dart';
import 'data/storage.dart';
import 'design/theme.dart';
import 'design/tokens.dart';

// 상태바 글자색: 밝은 화면은 검정, 어두운 화면은 흰색
void _statusBar() => SystemChrome.setSystemUIOverlayStyle(
  (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStorage();
  platformDark.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  _statusBar();
  registerAppLicenses(); // 설정 → 오픈소스 라이선스(글꼴·아이콘 고지)
  runApp(const RootgistApp());
}

class RootgistApp extends StatefulWidget {
  const RootgistApp({super.key});

  @override
  State<RootgistApp> createState() => _RootgistAppState();
}

// 화면 바탕·화면 모드(설정 › 읽기 설정)나 기기 다크 모드가 바뀌면 앱 전체를 다시 그린다. 색 토큰이 getter라 모든 요소의 build를
// 다시 부르면(핫 리로드의 reassemble과 같은 일, 입력 잠금 없이) 열린 화면·스크롤 위치는 그대로 새 색이 된다.
class _RootgistAppState extends State<RootgistApp> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // 화면 모드·바탕이 바뀔 때 직전 화면을 찍어 새 색 위에 덮고 흐리게 지운다(한 프레임에 확 바뀌지 않게)
  final _appKey = GlobalKey();
  ui.Image? _before;
  late final _fade = AnimationController(vsync: this, duration: RgMotion.base)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) setState(_dropBefore);
    });
  var _look = (isDark, backdrop.value);

  void _dropBefore() {
    _before?.dispose();
    _before = null;
  }

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

  // 기기의 다크 모드가 바뀌면(화면 모드가 「기기 설정」일 때만 색이 바뀐다)
  @override
  void didChangePlatformBrightness() =>
      platformDark.value = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      analytics.setActive(state == AppLifecycleState.resumed);

  void _repaint() {
    // 기기 다크 모드가 바뀌어도 화면 모드가 「밝게」·「어둡게」면 색은 그대로다
    final look = (isDark, backdrop.value);
    if (look == _look) return;
    _look = look;
    final boundary = _appKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary != null && !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      try {
        _dropBefore();
        _before = boundary.toImageSync(pixelRatio: View.of(context).devicePixelRatio);
        _fade.forward(from: 0);
      } catch (_) {
        _dropBefore(); // 아직 그려지지 않았으면 전환 없이 바로
      }
    }
    void dirty(Element e) {
      e.markNeedsBuild();
      e.visitChildren(dirty);
    }

    _statusBar();
    (context as Element).visitChildren(dirty);
    setState(() {}); // 테마(바탕색)도 새로
  }

  @override
  void initState() {
    super.initState();
    backdrop.addListener(_repaint);
    appearance.addListener(_repaint);
    platformDark.addListener(_repaint);
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
    appearance.removeListener(_repaint);
    platformDark.removeListener(_repaint);
    _fade.dispose();
    _dropBefore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'ROOTGIST',
      debugShowCheckedModeBanner: false,
      theme: rgTheme,
      themeAnimationStyle: AnimationStyle.noAnimation, // 색 전환은 아래 크로스페이드가 맡는다(동작 줄이기면 바로)
      routerConfig: router,
      builder: (context, child) => Stack(fit: StackFit.expand, children: [
        RepaintBoundary(key: _appKey, child: child),
        if (_before case final image?)
          IgnorePointer(
            child: FadeTransition(
              opacity: ReverseAnimation(CurvedAnimation(parent: _fade, curve: RgMotion.curve)),
              child: RawImage(image: image, fit: BoxFit.fill),
            ),
          ),
      ]),
    );
  }
}
