import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_buttons.dart';
import 'rg_pressable.dart';

// RgSegmented: 높이 40(더 큰 텍스트에서는 rgPillHeight만큼), 내부 여백 4, 간격 2, n등분. 흰 알약은 AnimatedAlign 200ms easeOut.
class RgSegmented<T> extends StatelessWidget {
  const RgSegmented({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  static const _gap = RgSpace.s2;

  @override
  Widget build(BuildContext context) {
    final n = options.length;
    final index = options.indexWhere((o) => o.$1 == value);
    final scaler = rgPillTextScaler(context);
    return Container(
      height: rgPillHeight(context, 40),
      padding: const EdgeInsets.all(RgSpace.s4),
      decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.pill)),
      child: LayoutBuilder(builder: (context, c) {
        final segW = (c.maxWidth - _gap * (n - 1)) / n;
        return Stack(
          children: [
            // 정렬 x = -1 + 2i/(n-1) 이면 왼쪽 = i × (segW + gap) 로 정확히 맞는다.
            AnimatedAlign(
              alignment: Alignment(n == 1 ? 0 : -1 + 2 * index / (n - 1), 0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              child: Container(
                width: segW,
                decoration: BoxDecoration(
                  color: RgColors.surfaceCard,
                  borderRadius: BorderRadius.circular(RgRadius.pill),
                  boxShadow: RgShadow.segment,
                ),
              ),
            ),
            Row(
              spacing: _gap,
              children: [
                for (final (v, label) in options)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: v == value,
                      child: RgPressable(
                        onTap: () => onChanged(v),
                        // 칸이 좁으면(4등분 「아주 크게」) 줄바꿈 대신 칸 안으로 줄인다.
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              textScaler: scaler,
                              maxLines: 1,
                              style: RgText.bodySmall.copyWith(
                                height: 1.2,
                                fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                                color: v == value ? RgColors.textPrimary : RgColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
