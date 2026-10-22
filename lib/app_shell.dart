import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
import 'design/typography.dart';
import 'design/widgets/rg_bottom_tab_bar.dart';

const _tabs = [
  RgTab('홈', 'house'),
  RgTab('탐색', 'compass'),
  RgTab('보관함', 'bookmark'),
  RgTab('설정', 'sliders-vertical'),
];

// ponytail: 탭 본문은 M2에서 features/<화면>/ 위젯으로 교체한다.
final router = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        for (final (path, title) in const [
          ('/home', '오늘의 연구'),
          ('/explore', '탐색'),
          ('/library', '보관함'),
          ('/settings', '설정'),
        ])
          StatefulShellBranch(routes: [
            GoRoute(path: path, builder: (_, _) => _PlaceholderTab(title: title)),
          ]),
      ],
    ),
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
          child: Align(alignment: Alignment.centerLeft, child: Text(title, style: RgText.titleDetail)),
        ),
      ),
    );
  }
}
