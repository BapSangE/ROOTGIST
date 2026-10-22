import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
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
        const SizedBox(height: 22),
        Text('핵심 내용 $pointIndex의 근거', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s4),
        Semantics(
          header: true,
          child: Text('초록 ${sentenceNumber(sentenceId)}번째 문장', style: RgText.titleSection),
        ),
        if (s != null) ...[
          const SizedBox(height: RgSpace.s16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.s18, vertical: RgSpace.s16),
            decoration: BoxDecoration(color: RgColors.bgReading, borderRadius: BorderRadius.circular(RgRadius.box)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(latexDisplay(s.text), style: RgText.serifTogether.copyWith(fontSize: 16, height: 26 / 16)),
                if (s.translation != null) ...[
                  const SizedBox(height: RgSpace.s10),
                  Text(keepAll(s.translation!), style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: RgSpace.s12),
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            link: true,
            child: RgPressable(
              onTap: () {
                Navigator.of(sheet).pop();
                context.push('/paper/${paper.id}/reader?s=$sentenceId');
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s2, children: [
                  Text('초록 전체에서 보기', style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
                  const RgIcon('chevron-right', size: 14, color: RgColors.textBody),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: RgSpace.s8),
        RgNeutralButton(label: '닫기', onTap: () => Navigator.of(sheet).pop()),
      ],
    ),
  );
}
