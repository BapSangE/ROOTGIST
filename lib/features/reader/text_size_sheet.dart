import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_segmented.dart';

// 글자 크기 4단계(readerScale)를 시스템 배율에 곱해 아래 글자에 적용한다. S02 AI 카드용(S03 본문은 스크롤 보정 때문에 직접 적용).
class ReaderTextScale extends StatelessWidget {
  const ReaderTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readerScale,
    builder: (context, scale, _) {
      final mq = MediaQuery.of(context);
      return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)), child: child);
    },
  );
}

// 글자 크기 4단계 시트(7.4). 시안이 없어 C02와 같은 시트 틀에 RgSegmented를 쓴다. 고르면 바로 반영·저장.
Future<void> showTextSizeSheet(BuildContext context) {
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 22),
        Semantics(header: true, child: Text('글자 크기', style: RgText.titleSection)),
        const SizedBox(height: RgSpace.s4),
        Text('AI 요약·핵심 내용과 초록 리더 본문에 적용돼요', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s16),
        ValueListenableBuilder(
          valueListenable: readerScale,
          builder: (_, scale, _) => RgSegmented(
            options: readerScales,
            value: scale,
            onChanged: (s) => readerScale.value = s,
          ),
        ),
        const SizedBox(height: RgSpace.s24),
        RgNeutralButton(label: '닫기', onTap: () => Navigator.of(sheet).pop()),
      ],
    ),
  );
}
