import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_pressable.dart';

// C01 원문 근거 시트 (HANDOFF 7.3). 문장 ID는 노출하지 않는다.
Future<void> showEvidenceSheet(
  BuildContext context, {
  required PaperDetail paper,
  required int pointIndex,
  required String sentenceId,
}) {
  final s = paper.sentence(sentenceId);
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4), // 손잡이(누르는 높이 24) 아래
        Text('핵심 내용 $pointIndex의 근거', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s4),
        Semantics(
          header: true,
          child: Text('초록 ${sentenceNumber(sentenceId)}번째 문장', style: RgText.titleReader),
        ),
        if (s != null) ...[
          const SizedBox(height: RgSpace.s16),
          // 인용 상자(레퍼런스 011): 읽기 바탕 + 왼쪽 3pt 검정 막대.
          // 한쪽만 있는 테두리에는 모서리를 줄 수 없다(Flutter 제약). 막대가 곧은 쪽이라 모서리 없이.
          Container(
            padding: const EdgeInsets.fromLTRB(RgSpace.s18, RgSpace.s16, RgSpace.s18, RgSpace.s18),
            decoration: BoxDecoration(
              color: RgColors.bgReading,
              border: Border(left: BorderSide(color: RgColors.textPrimary, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(latexDisplay(s.text), style: RgText.serifTogether.copyWith(fontSize: 17, height: 27 / 17, color: RgColors.textPrimary)),
                if (s.translation != null) ...[
                  const SizedBox(height: RgSpace.s12),
                  KeepAllText(s.translation!, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: RgSpace.s20),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            link: true,
            child: RgPressable(
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/paper/${paper.id}/reader?s=$sentenceId');
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.s18, vertical: RgSpace.s10),
                decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.pill)),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s6, children: [
                  const RgIcon('book', size: 16, color: RgColors.textPrimary),
                  Flexible(child: Text('초록 전체에서 보기', style: RgText.bodySmall.copyWith(height: 1.2, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
