import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_pressable.dart';

// RgPrimaryButton: 카드 안 48(15/600), 하단 고정 56(16/600 + 주 버튼 그림자).
class RgPrimaryButton extends StatelessWidget {
  const RgPrimaryButton({super.key, required this.label, required this.onTap, this.floating = false});
  final String label;
  final VoidCallback? onTap;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: onTap,
        child: Container(
          height: floating ? 56 : 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RgColors.actionPrimary,
            borderRadius: BorderRadius.circular(RgRadius.pill),
            boxShadow: floating ? RgShadow.primaryFloating : null,
          ),
          child: Text(
            label,
            style: RgText.bodySmall.copyWith(
              fontSize: floating ? 16 : 15,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: RgColors.onAction,
            ),
          ),
        ),
      ),
    );
  }
}

// 시트 닫기·빈 상태 행동 등 회색 알약 버튼(폭 전체 48, fillNeutral, 15/600).
class RgNeutralButton extends StatelessWidget {
  const RgNeutralButton({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.pill)),
          child: Text(label, style: RgText.bodySmall.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

enum RgCircleVariant { outline, neutral, filled, plain }

// RgCircleButton: 44×44(추천 카드 북마크 48), 아이콘 20. plain은 목록 행 북마크(배경 없음).
class RgCircleButton extends StatelessWidget {
  const RgCircleButton({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    this.icon,
    this.text,
    this.variant = RgCircleVariant.outline,
    this.size = 44,
    this.iconColor,
    this.selected,
  }) : assert((icon == null) != (text == null));

  final String semanticLabel;
  final VoidCallback? onTap;
  final String? icon;
  final String? text; // 리더 글자 크기 버튼 「가」
  final RgCircleVariant variant;
  final double size;
  final Color? iconColor;
  final bool? selected; // 토글(북마크)일 때 상태 낭독

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ?? (variant == RgCircleVariant.filled ? RgColors.onAction : RgColors.textPrimary);
    return Semantics(
      container: true, // 행 탭 영역 안에 있어도 별도 노드로(행 이동과 북마크를 따로 조작)
      button: true,
      toggled: selected,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: onTap, // excludeSemantics가 하위의 탭 동작까지 지우므로 직접 넘긴다(TalkBack 두 번 탭)
      child: RgPressable(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (variant) {
              RgCircleVariant.outline => RgColors.surfaceCard,
              RgCircleVariant.neutral => RgColors.fillNeutral,
              RgCircleVariant.filled => RgColors.actionPrimary,
              RgCircleVariant.plain => null,
            },
            border: variant == RgCircleVariant.outline ? Border.all(color: RgColors.borderDefault) : null,
          ),
          child: icon != null
              ? RgIcon(icon!, size: 20, color: fg)
              : Text(text!, style: RgText.bodySmall.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, color: fg)),
        ),
      ),
    );
  }
}

// 북마크 버튼 공통: 저장 상태에 따라 아이콘·변형·라벨이 바뀐다.
class RgBookmarkButton extends StatelessWidget {
  const RgBookmarkButton({super.key, required this.saved, required this.onTap, this.variant = RgCircleVariant.outline, this.size = 44});
  final bool saved;
  final VoidCallback? onTap;
  final RgCircleVariant variant; // plain(목록 행) 또는 outline(카드·상단 바)
  final double size;

  @override
  Widget build(BuildContext context) {
    final plain = variant == RgCircleVariant.plain;
    return RgCircleButton(
      semanticLabel: saved ? '저장됨, 북마크 해제' : '북마크에 저장',
      selected: saved,
      onTap: onTap,
      icon: saved ? 'bookmark-filled' : 'bookmark',
      size: size,
      variant: plain ? variant : (saved ? RgCircleVariant.filled : variant),
      iconColor: plain ? (saved ? RgColors.textPrimary : RgColors.textTertiary) : null,
    );
  }
}

// RgFilterChip: 시각 36 / 터치 44, 좌우 16, 14pt.
// 알약 칩·세그먼트 글자(bodySmall 14, 줄 높이 1.2)가 더 큰 텍스트에서 잘리지 않도록 높이를 글자에 맞춰 늘린다.
// 배율은 2배에서 멈춘다: S03 상단 바가 52 고정이라 세그먼트가 그 안에 들어가야 한다(iOS QA Q02).
TextScaler rgPillTextScaler(BuildContext context) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
double rgPillHeight(BuildContext context, double base) =>
    math.max(base, rgPillTextScaler(context).scale(14) * 1.2 + RgSpace.s16);

class RgFilterChip extends StatelessWidget {
  const RgFilterChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  // 칩 목록(S01)도 이 높이로 잡는다.
  static double touchHeight(BuildContext context) => math.max(RgSpace.minTouch, rgPillHeight(context, 36));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: RgPressable(
        onTap: onTap,
        child: SizedBox(
          height: touchHeight(context),
          child: Center(
            widthFactor: 1, // 가로로 늘어나지 않고 칩 폭만큼(Wrap 안에서도)
            child: Container(
              height: rgPillHeight(context, 36),
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.s16),
              decoration: BoxDecoration(
                color: selected ? RgColors.actionPrimary : null,
                borderRadius: BorderRadius.circular(RgRadius.pill),
                border: selected ? null : Border.all(color: RgColors.borderDefault),
              ),
              // Container(alignment:)는 가로로 꽉 차므로 Center(widthFactor: 1)로 세로만 가운데.
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  textScaler: rgPillTextScaler(context),
                  maxLines: 1,
                  style: RgText.bodySmall.copyWith(
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? RgColors.onAction : RgColors.textBody,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
