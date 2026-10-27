import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';
import 'rg_pressable.dart';

// 밑줄 탭: 글자 + 고른 칸 아래 2pt 검정 선, 전체 아래 가는 선. 위의 알약 세그먼트(탐색 칸)와 위계를 나눈다.
// 공식 소식 안 「발표 | 업데이트」.
class RgUnderlineTabs extends StatelessWidget {
  const RgUnderlineTabs({super.key, required this.labels, required this.selected, required this.onTap, this.dots = const {}});
  final List<String> labels;
  final int selected;
  final Set<int> dots; // 새 글 점
  final ValueChanged<int> onTap;

  // 하단 탭바처럼 화면 틀이라 글자 배율은 1.35배에서 멈춘다(ChromeTextScale)
  @override
  Widget build(BuildContext context) => ChromeTextScale(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.borderDefault))),
      child: Row(spacing: RgSpace.s20, children: [
        for (final (i, label) in labels.indexed)
          Semantics(
            button: true,
            selected: i == selected,
            child: RgPressable(
              onTap: () => onTap(i),
              child: Container(
                constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == selected ? RgColors.textPrimary : Colors.transparent, width: 2)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, spacing: 3, children: [
                  Text(
                    label,
                    style: RgText.titleList.copyWith(
                      fontSize: 16,
                      fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                      color: i == selected ? RgColors.textPrimary : RgColors.textSecondary,
                    ),
                  ),
                  if (dots.contains(i)) const RgNewDot(),
                ]),
              ),
            ),
          ),
      ]),
    ),
  );
}
