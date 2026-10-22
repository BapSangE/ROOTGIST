import 'package:flutter/material.dart';

import '../tokens.dart';

// RgBottomSheet: 상단 모서리 28, 여백 위10/좌우24/아래40, 손잡이 36×5, 최대 높이 85%.
// 바깥 탭·뒤로가기·아래 스와이프로 닫힘(showModalBottomSheet 기본 동작).
Future<T?> showRgBottomSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    barrierColor: RgColors.overlayDim,
    backgroundColor: RgColors.surfaceCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(RgRadius.sheet))),
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (context) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(color: RgColors.grabber, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          builder(context),
        ],
      ),
    ),
  );
}
