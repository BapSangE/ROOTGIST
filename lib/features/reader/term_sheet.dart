import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';

// C02 용어 설명 시트 (HANDOFF 7.5). 한국어 대응어는 용어 사전에 연결된 경우에만(G1).
Future<void> showTermSheet(BuildContext context, GlossaryTerm t) {
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        Text('용어', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        HeadingTextScale(child: Semantics(header: true, child: Text(t.term, style: RgText.serifTerm))),
        // 약어면 정식 명칭 한 줄(예: SLAM → Simultaneous Localization and Mapping)
        if (t.fullForm != null) ...[
          const SizedBox(height: RgSpace.s4),
          Text(t.fullForm!, style: RgText.serifSubtitle.copyWith(color: RgColors.textSecondary)),
        ],
        // 대응어가 원어와 같으면(SLAM → SLAM) 같은 말을 두 번 보이지 않는다
        if (t.termKo != null && t.termKo!.toLowerCase() != t.term.toLowerCase()) ...[
          const SizedBox(height: RgSpace.s6),
          Text(t.termKo!, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: RgSpace.s18),
          child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
        ),
        Text('이 논문에서의 뜻', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        KeepAllText(t.definition, style: RgText.bodyDefinition),
        const SizedBox(height: RgSpace.s24),
        RgNeutralButton(label: '닫기', onTap: () => Navigator.of(sheet).pop()),
      ],
    ),
  );
}
