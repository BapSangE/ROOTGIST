import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/guide.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';

// 기능에 처음 들어갈 때 한 번만 뜨는 도움말(시안 design-preview/src/onboarding_guide.html 2장).
// 화면을 어둡게 덮고 버튼 하나만 밝혀 짧게 알려 준다. 밝힌 자리 테두리는 숨쉬듯 커졌다 작아지고(1.6초),
// 다음 단계로 가면 밝힌 자리가 미끄러져 옮겨 간다(240ms). 닫으면 막이 걷히며(180ms) 가벼운 진동.
// 「동작 줄이기」면 숨쉬기·미끄러짐 없이 바로. 띄우는 순간 본 것으로 적어 앱을 꺼도 다시 뜨지 않는다.
class CoachStep {
  const CoachStep({required this.target, required this.title, required this.body});
  final GlobalKey target;
  final String title, body;
}

Future<void> showCoachMarks(BuildContext context, String id, List<CoachStep> steps) async {
  if (tipsSeen.value.contains(id)) return;
  final shown = [for (final s in steps) if (_rectOf(s.target) != null) s];
  if (shown.isEmpty) return;
  tipsSeen.value = {...tipsSeen.value, id};
  final still = MediaQuery.disableAnimationsOf(context);
  await Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: false,
    transitionDuration: still ? Duration.zero : const Duration(milliseconds: 200),
    reverseTransitionDuration: still ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder: (_, _, _) => Material(type: MaterialType.transparency, child: _CoachOverlay(steps: shown)), // 글자 기본 모양(노란 밑줄 방지)
    transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: CurvedAnimation(parent: animation, curve: RgMotion.curve), child: child),
  ));
}

Rect? _rectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _CoachOverlay extends StatefulWidget {
  const _CoachOverlay({required this.steps});
  final List<CoachStep> steps;

  @override
  State<_CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<_CoachOverlay> with SingleTickerProviderStateMixin {
  var _i = 0;
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  bool get _last => _i == widget.steps.length - 1;

  void _next() {
    if (_last) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop();
    } else {
      HapticFeedback.selectionClick();
      setState(() => _i++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_i];
    final size = MediaQuery.sizeOf(context);
    final target = (_rectOf(step.target) ?? Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0)).inflate(6);
    final still = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(end: target),
      duration: still ? Duration.zero : const Duration(milliseconds: 240),
      curve: RgMotion.curve,
      builder: (context, rect, _) {
        final hole = rect ?? target;
        // 아래 공간이 넉넉하면 아래에, 아니면 위에 말풍선
        final below = size.height - hole.bottom > hole.top;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _next, // 어두운 곳을 눌러도 다음으로
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: _ScrimPainter(hole: hole, pulse: still ? 0 : math.sin(_pulse.value * math.pi), color: RgColors.overlayDim),
                ),
              ),
            ),
            Positioned(
              left: RgSpace.gutterText,
              right: RgSpace.gutterText,
              top: below ? hole.bottom + 16 : null,
              bottom: below ? null : size.height - hole.top + 16,
              child: _Bubble(
                step: step,
                index: _i,
                count: widget.steps.length,
                last: _last,
                arrowX: hole.center.dx - RgSpace.gutterText,
                below: below,
                onNext: _next,
              ),
            ),
          ]),
        );
      },
    );
  }
}

// 어두운 막에 밝힌 자리만 구멍을 뚫고, 그 둘레에 흰 테두리(숨쉬기: 4pt ↔ 9pt, 흐려지며).
class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.pulse, required this.color});
  final Rect hole;
  final double pulse; // 0~1
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(hole, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(r)),
      Paint()..color = color,
    );
    final width = 4 + 5 * pulse;
    canvas.drawRRect(
      r.inflate(width / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = Color.fromRGBO(255, 255, 255, 0.95 - 0.6 * pulse),
    );
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.pulse != pulse || old.color != color;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.step,
    required this.index,
    required this.count,
    required this.last,
    required this.arrowX,
    required this.below,
    required this.onNext,
  });
  final CoachStep step;
  final int index, count;
  final bool last, below;
  final double arrowX;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.fromLTRB(RgSpace.s18, RgSpace.s18, RgSpace.s14, RgSpace.s14),
      decoration: BoxDecoration(color: RgColors.surfaceCard, borderRadius: BorderRadius.circular(20)),
      child: Semantics(
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Semantics(header: true, child: KeepAllText(step.title, style: RgText.titleList.copyWith(fontSize: 17, fontWeight: FontWeight.w700))),
          const SizedBox(height: RgSpace.s4),
          KeepAllText(step.body, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
          const SizedBox(height: RgSpace.s14),
          Row(children: [
            Expanded(child: Text('${index + 1} / $count', style: RgText.caption.copyWith(fontWeight: FontWeight.w500, color: RgColors.textSecondary))),
            SizedBox(width: 108, child: RgPrimaryButton(label: last ? '알겠어요' : '다음', onTap: onNext)),
          ]),
        ]),
      ),
    );
    // 말풍선 꼬리: 밝힌 자리 가운데를 가리킨다(카드 모서리 안쪽으로만)
    final tail = Transform.rotate(
      angle: math.pi / 4,
      child: Container(width: 16, height: 16, decoration: BoxDecoration(color: RgColors.surfaceCard, borderRadius: BorderRadius.circular(3))),
    );
    return LayoutBuilder(builder: (context, c) {
      final x = arrowX.clamp(24.0, c.maxWidth - 24.0) - 8;
      return Stack(clipBehavior: Clip.none, children: [
        card,
        Positioned(left: x, top: below ? -7 : null, bottom: below ? null : -7, child: tail),
      ]);
    });
  }
}
