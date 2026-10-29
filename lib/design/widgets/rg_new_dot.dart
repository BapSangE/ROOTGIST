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

// 「새 글」 두 글자(공식 소식 출처 줄 끝). 출처 배지가 회사 대표 색이라 점 대신 글자로 뜻을 분명히 한다.
// 작은 글자라 점보다 한 단계 진한 newText(대비 4.5:1 이상).
class RgNewLabel extends StatelessWidget {
  const RgNewLabel({super.key});

  @override
  Widget build(BuildContext context) => Text(
    '새 글',
    style: RgText.caption.copyWith(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700, color: RgColors.newText),
  );
}
