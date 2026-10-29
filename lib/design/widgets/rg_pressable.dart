import 'package:flutter/material.dart';

import '../tokens.dart';
import 'package:flutter_svg/flutter_svg.dart';

// 눌림 피드백: ripple 대신 불투명도 0.85 (HANDOFF 6장 공통 규칙).
// row: 행·카드는 누르는 동안 98%로 작아지고 4% 어두워진다(100ms). 떼면 살짝 튀며 돌아온다(160ms).
// 「동작 줄이기」면 크기는 그대로, 어두워지기만.
class RgPressable extends StatefulWidget {
  const RgPressable({super.key, required this.onTap, required this.child, this.row = false});
  final VoidCallback? onTap;
  final Widget child;
  final bool row;

  @override
  State<RgPressable> createState() => _RgPressableState();
}

class _RgPressableState extends State<RgPressable> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: widget.row
          ? AnimatedScale(
              scale: _pressed && !still ? RgMotion.pressScale : 1,
              duration: _pressed ? RgMotion.press : RgMotion.release,
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: AnimatedContainer(
                duration: _pressed ? RgMotion.press : RgMotion.release,
                foregroundDecoration: BoxDecoration(color: _pressed ? const Color(0x0A000000) : const Color(0x00000000)),
                child: widget.child,
              ),
            )
          : AnimatedOpacity(
              opacity: _pressed ? 0.85 : 1,
              duration: RgMotion.press,
              child: widget.child,
            ),
    );
  }
}

// assets/icons/<name>.svg 를 지정 색으로.
class RgIcon extends StatelessWidget {
  const RgIcon(this.name, {super.key, this.size = 20, required this.color});
  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}
