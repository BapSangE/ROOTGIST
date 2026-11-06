import 'package:flutter/material.dart';

// 목록·읽기 dock에서 같은 저장 피드백을 쓴다. 아이콘과 터치 영역은 그대로 둔다.
class RgBookmarkMotion extends StatefulWidget {
  const RgBookmarkMotion({super.key, required this.saved, required this.child});
  final bool saved;
  final Widget child;

  @override
  State<RgBookmarkMotion> createState() => _RgBookmarkMotionState();
}

class _RgBookmarkMotionState extends State<RgBookmarkMotion>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: 1,
  );
  static final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.85,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.85,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 30,
    ),
  ]);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still) {
      _pop.stop();
      _pop.value = 1;
    }
  }

  @override
  void didUpdateWidget(RgBookmarkMotion old) {
    super.didUpdateWidget(old);
    if (old.saved != widget.saved && !_still) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale.animate(_pop), child: widget.child);
}
