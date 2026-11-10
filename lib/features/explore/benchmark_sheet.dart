import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';

// 모델 상세 「제작사 측정 점수」의 한 줄을 누르면 여는 평가 항목 풀이(2026-11-10). 용어 시트(C02)와 같은 차례:
// 작은 머리 → 이름(세리프) → 점수 → 선 → 무엇을 재나요 → 점수 읽는 법 → 출처 안내.
Future<void> showBenchmarkSheet(BuildContext context, Benchmark b, {required String model}) {
  final label = RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary);
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4),
        Text('평가 항목', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        HeadingTextScale(child: Semantics(header: true, child: Text(b.name, style: RgText.serifTerm))),
        const SizedBox(height: RgSpace.s6),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$model  ', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
            TextSpan(text: b.score, style: RgText.titleSection.copyWith(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: RgSpace.s18),
          child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
        ),
        Text('무엇을 재나요', style: label),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(b.about ?? '', style: RgText.bodyDefinition),
        if (b.higherBetter case final up?) ...[
          const SizedBox(height: RgSpace.s14),
          Container(
            padding: const EdgeInsets.fromLTRB(RgSpace.s16, RgSpace.s12, RgSpace.s16, RgSpace.s14),
            decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.box)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('점수 읽는 법', style: label),
              const SizedBox(height: RgSpace.s4),
              KeepAllText(
                up ? '높을수록 좋아요.' : '낮을수록 좋아요.',
                style: RgText.bodySmall.copyWith(color: RgColors.textBody),
              ),
            ]),
          ),
        ],
        const SizedBox(height: RgSpace.s14),
        KeepAllText(
          '제작사가 모델 카드에 밝힌 점수예요. 같은 평가를 같은 조건에서 잰 다른 모델과만 견줄 수 있어요.',
          style: RgText.meta.copyWith(color: RgColors.textSecondary),
        ),
      ],
    ),
  );
}
