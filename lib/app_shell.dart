import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
import 'design/typography.dart';
import 'design/widgets/rg_bottom_tab_bar.dart';
import 'debug/widget_gallery.dart';
import 'features/explore/explore_screen.dart';
import 'features/home/home_screen.dart';
import 'features/paper/paper_screen.dart';
import 'features/reader/reader_screen.dart';

const _tabs = [
  RgTab('홈', 'house'),
  RgTab('탐색', 'compass'),
  RgTab('보관함', 'bookmark'),
  RgTab('설정', 'sliders-vertical'),
];

// ponytail: 나머지 탭 본문은 M2에서 features/<화면>/ 위젯으로 교체한다.
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
              GoRoute(path: ':date', builder: (_, state) => HomeScreen(date: state.pathParameters['date'])),
            ],
          ),
        ]),
        for (final (path, title) in const [
          ('/library', '보관함'),
          ('/settings', '설정'),
        ])
          StatefulShellBranch(routes: [
            GoRoute(path: path, builder: (_, _) => _PlaceholderTab(title: title)),
          ]),
      ],
    ),
    // S02·S03은 탭바 없이 쉘 위로 푸시된다(7.0).
    GoRoute(
      path: '/paper/:id',
      builder: (_, state) => PaperScreen(paperId: state.pathParameters['id']!),
      routes: [
        // ?s=문장ID: C01에서 들어오면 그 문장 쌍으로 스크롤
        GoRoute(
          path: 'reader',
          builder: (_, state) => ReaderScreen(
            paperId: state.pathParameters['id']!,
            initialSentenceId: state.uri.queryParameters['s'],
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

class _PlaceholderTab extends StatelessWidget {
  const _PlaceholderTab({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: RgSpace.topBar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          child: Row(children: [
            Expanded(child: Text(title, style: RgText.titleDetail)),
            if (kDebugMode && title == '설정')
              TextButton(onPressed: () => context.push('/gallery'), child: const Text('위젯 갤러리')),
          ]),
        ),
      ),
    );
  }
}
