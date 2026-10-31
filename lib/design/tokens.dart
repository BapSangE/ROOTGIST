import 'package:flutter/material.dart';

// 리디자인 「Ink & Paper」(design-preview/DESIGN_SYSTEM.md). 화면 코드에 HEX·숫자를 직접 쓰지 않는다.
// 검정 잉크와 바탕만으로 위계를 만든다: 색은 새 글 점(빨강)과 리더 용어 하이라이트(노랑)뿐이다.

// 화면 바탕 두 가지(설정 › 읽기 설정 › 화면 바탕). 배치는 같고 바탕·카드·선·새 글 점만 다르다.
// 흰색(기본): 흰 바탕 + 연한 회색 카드 + 선명한 빨간 점. 종이: 따뜻한 바탕 + 흰 카드 + 로고 주황 점(Ink & Paper 첫 시안).
enum Backdrop { white, paper }

class RgPalette {
  const RgPalette({
    required this.bgApp,
    required this.bgReading,
    required this.surfaceCard,
    required this.fill,
    required this.line,
    required this.divider,
    required this.grabber,
    required this.newDot,
    required this.newText,
  });
  final Color bgApp, bgReading, surfaceCard, fill, line, divider, grabber, newDot, newText;

  static const white = RgPalette(
    bgApp: Color(0xFFFFFFFF),
    bgReading: Color(0xFFFFFFFF),
    surfaceCard: Color(0xFFF4F4F2), // 연한 회색 카드(보조 글자 대비 4.9:1)
    fill: Color(0xFFE7E7E3), // 회색 카드 위에서도 칩·태그가 보이게 한 단계 진하게
    line: Color(0xFFE6E6E3),
    divider: Color(0xFFE3E3E0),
    grabber: Color(0xFFD9D9D6),
    newDot: Color(0xFFF0362B), // 선명한 빨강
    newText: Color(0xFFD42A20), // 「새 글」 글자: 점보다 한 단계 진하게(회색 카드 위 4.6:1)
  );
  // 어두운 화면(설정 › 화면 모드). 바탕 선택(흰색·종이)과 상관없이 이 한 벌.
  static const dark = RgPalette(
    bgApp: Color(0xFF0C0C0B), // 카드와 차이를 벌리려 거의 검정(사용자 피드백)
    bgReading: Color(0xFF0F0F0E),
    surfaceCard: Color(0xFF222220),
    fill: Color(0xFF30302D), // 카드 위 칩·태그
    line: Color(0xFF3A3A36),
    divider: Color(0xFF31312E),
    grabber: Color(0xFF55554F),
    newDot: Color(0xFFFF5449),
    newText: Color(0xFFFF6A5F), // 카드 위 5.7:1
  );
  static const paper = RgPalette(
    bgApp: Color(0xFFF4F4F1),
    bgReading: Color(0xFFFAFAF7),
    surfaceCard: Color(0xFFFFFFFF),
    fill: Color(0xFFEBEBE6),
    line: Color(0xFFE4E4DF),
    divider: Color(0xFFE4E4DF),
    grabber: Color(0xFFD9D9D3),
    newDot: Color(0xFFE0533A), // 로고 주황
    newText: Color(0xFFC2462E), // 「새 글」 글자(종이 바탕 위 4.5:1)
  );
}

// 지금 고른 바탕·화면 모드. 바꾸면 main.dart가 앱 전체를 다시 그린다. 저장은 storage.dart.
final backdrop = ValueNotifier(Backdrop.white);

enum Appearance { system, light, dark }

final appearance = ValueNotifier(Appearance.system);
final platformDark = ValueNotifier(false); // 기기 설정의 다크 모드(main.dart가 맞춘다)
bool get isDark => appearance.value == Appearance.dark || (appearance.value == Appearance.system && platformDark.value);
RgPalette get _p => isDark ? RgPalette.dark : (backdrop.value == Backdrop.paper ? RgPalette.paper : RgPalette.white);
RgInk get _i => isDark ? RgInk.dark : RgInk.light;

// 바탕(흰색·종이)과 상관없이 밝은/어두운 화면에서만 갈리는 색
class RgInk {
  const RgInk({
    required this.surfaceRaised,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.textTertiary,
    required this.highlight,
    required this.highlightActive,
    required this.actionPrimary,
    required this.onAction,
    required this.overlayDim,
    required this.pressOverlay,
    required this.thumb,
  });
  final Color surfaceRaised, textPrimary, textBody, textSecondary, textTertiary, highlight, highlightActive,
      actionPrimary, onAction, overlayDim, pressOverlay, thumb;

  static const light = RgInk(
    surfaceRaised: Color(0xFFFFFFFF), // 늘 흰 면: 탭바, 시트, 세그먼트 선택 알약, 외곽선 버튼, 하단 버튼 줄
    textPrimary: Color(0xFF0E0E0D),
    textBody: Color(0xFF33332F),
    textSecondary: Color(0xFF6B6B65), // 바탕 대비 5.0:1
    textTertiary: Color(0xFF9B9B94), // 번호·셰브론 같은 장식만
    highlight: Color(0xFFFFEFA3), // 리더 용어(레퍼런스 011)
    highlightActive: Color(0xFFFFE27A),
    actionPrimary: Color(0xFF0E0E0D),
    onAction: Color(0xFFFFFFFF),
    overlayDim: Color(0x520E0E0D), // 0.32
    pressOverlay: Color(0x0A000000),
    thumb: Color(0xFFFFFFFF),
  );
  // 어두운 화면: 면은 바탕 → 카드 → 떠 있는 면 순으로 밝아지고, 주 버튼은 밝은 면 + 검정 글자로 뒤집힌다.
  static const dark = RgInk(
    surfaceRaised: Color(0xFF222220), // 탭바·시트·하단 버튼 줄: 카드와 같은 밝기(밝으면 화면 아래가 떠 보인다)
    textPrimary: Color(0xFFEDEDE9),
    textBody: Color(0xFFCFCFC9),
    textSecondary: Color(0xFFA3A39C), // 카드 대비 6.3:1
    textTertiary: Color(0xFF75756F),
    highlight: Color(0xFF4A3F12), // 어두운 노랑 면 + 밝은 글자(10:1)
    highlightActive: Color(0xFF66561A),
    actionPrimary: Color(0xFFEDEDE9),
    onAction: Color(0xFF111110),
    overlayDim: Color(0x99000000),
    pressOverlay: Color(0x14FFFFFF),
    thumb: Color(0xFF4E4E49), // 세그먼트 선택 알약·슬라이더 손잡이: 칩 면보다 한 단계 밝게
  );
}

abstract class RgColors {
  // 바탕·화면 모드에 따라 바뀌는 색(getter라 const 안에 쓸 수 없다)
  static Color get bgApp => _p.bgApp;
  static Color get bgReading => _p.bgReading;
  static Color get surfaceCard => _p.surfaceCard; // 카드
  static Color get fillBadgeOnCard => _p.fill;
  static Color get fillBadgeOnBg => _p.fill;
  static Color get fillNeutral => _p.fill;
  static Color get fillSelected => _p.fill;
  static Color get borderDefault => _p.line;
  static Color get dividerCard => _p.divider;
  static Color get dividerReading => _p.divider;
  static Color get highlightOriginal => _p.fill; // 「함께」의 원문 쪽 용어는 옅은 회색
  static Color get grabber => _p.grabber;
  static Color get newDot => _p.newDot; // 새 글 점(설정 공지사항, 탐색 칸 이름 옆)
  static Color get newText => _p.newText; // 공식 소식 출처 줄의 「새 글」 글자

  static Color get surfaceRaised => _i.surfaceRaised;
  static Color get textPrimary => _i.textPrimary;
  static Color get textBody => _i.textBody;
  static Color get textSecondary => _i.textSecondary;
  static Color get textTertiary => _i.textTertiary;
  static Color get highlight => _i.highlight;
  static Color get highlightActive => _i.highlightActive;
  static Color get actionPrimary => _i.actionPrimary; // 주 버튼 면(밝은 화면 검정, 어두운 화면 밝은 회색)
  static Color get onAction => _i.onAction; // 주 버튼 위 글자
  static Color get overlayDim => _i.overlayDim;
  static Color get pressOverlay => _i.pressOverlay; // 눌림 덮개
  static Color get thumb => _i.thumb; // 세그먼트 선택 알약·슬라이더 손잡이

  static Color get hotScore => isDark ? const Color(0xFFF59E5B) : const Color(0xFFC2410C); // 화제 점수(카드 위 4.6:1·7:1)
  static const onInkMuted = Color(0xFFA9A9A2); // 리더 검정 조절 알약의 고르지 않은 칸
}

// 출처 칩 색(디자인 피드백 2026-10-31 A안): 원색·쌩 검정 대신 「연한 바탕 + 같은 계열 진한 글자」 한 규칙.
// 흰 글자·검정 글자가 섞이지 않고, 글자 대비는 모두 4.5:1 이상(밝은 화면 6~8:1). 어두운 화면은 어둡게 낮춘 바탕 + 밝은 글자.
// Google은 4색 조합을 흉내 내지 않고 파랑 하나만. 로고 모양·글꼴은 따라 하지 않는다. 권리 검토: docs/RIGHTS.md 4장.
// 시안: design-preview/src/feedback_2026-10-31.html, 피그마 「홈·탐색 A안」.
class RgBrandTone {
  const RgBrandTone(this.bg, this.fg, this.darkBg, this.darkFg);
  final Color bg, fg, darkBg, darkFg;
  Color get background => isDark ? darkBg : bg;
  Color get foreground => isDark ? darkFg : fg;
}

abstract class RgBrand {
  static const anthropic = RgBrandTone(Color(0xFFF6E3D6), Color(0xFF8A3D1E), Color(0xFF3D271D), Color(0xFFF2B79A)); // 살구
  static const openai = RgBrandTone(Color(0xFFE6E6E2), Color(0xFF2E2E2B), Color(0xFF34342F), Color(0xFFDCDCD6)); // 회색(흑백 브랜드)
  static const google = RgBrandTone(Color(0xFFDDE8FA), Color(0xFF1A4F9E), Color(0xFF1C2A42), Color(0xFFA9C7F5)); // 하늘
  static const huggingface = RgBrandTone(Color(0xFFFFF0BA), Color(0xFF6B5400), Color(0xFF3A3215), Color(0xFFF3D774)); // 노랑
  static const nvidia = RgBrandTone(Color(0xFFE5F1CF), Color(0xFF3E6400), Color(0xFF26331A), Color(0xFFBEDC8C)); // 연두
  static const meta = RgBrandTone(Color(0xFFE3E6FA), Color(0xFF3A47A8), Color(0xFF23264A), Color(0xFFB4BCF5)); // 남색
  static const xai = openai;
}

// 움직임(design-preview/DESIGN_SYSTEM.md 「움직임·진동」). 앱 전체가 같은 속도·곡선을 쓴다.
// 「동작 줄이기」(MediaQuery.disableAnimations)면 길이를 0으로: RgMotion.of(context, RgMotion.base).
abstract class RgMotion {
  static const press = Duration(milliseconds: 100); // 눌림 들어감
  static const release = Duration(milliseconds: 160); // 떼고 돌아옴(살짝 튐)
  static const fast = Duration(milliseconds: 150); // 칩 채움·색 바뀜
  static const base = Duration(milliseconds: 220); // 미끄러짐·접힘·탭 넘김
  static const curve = Curves.easeOutCubic;
  static const pressScale = 0.98; // 행·카드 눌림
  static Duration of(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

abstract class RgSpace {
  static const s2 = 2.0, s4 = 4.0, s6 = 6.0, s8 = 8.0, s10 = 10.0, s12 = 12.0, s14 = 14.0,
      s16 = 16.0, s18 = 18.0, s20 = 20.0, s22 = 22.0, s24 = 24.0, s28 = 28.0, s32 = 32.0, s36 = 36.0, s40 = 40.0;
  static const gutterCard = 16.0, gutterText = 20.0, gutterReader = 24.0;
  // 탭바가 바닥에 붙어(Scaffold.bottomNavigationBar) 본문이 그 위에서 끝난다. 스크롤 끝 여백만.
  static const topBar = 52.0, bottomScrollInset = 40.0, minTouch = 44.0;
  static const floatingBottom = 30.0; // 리더 떠 있는 조절 알약의 하단 띄움
  static const tabBar = 52.0; // 탭바 높이(하단 안전 영역 제외)
}

abstract class RgRadius {
  static const card = 22.0, cardDark = 26.0, sheet = 30.0, box = 16.0, badge = 10.0, term = 4.0, pill = 999.0;
}

// 그림자는 쓰지 않는다. 예외는 세그먼트의 선택 알약 하나(1px, 6%).
abstract class RgShadow {
  static const segment = [BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1), blurRadius: 2)];
  static const thumb = [BoxShadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 4)]; // 글자 크기 슬라이더
}
