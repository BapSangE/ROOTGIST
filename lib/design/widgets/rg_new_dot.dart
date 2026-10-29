import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';

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

// 「새 글」 두 글자(목록 행 머리 줄 끝). 출처 칩이 회사 대표 색이라 점 대신 글자로 뜻을 분명히 한다.
// 작은 글자라 점보다 한 단계 진한 newText(대비 4.5:1 이상). 읽으면 작아지며 흐려져 사라지고(180ms) 자리를 메운다.
class RgNewLabel extends StatelessWidget {
  const RgNewLabel({super.key, this.visible = true, this.label = '새 글'});
  final bool visible;
  final String label; // 모델 목록은 「새로 진입」

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
            ? Text(
                label,
                key: const ValueKey(true),
                style: RgText.caption.copyWith(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: RgColors.newText),
              )
            : const SizedBox(key: ValueKey(false)),
      ),
    );
  }
}
