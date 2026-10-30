import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
import 'data/repository.dart';
import 'design/widgets/rg_bottom_tab_bar.dart';
import 'debug/widget_gallery.dart';
import 'features/explore/explore_screen.dart';
import 'features/explore/news_detail.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/paper/paper_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/settings/notices.dart';
import 'features/settings/settings_screen.dart';

const _tabs = [
  RgTab('홈', 'house'),
  RgTab('탐색', 'compass'),
  RgTab('보관함', 'bookmark'),
  RgTab('설정', 'settings'),
];

// 뒤로 가는 하위 화면은 MaterialPage를 직접 만든다. go_router 기본 페이지가 전환 없는 NoTransitionPage로
// 만들어져 iOS 가장자리 밀어서 뒤로가기가 붙지 않았다(iOS QA). MaterialPage는 테마의 플랫폼 기본 전환을 쓴다.
// 배경을 깐다: Scaffold 없는 화면(S04 날짜, 데이터 출처, 처리방침)은 투명해서 밀려 들어오는 동안 뒤 화면이 비쳤다(실기기 QA).
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  // Material도 깐다: Scaffold 없는 화면을 쉘 밖으로 띄우면 글자 밑에 노란 두 줄(Material 없음 표시)이 생겼다(실기기 QA).
  child: _PageBackground(child: Material(type: MaterialType.transparency, child: child)),
);

// 페이지 바탕. 페이지 위젯은 라우터가 한 번 만들어 들고 있어, 색을 build에서 읽어야 화면 바탕을 바꿀 때 따라온다.
class _PageBackground extends StatelessWidget {
  const _PageBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: RgColors.bgApp, child: child);
}

final router = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/explore',
            builder: (_, _) => const ExploreScreen(),
            routes: [
              // 지난 날짜의 S01. 탐색 탭 스택 안이라 탭바가 보인다.
              GoRoute(path: ':date', pageBuilder: (_, state) => _page(state, HomeScreen(date: state.pathParameters['date']))),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [GoRoute(path: '/library', builder: (_, _) => const LibraryScreen())]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (_, _) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'reading', pageBuilder: (_, state) => _page(state, const ReadingSettingsScreen())),
              GoRoute(path: 'source', pageBuilder: (_, state) => _page(state, const DataSourceScreen())),
              GoRoute(path: 'privacy', pageBuilder: (_, state) => _page(state, const PrivacyScreen())),
              GoRoute(path: 'terms', pageBuilder: (_, state) => _page(state, const TermsScreen())),
              GoRoute(path: 'notices', pageBuilder: (_, state) => _page(state, const NoticesScreen())),
            ],
          ),
        ]),
      ],
    ),
    // 공식 소식·모델 상세도 논문 상세처럼 쉘 위로 푸시한다. 탭바는 _detailPage가 따로 단다(들어온 탭 그대로). 탐색 탭 안에 두면 홈·보관함에서 열었을 때
    // 탭이 탐색으로 바뀌고 뒤로 가기가 탐색으로 갔다(실기기 QA). id는 encodeComponent(모델 id에 / 가 있다).
    GoRoute(
      path: '/news/:id',
      pageBuilder: (_, state) => _detailPage(state, NewsDetailScreen(id: Uri.decodeComponent(state.pathParameters['id']!))),
    ),
    GoRoute(
      path: '/model/:id',
      pageBuilder: (_, state) => _detailPage(state, ModelDetailScreen(id: Uri.decodeComponent(state.pathParameters['id']!))),
    ),
    // S02는 쉘 위로 푸시되지만 탭바는 남는다(리디자인). S03 리더는 글에 집중하도록 탭바 없이.
    GoRoute(
      path: '/paper/:id',
      pageBuilder: (_, state) => _detailPage(state, PaperScreen(paperId: state.pathParameters['id']!)),
      routes: [
        // ?s=문장ID: C01에서 들어오면 그 문장 쌍으로 스크롤
        GoRoute(
          path: 'reader',
          pageBuilder: (_, state) => _page(
            state,
            ReaderScreen(
              paperId: state.pathParameters['id']!,
              initialSentenceId: state.uri.queryParameters['s'],
            ),
          ),
        ),
      ],
    ),
    if (kDebugMode) GoRoute(path: '/gallery', builder: (_, _) => const WidgetGallery()),
  ],
);

// 지금 쉘. 쉘 위로 푸시된 상세 화면이 같은 탭바를 그리고 탭을 바꿀 때 쓴다.
final currentShell = ValueNotifier<StatefulNavigationShell?>(null);

// 탭바는 바닥에 붙는다(Ink & Paper). 본문은 탭바 위에서 끝나고, 알림(SnackBar)도 그 위에 뜬다.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    currentShell.value = shell;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _TabSwipe(shell: shell, child: shell)),
          // 상태바 밑에 배경색 띠: 스크롤한 내용이 시계·배터리 아이콘과 겹치지 않게(에뮬레이터 QA)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: ColoredBox(color: RgColors.bgApp),
          ),
        ],
      ),
      // 새 글 점은 탭바에 달지 않는다(피드백: 「해야 할 일」처럼 보인다). 설정 탭 안 공지사항 행에만.
      bottomNavigationBar: RgBottomTabBar(
        tabs: _tabs,
        currentIndex: shell.currentIndex,
        onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}

// 쉘 위로 푸시된 상세(논문·소식·모델)에도 같은 탭바를 단다. 들어온 탭이 계속 선택돼 있다.
// 탭을 누르면 상세를 모두 닫고 그 탭으로 간다. 지금 탭을 누르면 그 탭의 첫 화면으로(iOS 관례).
Page<void> _detailPage(GoRouterState state, Widget child) => _page(state, _WithTabBar(child: child));

class _WithTabBar extends StatelessWidget {
  const _WithTabBar({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shell = currentShell.value;
    if (shell == null) return child; // 딥링크로 바로 열려 쉘이 아직 없을 때
    return Scaffold(
      body: child,
      bottomNavigationBar: RgBottomTabBar(
        tabs: _tabs,
        currentIndex: shell.currentIndex,
        onTap: (i) {
          Navigator.of(context, rootNavigator: true).popUntil((r) => r.isFirst);
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
      ),
    );
  }
}

// 옆으로 밀어 탭 넘기기(실기기 QA 요청). 한 줄로 이어진 자리를 차례로 넘는다:
// 홈 → 탐색·논문 → 탐색·소식(발표) → 소식(업데이트) → 소식(화제) → 탐색·모델(트렌딩) → 모델(새로 나옴) → 보관함 → 설정.
// 왼쪽으로 밀면 다음, 오른쪽으로 밀면 이전. 하단 탭바 선택도 같이 옮겨 간다.
// 탭의 첫 화면에서만: 지난 날짜·설정 하위 화면에서는 가장자리 밀기(뒤로)가 먼저다. 가로로 넘기는 칩 목록은 칩이 먼저 넘어간다.
typedef TabStop = (int branch, int exploreTab, int sub); // sub: 소식은 발표·업데이트·화제, 모델은 트렌딩·새로 나옴

const tabStops = <TabStop>[
  (0, 0, 0),
  (1, 0, 0),
  (1, 1, 0),
  (1, 1, 1),
  (1, 1, 2),
  (1, 2, 0),
  (1, 2, 1),
  (2, 0, 0),
  (3, 0, 0),
];

// 지금 자리. 탐색이 아니면 탐색 칸 값은 보지 않는다.
int currentStop(int branch, int tab, int sub) => tabStops.indexWhere(
  (s) => s.$1 == branch && (branch != 1 || (s.$2 == tab && (tab == 0 || s.$3 == sub))),
);

class _TabSwipe extends StatefulWidget {
  const _TabSwipe({required this.shell, required this.child});
  final StatefulNavigationShell shell;
  final Widget child;

  static const _roots = {'/home', '/explore', '/library', '/settings'};

  @override
  State<_TabSwipe> createState() => _TabSwipeState();
}

// 다른 탭으로 넘어갈 때는 민 방향에서 살짝 밀려 들어온다(40pt, 220ms). 어디로 갔는지 감이 잡히게.
// 탐색 안의 칸은 PageView가 미끄러지고, 탭바를 눌러 바꿀 때는 지금처럼 바로 바뀐다. 「동작 줄이기」면 움직이지 않는다.
class _TabSwipeState extends State<_TabSwipe> with SingleTickerProviderStateMixin {
  double _dx = 0;
  GoRouterDelegate? _router;
  late final _enter = AnimationController(vsync: this, duration: RgMotion.base, value: 1);
  double _from = 0; // 들어오기 시작하는 x(다음이면 오른쪽 +, 이전이면 왼쪽 −)

  // 화면을 옮길 때마다 탭 첫 화면인지 다시 본다
  void _changed() => setState(() {});

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = GoRouter.of(context).routerDelegate;
    if (r != _router) {
      _router?.removeListener(_changed);
      _router = r..addListener(_changed);
    }
  }

  @override
  void dispose() {
    _router?.removeListener(_changed);
    _enter.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final dx = _dx;
    _dx = 0;
    // 살짝 밀거나(60pt) 빠르게 튕기면(초당 300pt) 넘긴다
    if (dx.abs() < 60 && v.abs() < 300) return;
    final shell = widget.shell;
    final at = currentStop(shell.currentIndex, exploreTab.value, exploreTab.value == 2 ? (modelsFresh.value ? 1 : 0) : newsTab.value);
    final next = at + ((dx != 0 ? dx : v) < 0 ? 1 : -1);
    if (at < 0 || next < 0 || next >= tabStops.length) return;
    final (branch, tab, sub) = tabStops[next];
    HapticFeedback.selectionClick();
    if (branch == 1) {
      exploreJump.value = ExploreJump(tab, updates: tab == 1 && sub == 1, hot: tab == 1 && sub == 2, fresh: tab == 2 && sub == 1, animate: shell.currentIndex == 1);
    }
    if (branch != shell.currentIndex) {
      shell.goBranch(branch);
      if (!MediaQuery.disableAnimationsOf(context)) {
        _from = next > at ? 40 : -40;
        _enter.forward(from: 0);
      }
    }
  }

  // 탭 첫 화면이 아니면 끌기를 아예 받지 않는다: 받기만 해도 하위 화면의 가장자리 뒤로 가기와 다툰다.
  // 위젯 모양은 그대로 두고 콜백만 비운다(바꾸면 쉘 상태가 새로 만들어진다).
  @override
  Widget build(BuildContext context) {
    final root = _TabSwipe._roots.contains(GoRouter.of(context).routerDelegate.currentConfiguration.uri.path);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: root ? (_) => _dx = 0 : null,
      onHorizontalDragUpdate: root ? (d) => _dx += d.delta.dx : null,
      onHorizontalDragEnd: root ? _end : null,
      child: AnimatedBuilder(
        animation: _enter,
        child: widget.child,
        builder: (context, child) {
          // 모양은 늘 같게(끝나면 투명도 1·이동 0): 위젯 모양이 바뀌면 탭 화면 상태가 새로 만들어진다
          final t = RgMotion.curve.transform(_enter.value);
          return Opacity(opacity: 0.4 + 0.6 * t, child: Transform.translate(offset: Offset(_from * (1 - t), 0), child: child));
        },
      ),
    );
  }
}
