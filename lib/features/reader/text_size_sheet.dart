import 'package:flutter/material.dart';

import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
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

// 글자 크기 고르기: 4단계 세그먼트 + 고른 크기로 바로 바뀌는 예시(피드백: 실제 크기를 보여 줄 것).
// 시트(S02·S03 「가」)와 설정 › 읽기 설정이 같이 쓴다. 고르면 바로 반영·저장.
class TextSizePicker extends StatelessWidget {
  const TextSizePicker({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readerScale,
    builder: (_, scale, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RgSegmented(options: readerScales, value: scale, onChanged: (s) => readerScale.value = s),
      const SizedBox(height: RgSpace.s12),
      // 예시: 리더 「함께」와 같은 모양(번역 + 세로선 원문)
      Semantics(
        label: '미리 보기',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s18, vertical: RgSpace.s16),
          decoration: BoxDecoration(color: RgColors.bgReading, borderRadius: BorderRadius.circular(RgRadius.box)),
          child: ReaderTextScale(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              KeepAllText('AI 요약과 초록 번역이 이 크기로 보여요.', style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
              Container(
                padding: const EdgeInsets.only(left: RgSpace.s12),
                decoration: const BoxDecoration(border: Border(left: BorderSide(color: RgColors.borderDefault, width: 2))),
                child: Text('The original abstract looks like this.', style: RgText.serifTogether.copyWith(color: RgColors.textBody)),
              ),
            ]),
          ),
        ),
      ),
    ]),
  );
}

// 글자 크기 시트(7.4). C02와 같은 시트 틀.
Future<void> showTextSizeSheet(BuildContext context) {
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4), // 손잡이(누르는 높이 24) 아래
        Semantics(header: true, child: Text('글자 크기', style: RgText.titleSection)),
        const SizedBox(height: RgSpace.s4),
        Text('AI 요약·핵심 내용과 초록 리더 본문에 적용돼요', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s16),
        const TextSizePicker(),
      ],
    ),
  );
}
