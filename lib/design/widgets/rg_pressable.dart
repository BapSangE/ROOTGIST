import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// 눌림 피드백: ripple 대신 불투명도 0.85 (HANDOFF 6장 공통 규칙).
class RgPressable extends StatefulWidget {
  const RgPressable({super.key, required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedOpacity(
        opacity: _pressed ? 0.85 : 1,
        duration: const Duration(milliseconds: 100),
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
