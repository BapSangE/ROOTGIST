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
