import 'package:flutter/material.dart';

// HANDOFF 5.1·5.3 / UI 명세서 v2.1 14.2. 화면 코드에 HEX·숫자를 직접 쓰지 않는다.

abstract class RgColors {
  static const bgApp = Color(0xFFF6F5F3);
  static const bgReading = Color(0xFFFBFAF7);
  static const surfaceCard = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF111111);
  static const textBody = Color(0xFF3A3835);
  static const textSecondary = Color(0xFF6E6B66);
  static const textTertiary = Color(0xFF8A867F);
  static const fillBadgeOnCard = Color(0xFFF2F1EE);
  static const fillBadgeOnBg = Color(0xFFE9E7E3);
  static const fillNeutral = Color(0xFFEFEEEA);
  static const fillSelected = Color(0xFFF0EFEC);
  static const borderDefault = Color(0xFFE6E3DE);
  static const dividerCard = Color(0xFFEEECE8);
  static const dividerReading = Color(0xFFECE9E4);
  static const highlight = Color(0xFFECEAE6);
  static const highlightActive = Color(0xFFDEDBD5);
  static const actionPrimary = Color(0xFF111111);
  static const onAction = Color(0xFFFFFFFF);
  static const overlayDim = Color(0x47111111); // 0.28
  static const grabber = Color(0xFFDDDAD5);
  static const newDot = Color(0xFFE0533A); // 새 글 점. 흑백 화면에서 유일한 포인트 색
}

abstract class RgSpace {
  static const s2 = 2.0, s4 = 4.0, s6 = 6.0, s8 = 8.0, s10 = 10.0, s12 = 12.0, s14 = 14.0,
      s16 = 16.0, s18 = 18.0, s20 = 20.0, s24 = 24.0, s28 = 28.0, s32 = 32.0, s40 = 40.0;
  static const gutterCard = 16.0, gutterText = 20.0, gutterReader = 24.0;
  static const topBar = 52.0, bottomScrollInset = 136.0, minTouch = 44.0;
  static const floatingBottom = 30.0; // 탭바·하단 주 버튼의 하단 띄움
}

abstract class RgRadius {
  static const card = 24.0, sheet = 28.0, box = 16.0, term = 4.0, pill = 999.0;
}

abstract class RgShadow {
  static const card = [BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 2)];
  static const tabBar = [
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x12000000), offset: Offset(0, 8), blurRadius: 24),
  ];
  static const primaryFloating = [BoxShadow(color: Color(0x1F000000), offset: Offset(0, 8), blurRadius: 20)];
  static const segment = [BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1), blurRadius: 2)];
}
