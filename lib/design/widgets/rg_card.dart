import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_pressable.dart';

// RgCard: 폭 = 화면 − 32. 바깥 좌우 16 여백까지 포함한다.
class RgCard extends StatelessWidget {
  const RgCard({super.key, required this.child, this.padding = EdgeInsets.zero});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RgColors.surfaceCard,
          borderRadius: BorderRadius.circular(RgRadius.card),
          boxShadow: RgShadow.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(RgRadius.card),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// RgListRow: 최소 높이 56, 여백 위18/오른8/아래18/왼20, 텍스트 열 + 오른쪽 44 버튼, 마지막 행 제외 구분선.
class RgListRow extends StatelessWidget {
  const RgListRow({
    super.key,
    required this.child,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 8, 18),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final EdgeInsets padding; // S04 날짜 행은 16/16/16/20
  final CrossAxisAlignment crossAxisAlignment; // S01·S05 북마크는 위 정렬, S04 날짜 행은 center

  @override
  Widget build(BuildContext context) {
    final row = Semantics(
      button: onTap != null,
      child: RgPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Expanded(child: child),
                if (trailing != null) ...[const SizedBox(width: RgSpace.s8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        row,
        const Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
      ],
    );
  }
}

// RgBadge: 높이 24, 여백 4/10, 12/16 500 textBody.
class RgBadge extends StatelessWidget {
  const RgBadge({super.key, required this.label, this.onCard = true});
  final String label;
  final bool onCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 24), // 고정 높이면 글자 200%에서 위아래가 잘린다(에뮬레이터 QA)
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s10, vertical: RgSpace.s4),
      decoration: BoxDecoration(
        color: onCard ? RgColors.fillBadgeOnCard : RgColors.fillBadgeOnBg,
        borderRadius: BorderRadius.circular(RgRadius.pill),
      ),
      child: Text(
        label,
        style: RgText.caption.copyWith(fontWeight: FontWeight.w500, color: RgColors.textBody),
      ),
    );
  }
}
