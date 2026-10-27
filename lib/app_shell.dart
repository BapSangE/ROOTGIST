import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'design/tokens.dart';
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
  child: ColoredBox(color: RgColors.bgApp, child: Material(type: MaterialType.transparency, child: child)),
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
              GoRoute(path: 'reading', pageBuilder: (_, state) => _page(state, const ReadingSettingsScreen())),
              GoRoute(path: 'source', pageBuilder: (_, state) => _page(state, const DataSourceScreen())),
              GoRoute(path: 'privacy', pageBuilder: (_, state) => _page(state, const PrivacyScreen())),
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
          Positioned.fill(child: shell),
          // 상태바 밑에 배경색 띠: 스크롤한 내용이 시계·배터리 아이콘과 겹치지 않게(에뮬레이터 QA)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.paddingOf(context).top,
            child: const ColoredBox(color: RgColors.bgApp),
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
