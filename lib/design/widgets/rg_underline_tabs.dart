import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';
import 'rg_pressable.dart';

// 선택한 탭의 실제 폭을 재어 한 개의 밑줄을 이동한다. 기본/탐색 표현이
// 같은 모션을 공유하므로 빠른 재선택도 현재 위치에서 새 선택으로 이어진다.
class RgUnderlineTabs extends StatefulWidget {
  const RgUnderlineTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
    this.dots = const {},
  }) : information = const {},
       _explore = false;

  // 탐색 시안: 화면 전체 경계, 16/25 글자, 탭 안쪽 여백과 가로 스크롤.
  const RgUnderlineTabs.explore({
    super.key,
    required this.labels,
    required this.selected,
    required this.onTap,
    this.information = const {},
  }) : dots = const {},
       _explore = true;

  final List<String> labels;
  final int selected;
  final Set<int> dots;
  final Set<int> information;
  final ValueChanged<int> onTap;
  final bool _explore;

  @override
  State<RgUnderlineTabs> createState() => _RgUnderlineTabsState();
}

class _RgUnderlineTabsState extends State<RgUnderlineTabs> {
  final _row = GlobalKey();
  late var _keys = [for (final _ in widget.labels) GlobalKey()];
  (double, double)? _bar;

  @override
  void didUpdateWidget(RgUnderlineTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) {
      _keys = [for (final _ in widget.labels) GlobalKey()];
    }
  }

  void _measure() {
    final row = _row.currentContext?.findRenderObject() as RenderBox?;
    final box =
        _keys[widget.selected].currentContext?.findRenderObject() as RenderBox?;
    if (row == null || box == null || !row.hasSize || !box.hasSize) return;
    final bar = (
      box.localToGlobal(Offset.zero, ancestor: row).dx,
      box.size.width,
    );
    if (bar != _bar && mounted) setState(() => _bar = bar);
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final still = MediaQuery.disableAnimationsOf(context) || _bar == null;
    final explore = widget._explore;
    final tabs = Stack(
      children: [
        Row(
          key: _row,
          mainAxisSize: explore ? MainAxisSize.min : MainAxisSize.max,
          spacing: explore ? 0 : RgSpace.s20,
          children: [
            for (final (i, label) in widget.labels.indexed)
              Semantics(
                button: true,
                selected: i == widget.selected,
                // 위치는 눌림으로 작아지기 전 크기로 잰다(키를 눌림 바깥에: 짧게 톡 누르면 바로 97%가 돼 밑줄이 어긋났다)
                child: KeyedSubtree(
                  key: _keys[i],
                  child: RgPressable(
                  onTap: () {
                    if (i != widget.selected) HapticFeedback.selectionClick();
                    widget.onTap(i);
                  },
                  child: Container(
                    constraints: BoxConstraints(
                      minHeight: RgSpace.minTouch,
                      minWidth: explore ? RgSpace.minTouch : 0,
                    ),
                    padding: explore
                        ? const EdgeInsets.fromLTRB(10, 5, 10, 8)
                        : EdgeInsets.zero,
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: explore
                          ? CrossAxisAlignment.center
                          : CrossAxisAlignment.start,
                      spacing: explore ? RgSpace.s4 : 3,
                      children: [
                        Text(
                          label,
                          style: RgText.titleList.copyWith(
                            fontSize: 16,
                            height: explore ? 25 / 16 : null,
                            letterSpacing: explore ? -0.32 : null,
                            fontWeight: explore || i != widget.selected
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: i == widget.selected
                                ? RgColors.textPrimary
                                : RgColors.textSecondary,
                          ),
                        ),
                        if (widget.dots.contains(i)) const RgNewDot(),
                        if (widget.information.contains(i))
                          ExcludeSemantics(
                            child: RgIcon(
                              'info',
                              size: 12,
                              color: RgColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                ),
              ),
          ],
        ),
        if (_bar case (final left, final width))
          AnimatedPositioned(
            duration: still ? Duration.zero : RgMotion.base,
            curve: RgMotion.curve,
            left: left,
            width: width,
            bottom: 0,
            height: 2,
            child: ColoredBox(color: RgColors.textPrimary),
          ),
      ],
    );
    return ChromeTextScale(
      child: Container(
        margin: explore
            ? null
            : const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
        padding: explore
            ? const EdgeInsets.fromLTRB(
                RgSpace.gutterText,
                RgSpace.s6,
                RgSpace.gutterText,
                0,
              )
            : null,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: RgColors.borderDefault)),
        ),
        child: explore
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: tabs,
              )
            : tabs,
      ),
    );
  }
}
