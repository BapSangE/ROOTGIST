import 'package:flutter/material.dart';

import '../tokens.dart';
import 'rg_pressable.dart';

// RgBottomSheet: 상단 모서리 28, 여백 위10/좌우24/아래40, 손잡이 36×5, 최대 높이 85%.
// 바깥 탭·뒤로가기·아래 스와이프로 닫힘(showModalBottomSheet 기본 동작). 「닫기」 버튼은 두지 않는다(피드백).
// 화면 읽기 사용자는 밀어 내리기를 하기 어려워, 손잡이를 「닫기」 버튼으로 읽히게 하고 누르면 닫는다.
Future<T?> showRgBottomSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true, // 탭 화면에서 열어도 떠 있는 탭바 위로 덮는다
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
          Semantics(
            button: true,
            label: '닫기',
            excludeSemantics: true,
            onTap: () => Navigator.of(context).pop(),
            child: RgPressable(
              onTap: () => Navigator.of(context).pop(),
              // 손잡이 둘레 위아래로 눌리는 영역을 둔다(보이는 손잡이는 36×5 그대로)
              child: SizedBox(
                height: 24,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(color: RgColors.grabber, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
          builder(context),
        ],
      ),
    ),
  );
}
