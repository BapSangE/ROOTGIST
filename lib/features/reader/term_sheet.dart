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
        Semantics(header: true, child: Text(t.term, style: RgText.serifTerm)),
        if (t.termKo != null) ...[
          const SizedBox(height: RgSpace.s6),
          Text(t.termKo!, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(vertical: RgSpace.s18),
          child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
        ),
        Text('이 논문에서의 뜻', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        Text(keepAll(t.definition), style: RgText.bodyDefinition),
        const SizedBox(height: RgSpace.s24),
        RgNeutralButton(label: '닫기', onTap: () => Navigator.of(sheet).pop()),
      ],
    ),
  );
}
