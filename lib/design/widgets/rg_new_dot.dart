import 'package:flutter/material.dart';

import '../tokens.dart';

// 새 글 점 6pt(포인트 색 하나, 개수는 세지 않는다). 화면 읽기에는 「새 글」.
class RgNewDot extends StatelessWidget {
  const RgNewDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '새 글',
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: RgColors.newDot, shape: BoxShape.circle),
    ),
  );
}

// 목록 행 머리 줄 끝의 새 글 표시. 글자 「새 글」은 시각·관련 수와 같은 무게로 붙어 위계를 흐려(디자인 피드백 2026-10-31 4번)
// 점 하나로 바꿨다. 칩이 연한 색이라 빨간 점이 묻히지 않는다. 화면 읽기에는 label을 읽는다.
// 읽으면 작아지며 흐려져 사라지고(180ms) 자리를 메운다.
class RgNewLabel extends StatelessWidget {
  const RgNewLabel({super.key, this.visible = true, this.label = '새 글'});
  final bool visible;
  final String label; // 화면 읽기 이름. 모델 목록은 「새로 진입」

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, const Duration(milliseconds: 180));
    return AnimatedSize(
      duration: d,
      curve: RgMotion.curve,
      child: AnimatedSwitcher(
        duration: d,
        transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: 0.6, end: 1.0).animate(a), child: child)),
        child: visible
            ? Semantics(
                key: const ValueKey(true),
                label: label,
                child: Container(width: 6, height: 6, decoration: BoxDecoration(color: RgColors.newDot, shape: BoxShape.circle)),
              )
            : const SizedBox(key: ValueKey(false)),
      ),
    );
  }
}
