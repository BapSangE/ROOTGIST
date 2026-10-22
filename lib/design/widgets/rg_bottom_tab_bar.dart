import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_pressable.dart';

class RgTab {
  const RgTab(this.label, this.icon);
  final String label;
  final String icon; // assets/icons/<icon>.svg
}

// HANDOFF 6장 RgBottomTabBar: 높이 64, 내부 여백 6, 4칸 균등(간격 4), 아이콘 22 + 라벨 11/14, 간격 2.
class RgBottomTabBar extends StatelessWidget {
  const RgBottomTabBar({super.key, required this.tabs, required this.currentIndex, required this.onTap});

  final List<RgTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
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
          for (var i = 0; i < tabs.length; i++) Expanded(child: _tab(tabs[i], i == currentIndex, () => onTap(i))),
        ],
      ),
    );
  }

  Widget _tab(RgTab tab, bool selected, VoidCallback onTap) {
    final color = selected ? RgColors.textPrimary : RgColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
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
              RgIcon(tab.icon, size: 22, color: color),
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
