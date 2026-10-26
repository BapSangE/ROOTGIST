import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
import 'design/widgets/rg_bottom_tab_bar.dart';
import 'debug/widget_gallery.dart';
import 'features/explore/explore_screen.dart';
import 'features/home/home_screen.dart';
import 'features/library/library_screen.dart';
import 'features/paper/paper_screen.dart';
import 'features/reader/reader_screen.dart';
import 'features/settings/settings_screen.dart';

const _tabs = [
  RgTab('홈', 'house'),
  RgTab('탐색', 'compass'),
  RgTab('보관함', 'bookmark'),
  RgTab('설정', 'sliders-vertical'),
];

// 뒤로 가는 하위 화면은 MaterialPage를 직접 만든다. go_router 기본 페이지가 전환 없는 NoTransitionPage로
// 만들어져 iOS 가장자리 밀어서 뒤로가기가 붙지 않았다(iOS QA). MaterialPage는 테마의 플랫폼 기본 전환을 쓴다.
// 배경을 깐다: Scaffold 없는 화면(S04 날짜, 데이터 출처, 처리방침)은 투명해서 밀려 들어오는 동안 뒤 화면이 비쳤다(실기기 QA).
Page<void> _page(GoRouterState state, Widget child) => MaterialPage<void>(
  key: state.pageKey,
  name: state.name ?? state.path,
  child: ColoredBox(color: RgColors.bgApp, child: child),
);

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
              GoRoute(path: 'source', pageBuilder: (_, state) => _page(state, const DataSourceScreen())),
              GoRoute(path: 'privacy', pageBuilder: (_, state) => _page(state, const PrivacyScreen())),
            ],
          ),
        ]),
      ],
    ),
    // S02·S03은 탭바 없이 쉘 위로 푸시된다(7.0).
    GoRoute(
      path: '/paper/:id',
      pageBuilder: (_, state) => _page(state, PaperScreen(paperId: state.pathParameters['id']!)),
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

// 탭바는 본문 위에 떠 있다(HANDOFF 9.3). 하단 띄움 = max(30, SafeArea 하단).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(RgSpace.floatingBottom, MediaQuery.paddingOf(context).bottom);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: shell),
          // 상태바 밑에 배경색 띠: 스크롤한 내용이 시계·배터리 아이콘과 겹치지 않게(에뮬레이터 QA)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: const ColoredBox(color: RgColors.bgApp),
          ),
          Positioned(
            left: RgSpace.gutterCard,
            right: RgSpace.gutterCard,
            bottom: bottom,
            child: RgBottomTabBar(
              tabs: _tabs,
              currentIndex: shell.currentIndex,
              onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            ),
          ),
        ],
      ),
    );
  }
}
