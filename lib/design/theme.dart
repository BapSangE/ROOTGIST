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
);
