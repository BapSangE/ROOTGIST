import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_pressable.dart';

// RgPrimaryButton: 카드 안 48(15/600), 하단 버튼 줄 50(16/600). 그림자 없음. icon은 글자 앞(「번역과 함께 초록 읽기」).
class RgPrimaryButton extends StatelessWidget {
  const RgPrimaryButton({super.key, required this.label, required this.onTap, this.floating = false, this.icon});
  final String label;
  final VoidCallback? onTap;
  final bool floating;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: onTap,
        child: Container(
          // 고정 높이면 더 큰 텍스트에서 글자가 잘린다. 기본 크기에서는 48/56 그대로.
          constraints: BoxConstraints(minHeight: floating ? 50 : 48),
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s12),
          decoration: BoxDecoration(
            color: RgColors.actionPrimary,
            borderRadius: BorderRadius.circular(RgRadius.pill),
          ),
          // 가로는 꽉, 세로는 글자만큼(heightFactor 1). alignment를 쓰면 높이 제한이 없는 하단 버튼 줄
          // (Scaffold.bottomNavigationBar)에서 화면 높이를 다 차지했다.
          child: Center(
            heightFactor: 1,
            child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s8, children: [
            if (icon != null) RgIcon(icon!, size: 20, color: RgColors.onAction),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: RgText.bodySmall.copyWith(
                  fontSize: floating ? 16 : 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: RgColors.onAction,
                ),
              ),
            ),
          ]),
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
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s12),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.pill)),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: RgText.bodySmall.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

enum RgCircleVariant { outline, neutral, filled, plain, glass }

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
    this.visualSize,
  }) : assert((icon == null) != (text == null));

  final String semanticLabel;
  final VoidCallback? onTap;
  final String? icon;
  final String? text; // 리더 글자 크기 버튼 「가」
  final RgCircleVariant variant;
  final double size;
  final Color? iconColor;
  final bool? selected; // 토글(북마크)일 때 상태 낭독
  final double? visualSize; // 보이는 원 크기(목록 행은 36). 누르는 영역은 size(44) 그대로

  @override
  Widget build(BuildContext context) {
    final fg = iconColor ??
        (variant == RgCircleVariant.filled || variant == RgCircleVariant.glass ? RgColors.onAction : RgColors.textPrimary);
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
          child: Container(
            width: visualSize ?? size,
            height: visualSize ?? size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: switch (variant) {
                RgCircleVariant.outline => RgColors.surfaceCard,
                RgCircleVariant.neutral => RgColors.fillNeutral,
                RgCircleVariant.filled => RgColors.actionPrimary,
                RgCircleVariant.plain => null,
                RgCircleVariant.glass => RgColors.glassOnInk,
              },
              border: variant == RgCircleVariant.outline ? Border.all(color: RgColors.borderDefault) : null,
            ),
            child: icon != null
                ? RgIcon(icon!, size: 20, color: fg)
                : Text(
                    text!,
                    style: RgText.bodySmall.copyWith(fontSize: 15, height: 1.2, fontWeight: FontWeight.w600, color: fg),
                  ),
          ),
        ),
      ),
    );
  }
}

// 뒤로 가기: 원 없이 화살표만(피드백). 누르는 영역 44는 그대로 두고, 화살표가 아래 제목(좌우 20)과 줄 맞게 왼쪽으로 당긴다.
class RgBackButton extends StatelessWidget {
  const RgBackButton({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Transform.translate(
    // 상단 바 좌우 16 − 16 → 44 영역 안 화살표 획이 제목 글자(좌우 20)와 같은 세로줄에 온다
    offset: const Offset(-16, 0),
    child: RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', variant: RgCircleVariant.plain, onTap: onTap),
  );
}

// 북마크 버튼 공통: 저장 상태에 따라 아이콘·변형·라벨이 바뀐다.
class RgBookmarkButton extends StatelessWidget {
  const RgBookmarkButton({
    super.key,
    required this.saved,
    required this.onTap,
    this.variant = RgCircleVariant.outline,
    this.size = 44,
    this.visualSize,
  });
  final bool saved;
  final VoidCallback? onTap;
  final RgCircleVariant variant; // neutral(목록 행·카드, 보이는 원 36) 또는 outline(상단 바). plain은 예전 목록 행
  final double size;
  final double? visualSize;

  @override
  Widget build(BuildContext context) {
    final plain = variant == RgCircleVariant.plain;
    final glass = variant == RgCircleVariant.glass; // 다크 카드 위: 저장되면 채운 아이콘만 바뀐다
    return RgCircleButton(
      semanticLabel: saved ? '저장됨, 북마크 해제' : '북마크에 저장',
      selected: saved,
      onTap: onTap,
      icon: saved ? 'bookmark-filled' : 'bookmark',
      size: size,
      visualSize: visualSize,
      variant: plain || glass ? variant : (saved ? RgCircleVariant.filled : variant),
      iconColor: plain ? (saved ? RgColors.textPrimary : RgColors.textTertiary) : null,
    );
  }
}

// RgFilterChip: 시각 36 / 터치 44, 좌우 16, 14pt.
// 알약 칩·세그먼트 글자(bodySmall 14, 줄 높이 1.2)가 더 큰 텍스트에서 잘리지 않도록 높이를 글자에 맞춰 늘린다.
// 배율은 2배에서 멈춘다: 세그먼트 칸 폭이 좁아(4등분) 그 이상은 칸 안에 들어가지 않는다(iOS QA Q02).
TextScaler rgPillTextScaler(BuildContext context) => MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 2);
double rgPillHeight(BuildContext context, double base) => math.max(base, rgPillTextScaler(context).scale(14) * 1.2 + RgSpace.s16);

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
