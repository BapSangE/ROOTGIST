import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens.dart';
import 'rg_pressable.dart';

// RgBottomSheet: 상단 모서리 30, 여백 위10/좌우24/아래40, 손잡이 38×5, 최대 높이 85%. 시트는 탭바도 덮는다.
// 바깥 탭·뒤로가기·아래 스와이프로 닫힘. 「닫기」 버튼은 두지 않는다(피드백).
// 화면 읽기 사용자는 밀어 내리기를 하기 어려워, 손잡이를 「닫기」 버튼으로 읽히게 하고 누르면 닫는다.
//
// 끌어 내리기(2026-11-11): 본문 전체가 iOS 튕김 스크롤이라 위쪽을 잡고 내려도 스크롤이 끌기를 가져가 시트가 안 내려갔다.
// · 손잡이 줄은 스크롤 밖에 둔다 → 거기서 끌면 시트 기본 끌기가 그대로 받는다.
// · 본문은 튕기지 않는 스크롤 → 짧은 시트는 아무 데나 잡아도 시트가 내려간다.
// · 긴 시트는 맨 위에서 더 내리면 손가락을 따라 시트가 내려가고, 충분히(80) 내리거나 빠르게 털면 닫힌다. 아니면 제자리로.
Future<T?> showRgBottomSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  HapticFeedback.selectionClick(); // 시트가 열릴 때 가벼운 진동 한 번(어느 시트든 같게, 2026-11-11)
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true, // 탭 화면에서 열어도 떠 있는 탭바 위로 덮는다
    barrierColor: RgColors.overlayDim,
    // 바탕·모서리는 본문(_RgSheetBody)이 그린다: 끌어 내릴 때 바탕까지 함께 내려가야 해서
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (context) => _RgSheetBody(child: builder(context)),
  );
}

class _RgSheetBody extends StatefulWidget {
  const _RgSheetBody({required this.child});
  final Widget child;

  @override
  State<_RgSheetBody> createState() => _RgSheetBodyState();
}

class _RgSheetBodyState extends State<_RgSheetBody> with SingleTickerProviderStateMixin {
  static const _closeAt = 80.0; // 이만큼 내리면 닫힘
  static const _flingClose = 700.0; // 아래로 이 속도(px/s) 이상 털면 닫힘

  // 맨 위에서 더 끌어 내린 거리. 값이 있으면 시트 전체를 그만큼 내려 그린다.
  late final _drag = AnimationController.unbounded(vsync: this);
  bool _closing = false;

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || _closing) return false;
    if (n is OverscrollNotification && n.dragDetails != null && n.overscroll < 0) {
      _drag.value = _drag.value - n.overscroll; // 위 끝에서 내린 만큼(손가락을 그대로 따라)
    } else if (n is ScrollUpdateNotification && n.dragDetails != null && _drag.value > 0 && (n.scrollDelta ?? 0) > 0) {
      _drag.value = math.max(0, _drag.value - n.scrollDelta!); // 내렸다가 다시 올리면 시트부터 되돌린다
    } else if (n is ScrollEndNotification && _drag.value > 0) {
      final v = n.dragDetails?.primaryVelocity ?? 0;
      if (_drag.value >= _closeAt || v >= _flingClose) {
        _close();
      } else {
        _drag.animateTo(0, duration: RgMotion.of(context, RgMotion.base), curve: Curves.easeOutCubic);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final grabber = Semantics(
      button: true,
      label: '닫기',
      excludeSemantics: true,
      onTap: _close,
      child: RgPressable(
        onTap: _close,
        // 손잡이 둘레 위아래로 눌리는(또 끌리는) 영역을 둔다(보이는 손잡이는 38×5 그대로)
        child: SizedBox(
          height: 24,
          child: Center(
            child: Container(
              width: 38,
              height: 5,
              decoration: BoxDecoration(color: RgColors.grabber, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _drag,
      builder: (context, child) => Transform.translate(offset: Offset(0, _drag.value), child: child),
      child: Material(
        color: RgColors.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(RgRadius.sheet))),
        clipBehavior: Clip.antiAlias,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: grabber),
          Flexible(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
