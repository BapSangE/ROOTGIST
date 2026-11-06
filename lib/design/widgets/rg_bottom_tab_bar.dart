import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';
import 'rg_pressable.dart';

class RgTab {
  const RgTab(this.label, this.icon);
  final String label;
  final String icon;
}

// 첨부 시안: 24pt Reicon, 라벨 14pt, 상단 16pt, 기기 하단 안전 영역.
class RgBottomTabBar extends StatelessWidget {
  const RgBottomTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.dots = const {},
  });
  final List<RgTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Set<int> dots;

  @override
  Widget build(BuildContext context) {
    final scale =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.35).scale(14) /
        14;
    final width = (42 * scale + 2).clamp(RgSpace.minTouch, 64.0).toDouble();
    return ChromeTextScale(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              36,
              16,
              36,
              MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              color: RgColors.surfaceRaised.withValues(alpha: 0.94),
              border: Border(top: BorderSide(color: RgColors.borderDefault)),
            ),
            child: SizedBox(
              height: 24 + 8 + 18 * scale,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    SizedBox(
                      width: width,
                      child: _tab(
                        tabs[i],
                        i == currentIndex,
                        () => _select(i),
                        dots.contains(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _select(int i) {
    if (i != currentIndex) HapticFeedback.selectionClick();
    onTap(i);
  }

  Widget _tab(RgTab tab, bool selected, VoidCallback onTap, bool dot) =>
      Semantics(
        button: true,
        selected: selected,
        label: dot ? '${tab.label}, 새 글' : tab.label,
        excludeSemantics: true,
        onTap: onTap,
        child: RgPressable(
          onTap: onTap,
          child: Column(
            spacing: 8,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  RgIcon(
                    tab.icon == 'bookmark' ? 'reicon-library' : tab.icon,
                    size: 24,
                    color: selected
                        ? RgColors.navigationActive
                        : RgColors.navigationInactive,
                  ),
                  if (dot)
                    const Positioned(
                      top: -1,
                      right: -3,
                      child: RgNewDot(size: 7),
                    ),
                ],
              ),
              Text(
                tab.label,
                maxLines: 1,
                style: RgText.tabLabel.copyWith(
                  color: selected
                      ? RgColors.navigationActive
                      : RgColors.navigationLabel,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
}
