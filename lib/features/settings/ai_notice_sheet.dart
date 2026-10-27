import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';

// C03 AI 생성 안내 (HANDOFF 7.8). 논문 본문 전체를 읽었다는 표현은 쓰지 않는다.
const aiNoticeParagraphs = [
  '요약, 핵심 내용, 번역, 용어 설명은 논문 초록만을 바탕으로 AI가 만들었어요.',
  '핵심 내용은 초록 안에서 근거 문장을 찾을 수 있는 것만 보여 드려요.',
  'AI가 만든 번역과 요약에는 오류가 있을 수 있어요. 중요한 내용은 원문에서 확인해 주세요.',
];

Future<void> showAiNoticeSheet(BuildContext context) {
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4), // 손잡이(누르는 높이 24) 아래
        Semantics(header: true, child: Text('AI 생성 안내', style: RgText.titleSection)),
        const SizedBox(height: RgSpace.s12),
        Column(
          spacing: RgSpace.s12,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final p in aiNoticeParagraphs) KeepAllText(p, perSentence: true, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
          ],
        ),
      ],
    ),
  );
}
