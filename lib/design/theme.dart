import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

// 무채색 고정. 눌림 피드백은 ripple 대신 불투명도(공통 위젯에서 처리).
final rgTheme = ThemeData(
  useMaterial3: true,
  colorScheme: const ColorScheme.light(
    primary: RgColors.actionPrimary,
    onPrimary: RgColors.onAction,
    surface: RgColors.surfaceCard,
    onSurface: RgColors.textPrimary,
  ),
  scaffoldBackgroundColor: RgColors.bgApp,
  fontFamily: RgText.sans,
  fontFamilyFallback: RgText.sansFallback,
  splashFactory: NoSplash.splashFactory,
  splashColor: Colors.transparent,
  highlightColor: Colors.transparent,
  dividerColor: RgColors.dividerCard,
  // 되돌리기·안내 알림: 검정 면, 모서리 16, 탭바 위(Scaffold.bottomNavigationBar 위로 저절로 뜬다)
  snackBarTheme: SnackBarThemeData(
    backgroundColor: RgColors.actionPrimary,
    contentTextStyle: RgText.bodySmall.copyWith(color: RgColors.onAction, fontWeight: FontWeight.w500),
    actionTextColor: RgColors.onAction,
    behavior: SnackBarBehavior.floating,
    insetPadding: const EdgeInsets.fromLTRB(RgSpace.gutterCard, 0, RgSpace.gutterCard, RgSpace.s12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(RgRadius.box)),
    elevation: 0,
  ),
);
