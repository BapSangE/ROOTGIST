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
    this.dividerInset = 0,
  });
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final EdgeInsets padding; // S04 날짜 행은 16/16/16/20
  final CrossAxisAlignment crossAxisAlignment; // S01·S05 북마크는 위 정렬, S04 날짜 행은 center
  final double dividerInset; // 바탕 위 목록(홈 논문)은 20: 구분선이 글자 폭에만 걸친다

  @override
  Widget build(BuildContext context) {
    final row = Semantics(
      button: onTap != null,
      child: RgPressable(
        row: true, // 행 눌림: 98% + 4% 어두워짐
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
        Divider(height: 1, thickness: 1, color: RgColors.dividerCard, indent: dividerInset, endIndent: dividerInset),
      ],
    );
  }
}

// 다크 카드(레퍼런스 007·016): 화면에서 가장 중요한 것 하나만 차콜 면으로. 오늘의 주요 논문, 트렌딩 1위.
class RgDarkCard extends StatelessWidget {
  const RgDarkCard({super.key, required this.child, this.padding = const EdgeInsets.all(RgSpace.s22)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(color: RgColors.surfaceInk, borderRadius: BorderRadius.circular(RgRadius.cardDark)),
      child: child,
    ),
  );
}

// 태그: 높이 24, fill 알약, 아이콘 + 글자(주제·라이선스·반응·버전·「지연」). onInk면 다크 카드 위(흰 12%).
class RgTag extends StatelessWidget {
  const RgTag({super.key, required this.label, this.icon, this.onInk = false, this.inverted = false, this.height = 24});
  final String label;
  final String? icon;
  final bool onInk;
  final bool inverted; // 검정 면 흰 글자(상세 화면 머리의 주제)
  final double height;

  @override
  Widget build(BuildContext context) {
    final fg = onInk || inverted ? RgColors.onAction : RgColors.textBody;
    return Container(
      constraints: BoxConstraints(minHeight: height), // 고정 높이면 큰 글자에서 잘린다
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s10, vertical: RgSpace.s4),
      decoration: BoxDecoration(
        color: inverted ? RgColors.actionPrimary : (onInk ? RgColors.tagOnInk : RgColors.fillNeutral),
        borderRadius: BorderRadius.circular(RgRadius.pill),
      ),
      // 아이콘도 글자 안에 넣는다: Row + Flexible이면 목록 행 오른쪽처럼 폭 제한이 없는 자리에서 배치가 깨진다
      child: Text.rich(
        TextSpan(children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(padding: const EdgeInsets.only(right: 5), child: RgIcon(icon!, size: 14, color: fg)),
            ),
          TextSpan(text: label),
        ]),
        style: RgText.caption.copyWith(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w500, color: fg),
      ),
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

// 출처 머리글자 배지처럼 쓰는 34×34 네모(모서리 10, fill).
class RgSquareBadge extends StatelessWidget {
  const RgSquareBadge({super.key, required this.text, this.size = 34, this.color, this.textColor});
  final String text;
  final double size;
  final Color? color; // 없으면 fill(출처 대표 색이 없는 곳)
  final Color? textColor;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color ?? RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.badge)),
      child: Text(
        text,
        textScaler: TextScaler.noScaling, // 상자 크기가 고정이라 글자도 고정
        style: RgText.caption.copyWith(fontSize: size < 32 ? 11 : 12, fontWeight: FontWeight.w700, color: textColor ?? RgColors.textBody),
      ),
    ),
  );
}
