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

// 하단 탭바(Ink & Paper): 바닥에 붙은 흰 면 + 위 가는 선. 높이 52 + 하단 안전 영역, 4칸 균등, 아이콘 22 + 라벨 13.
// Scaffold.bottomNavigationBar에 둔다. 탭 화면과 상세 화면(논문·소식·모델) 모두에 있고, 리더와 시트에는 없다.
class RgBottomTabBar extends StatelessWidget {
  const RgBottomTabBar({super.key, required this.tabs, required this.currentIndex, required this.onTap, this.dots = const {}});

  final List<RgTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Set<int> dots; // 새 글 점을 달 칸(지금은 쓰지 않는다: 피드백 「해야 할 일」처럼 보인다)

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ChromeTextScale(
      child: Container(
        padding: EdgeInsets.only(top: RgSpace.s6, bottom: bottom),
        decoration: BoxDecoration(
          color: RgColors.surfaceRaised,
          border: Border(top: BorderSide(color: RgColors.borderDefault)),
        ),
        child: SizedBox(
          height: RgSpace.tabBar,
          child: Row(children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(child: _tab(tabs[i], i == currentIndex, () => onTap(i), dots.contains(i))),
          ]),
        ),
      ),
    );
  }

  Widget _tab(RgTab tab, bool selected, VoidCallback onTap, bool dot) {
    // 고르지 않은 칸은 보조 글자색: 시안의 옅은 회색(faint)은 글자로 쓰기에 대비가 모자랐다(3:1 미만)
    final color = selected ? RgColors.textPrimary : RgColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: dot ? '${tab.label}, 새 글' : tab.label,
      excludeSemantics: true,
      onTap: onTap, // excludeSemantics가 하위의 탭 동작까지 지우므로 직접 넘긴다(TalkBack 두 번 탭)
      child: RgPressable(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          spacing: RgSpace.s4,
          children: [
            // 점은 아이콘 오른쪽 위에 겹친다(아이콘 자리는 그대로)
            Stack(clipBehavior: Clip.none, children: [
              RgIcon(tab.icon, size: 22, color: color),
              if (dot) const Positioned(top: -1, right: -3, child: RgNewDot(size: 7)),
            ]),
            Text(
              tab.label,
              style: RgText.tabLabel.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
