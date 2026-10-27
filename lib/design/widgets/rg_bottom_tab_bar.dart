import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';
import 'rg_pressable.dart';

class RgTab {
  const RgTab(this.label, this.icon);
  final String label;
  final String icon; // assets/icons/<icon>.svg
}

// HANDOFF 6장 RgBottomTabBar: 높이 64, 내부 여백 6, 4칸 균등(간격 4), 아이콘 22 + 라벨 11/14, 간격 2.
class RgBottomTabBar extends StatelessWidget {
  const RgBottomTabBar({super.key, required this.tabs, required this.currentIndex, required this.onTap, this.dots = const {}});

  final List<RgTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Set<int> dots; // 새 글 점을 달 칸(지금은 설정 = 안 읽은 공지)

  @override
  Widget build(BuildContext context) {
    return ChromeTextScale(child: _bar());
  }

  Widget _bar() {
    return Container(
      height: 64,
      padding: const EdgeInsets.all(RgSpace.s6),
      decoration: BoxDecoration(
        color: RgColors.surfaceCard,
        borderRadius: BorderRadius.circular(RgRadius.pill),
        boxShadow: RgShadow.tabBar,
      ),
      child: Row(
        spacing: RgSpace.s4,
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(child: _tab(tabs[i], i == currentIndex, () => onTap(i), dots.contains(i))),
        ],
      ),
    );
  }

  Widget _tab(RgTab tab, bool selected, VoidCallback onTap, bool dot) {
    final color = selected ? RgColors.textPrimary : RgColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: dot ? '${tab.label}, 새 글' : tab.label,
      excludeSemantics: true,
      onTap: onTap, // excludeSemantics가 하위의 탭 동작까지 지우므로 직접 넘긴다(TalkBack 두 번 탭)
      child: RgPressable(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? RgColors.fillSelected : null,
            borderRadius: BorderRadius.circular(RgRadius.pill),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: RgSpace.s2,
            children: [
              // 점은 아이콘 오른쪽 위에 겹친다(아이콘 자리는 그대로)
              Stack(clipBehavior: Clip.none, children: [
                RgIcon(tab.icon, size: 22, color: color),
                if (dot) const Positioned(top: -1, right: -3, child: RgNewDot(size: 7)),
              ]),
              Text(
                tab.label,
                style: RgText.tabLabel.copyWith(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
