import 'package:flutter/material.dart';

// 리디자인 「Ink & Paper」(design-preview/DESIGN_SYSTEM.md). 화면 코드에 HEX·숫자를 직접 쓰지 않는다.
// 흰 종이 위 검정 잉크: 색은 새 글 점(주황)과 리더 용어 하이라이트(노랑)뿐이다.

abstract class RgColors {
  static const bgApp = Color(0xFFF4F4F1); // 따뜻한 종이 바탕(중립 회색과 비교 후 유지)
  static const bgReading = Color(0xFFFAFAF7);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF0E0E0D);
  static const textBody = Color(0xFF33332F);
  static const textSecondary = Color(0xFF6B6B65); // 바탕 대비 5.0:1
  static const textTertiary = Color(0xFF9B9B94); // 번호·셰브론 같은 장식만
  static const fillBadgeOnCard = Color(0xFFEBEBE6);
  static const fillBadgeOnBg = Color(0xFFE4E4DF);
  static const fillNeutral = Color(0xFFEBEBE6);
  static const fillSelected = Color(0xFFEBEBE6);
  static const borderDefault = Color(0xFFE4E4DF);
  static const dividerCard = Color(0xFFE4E4DF);
  static const dividerReading = Color(0xFFE4E4DF);
  static const highlight = Color(0xFFFFEFA3); // 리더 용어(레퍼런스 011)
  static const highlightActive = Color(0xFFFFE27A);
  static const highlightOriginal = Color(0xFFEBEBE6); // 「함께」의 원문 쪽 용어는 옅은 회색
  static const actionPrimary = Color(0xFF0E0E0D);
  static const onAction = Color(0xFFFFFFFF);
  static const onInkSecondary = Color(0xFFB9B9B2); // 다크 카드 위 보조 글자(8.6:1)
  static const onInkMuted = Color(0xFFA9A9A2); // 검정 세그먼트의 고르지 않은 칸
  static const glassOnInk = Color(0x24FFFFFF); // 다크 카드 위 원형 버튼(흰 14%)
  static const lineOnInk = Color(0x24FFFFFF);
  static const tagOnInk = Color(0x1FFFFFFF); // 다크 카드 위 태그(흰 12%)
  static const overlayDim = Color(0x520E0E0D); // 0.32
  static const grabber = Color(0xFFD9D9D3);
  static const newDot = Color(0xFFE0533A); // 새 글 점. 흑백 화면에서 유일한 포인트 색
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
