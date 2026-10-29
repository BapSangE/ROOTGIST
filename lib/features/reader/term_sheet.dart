import '../../analytics/posthog_sink.dart';
import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';

// C02 용어 설명 시트 (HANDOFF 7.5). 한국어는 사전 대응어(G1), 없으면 이 논문 번역문에서 쓴 표기.
Future<void> showTermSheet(BuildContext context, GlossaryTerm t) {
  analytics.termOpened(highlighted: t.highlight, hasTranslation: t.termKo != null);
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4), // 손잡이(누르는 높이 24) 아래
        Text('용어', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        HeadingTextScale(child: Semantics(header: true, child: Text(t.term, style: RgText.serifTerm))),
        // 약어면 정식 명칭 한 줄(예: SLAM → Simultaneous Localization and Mapping)
        if (t.fullForm != null) ...[
          const SizedBox(height: RgSpace.s4),
          Text(t.fullForm!, style: RgText.serifSubtitle.copyWith(color: RgColors.textSecondary)),
        ],
        // 한국어: 승인된 대응어, 없으면 번역문에서 쓴 표기. 원어와 같으면(SLAM → SLAM) 같은 말을 두 번 보이지 않는다
        if (t.koLabel case final ko?) ...[
          const SizedBox(height: RgSpace.s6),
          Text(ko, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
        ],
        Padding(
          padding: EdgeInsets.symmetric(vertical: RgSpace.s18),
          child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
        ),
        // 사전 용어(공식 소식·모델 상세)는 논문 하나의 뜻이 아니라 사전의 뜻
        Text(t.papers == null ? '이 논문에서의 뜻' : '뜻', style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(t.definition, style: RgText.bodyDefinition),
        if (t.papers case final n? when n > 0) ...[
          const SizedBox(height: RgSpace.s14),
          Text('용어 사전 · 논문 $n편에서 쓰임', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        ],
      ],
    ),
  );
}
