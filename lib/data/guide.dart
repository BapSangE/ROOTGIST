import 'package:flutter/foundation.dart';

// 처음 쓰는 사람 안내(시안 design-preview/src/onboarding_guide.html, 2026-11-03). 저장은 storage.dart.
// onboardingDone: 첫 실행 온보딩 4장을 끝냈거나 건너뛰었다. 설정 › 사용 방법에서 다시 볼 수 있다.
final onboardingDone = ValueNotifier(false);

// 기능에 처음 들어갈 때 한 번만 뜨는 도움말 중 이미 본 것. 「도움말 다시 보기」가 비운다.
final tipsSeen = ValueNotifier<Set<String>>({});
const tipReader = 'reader', tipNews = 'news';
