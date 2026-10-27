import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_shell.dart';
import 'data/storage.dart';
import 'design/theme.dart';
import 'design/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
  await initStorage();
  runApp(const RootgistApp());
}

class RootgistApp extends StatefulWidget {
  const RootgistApp({super.key});

  @override
  State<RootgistApp> createState() => _RootgistAppState();
}

// 화면 바탕(설정 › 읽기 설정)을 바꾸면 앱 전체를 다시 그린다. 색 토큰이 getter라 모든 요소의 build를
// 다시 부르면(핫 리로드의 reassemble과 같은 일, 입력 잠금 없이) 열린 화면·스크롤 위치는 그대로 새 색이 된다.
class _RootgistAppState extends State<RootgistApp> {
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
  }

  @override
  void dispose() {
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
