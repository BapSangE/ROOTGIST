import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';
import 'rg_pressable.dart';

// 밑줄 탭: 글자 + 고른 칸 아래 2pt 검정 선, 전체 아래 가는 선. 위의 알약 세그먼트(탐색 칸)와 위계를 나눈다.
// 공식 소식 안 「발표 | 업데이트」. 칸을 바꾸면 밑줄이 옆으로 미끄러진다(세그먼트 알약처럼 220ms).
class RgUnderlineTabs extends StatefulWidget {
  const RgUnderlineTabs({super.key, required this.labels, required this.selected, required this.onTap, this.dots = const {}});
  final List<String> labels;
  final int selected;
  final Set<int> dots; // 새 글 점
  final ValueChanged<int> onTap;

  @override
  State<RgUnderlineTabs> createState() => _RgUnderlineTabsState();
}

class _RgUnderlineTabsState extends State<RgUnderlineTabs> {
  final _row = GlobalKey();
  late var _keys = [for (final _ in widget.labels) GlobalKey()];
  (double, double)? _bar; // 고른 칸의 (왼쪽, 폭). 그린 뒤에 잰다(글자 폭은 굵기·배율에 따라 다르다)

  @override
  void didUpdateWidget(RgUnderlineTabs old) {
    super.didUpdateWidget(old);
    if (old.labels.length != widget.labels.length) _keys = [for (final _ in widget.labels) GlobalKey()];
  }

  void _measure() {
    final row = _row.currentContext?.findRenderObject() as RenderBox?;
    final box = _keys[widget.selected].currentContext?.findRenderObject() as RenderBox?;
    if (row == null || box == null || !row.hasSize || !box.hasSize) return;
    final bar = (box.localToGlobal(Offset.zero, ancestor: row).dx, box.size.width);
    if (bar != _bar && mounted) setState(() => _bar = bar);
  }

  // 하단 탭바처럼 화면 틀이라 글자 배율은 1.35배에서 멈춘다(ChromeTextScale)
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final still = MediaQuery.disableAnimationsOf(context) || _bar == null;
    return ChromeTextScale(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.borderDefault))),
        child: Stack(children: [
          Row(key: _row, spacing: RgSpace.s20, children: [
            for (final (i, label) in widget.labels.indexed)
              Semantics(
                button: true,
                selected: i == widget.selected,
                child: RgPressable(
                  onTap: () {
                    if (i != widget.selected) HapticFeedback.selectionClick();
                    widget.onTap(i);
                  },
                  child: Container(
                    key: _keys[i],
                    constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                    alignment: Alignment.center,
                    child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                      Text(
                        label,
                        style: RgText.titleList.copyWith(
                          fontSize: 16,
                          fontWeight: i == widget.selected ? FontWeight.w700 : FontWeight.w500,
                          color: i == widget.selected ? RgColors.textPrimary : RgColors.textSecondary,
                        ),
                      ),
                      if (widget.dots.contains(i)) const RgNewDot(),
                    ]),
                  ),
                ),
              ),
          ]),
          if (_bar case (final left, final width))
            AnimatedPositioned(
              duration: still ? Duration.zero : RgMotion.base,
              curve: RgMotion.curve,
              left: left,
              width: width,
              bottom: 0,
              height: 2,
              child: const ColoredBox(color: RgColors.textPrimary),
            ),
        ]),
      ),
    );
  }
}
