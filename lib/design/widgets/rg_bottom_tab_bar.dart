import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../tokens.dart';
import '../typography.dart';

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
          for (var i = 0; i < tabs.length; i++)
            Expanded(child: _TabItem(tab: tabs[i], selected: i == currentIndex, onTap: () => onTap(i))),
        ],
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  const _TabItem({required this.tab, required this.selected, required this.onTap});
  final RgTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.selected ? RgColors.textPrimary : RgColors.textSecondary;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.tab.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedOpacity(
          opacity: _pressed ? 0.85 : 1,
          duration: const Duration(milliseconds: 100),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: widget.selected ? RgColors.fillSelected : null,
              borderRadius: BorderRadius.circular(RgRadius.pill),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: RgSpace.s2,
              children: [
                SvgPicture.asset(
                  'assets/icons/${widget.tab.icon}.svg',
                  width: 22,
                  height: 22,
                  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
                ),
                Text(
                  widget.tab.label,
                  style: RgText.tabLabel.copyWith(
                    color: color,
                    fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
