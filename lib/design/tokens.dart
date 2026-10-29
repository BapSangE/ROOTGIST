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

// 지금 고른 바탕. 바꾸면 main.dart가 앱 전체를 다시 그린다. 저장은 storage.dart.
final backdrop = ValueNotifier(Backdrop.white);
RgPalette get _p => backdrop.value == Backdrop.paper ? RgPalette.paper : RgPalette.white;

abstract class RgColors {
  // 바탕에 따라 바뀌는 색(getter라 const 안에 쓸 수 없다)
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

  // 두 바탕에 같은 색
  static const surfaceRaised = Color(0xFFFFFFFF); // 늘 흰 면: 탭바, 시트, 세그먼트 선택 알약, 외곽선 버튼, 하단 버튼 줄
  static const textPrimary = Color(0xFF0E0E0D);
  static const textBody = Color(0xFF33332F);
  static const textSecondary = Color(0xFF6B6B65); // 바탕 대비 5.0:1
  static const textTertiary = Color(0xFF9B9B94); // 번호·셰브론 같은 장식만
  static const highlight = Color(0xFFFFEFA3); // 리더 용어(레퍼런스 011)
  static const highlightActive = Color(0xFFFFE27A);
  static const actionPrimary = Color(0xFF0E0E0D);
  static const onAction = Color(0xFFFFFFFF);
  static const surfaceInk = Color(0xFF2B2B29); // 다크 카드 면(차콜). 순검정은 흰 바탕에서 너무 튄다
  static const chipOnInk = Color(0xFFFFFFFF); // 다크 카드 위 칩: 흰 알약 + 잉크 글자(카드 대비 14.2:1)
  static const onInkSecondary = Color(0xFFB9B9B2); // 다크 카드 위 보조 글자(8.6:1)
  static const onInkMuted = Color(0xFFA9A9A2); // 검정 세그먼트의 고르지 않은 칸
  static const glassOnInk = Color(0x24FFFFFF); // 다크 카드 위 원형 버튼(흰 14%)
  static const lineOnInk = Color(0x24FFFFFF);
  static const tagOnInk = Color(0x1FFFFFFF); // 다크 카드 위 태그(흰 12%)
  static const overlayDim = Color(0x520E0E0D); // 0.32
}

// 공식 소식 출처 배지의 대표 색. 회사당 한 가지, 흰 글자 대비 4.5:1 이상으로 맞춘 앱용 색(정확한 브랜드 HEX 아님).
// Google은 4색 조합을 흉내 내지 않고 파랑 하나만(Google 가이드: 「distinctive color combinations」을 따라 하지 말 것).
// 로고 모양·글꼴은 따라 하지 않고 Pretendard 머리글자만 쓴다. 권리 검토: docs/RIGHTS.md 4장.
abstract class RgBrand {
  static const anthropic = Color(0xFFB5522B); // Anthropic·Claude Code·Claude API(점토 주황, 흰 글자 5.0:1)
  static const openai = Color(0xFF0E0E0D); // OpenAI·OpenAI 커뮤니티(흑백 브랜드)
  static const google = Color(0xFF1A66D9); // Google DeepMind·Google Research(흰 글자 5.3:1)
  static const huggingface = Color(0xFFFFD21E); // Hugging Face(노랑, 검정 글자 13.3:1)
  static const nvidia = Color(0xFF76B900); // NVIDIA(초록, 흰 글자는 2.4:1이라 검정 글자 8.0:1)
  static const meta = Color(0xFF0866FF); // Meta(파랑, 흰 글자 4.8:1)
  static const xai = Color(0xFF0E0E0D); // xAI(흑백 브랜드)
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
