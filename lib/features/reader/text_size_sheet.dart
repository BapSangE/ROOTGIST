import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';

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

// 글자 크기 고르기: 4단계 슬라이더(위에 단계별 「가」, 아래에 이름) + 고른 크기로 바로 바뀌는 예시(피드백: 실제 크기를 보여 줄 것).
// 시트(S02·S03 「가」)와 설정 › 읽기 설정이 같이 쓴다. 고르면 바로 반영·저장.
class TextSizePicker extends StatelessWidget {
  const TextSizePicker({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readerScale,
    builder: (_, scale, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _StepSlider(value: scale, onChanged: (s) => readerScale.value = s),
      const SizedBox(height: RgSpace.s20),
      // 예시: 리더 「함께」와 같은 모양(번역 + 세로선 원문)
      Semantics(
        label: '미리 보기',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s18, vertical: RgSpace.s16),
          // 흰 바탕에서는 시트·카드와 같은 흰색이라 가는 선으로 상자를 나눈다
          decoration: BoxDecoration(
            color: RgColors.bgReading,
            borderRadius: BorderRadius.circular(RgRadius.box),
            border: Border.all(color: RgColors.borderDefault),
          ),
          child: ReaderTextScale(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              KeepAllText('AI 요약과 초록 번역이 이 크기로 보여요.', style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
              Container(
                padding: const EdgeInsets.only(left: RgSpace.s12),
                decoration: BoxDecoration(border: Border(left: BorderSide(color: RgColors.borderDefault, width: 2))),
                child: Text('The original abstract looks like this.', style: RgText.serifTogether.copyWith(color: RgColors.textSecondary)),
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

// 4단계 슬라이더(레퍼런스 017): 위에 단계별 크기의 「가」, 가운데 트랙과 흰 손잡이, 아래에 단계 이름.
// 누르거나 끌면 가장 가까운 단계로. 화면 읽기에서는 조절 가능한 값(올리기·내리기)으로 읽힌다.
class _StepSlider extends StatelessWidget {
  const _StepSlider({required this.value, required this.onChanged});
  final double value;
  final ValueChanged<double> onChanged;

  static const _glyph = [13.0, 16.0, 19.0, 22.0]; // 단계별 「가」 크기

  @override
  Widget build(BuildContext context) {
    final n = readerScales.length;
    final i = readerScales.indexWhere((e) => e.$1 == value).clamp(0, n - 1);
    // 단계가 바뀔 때마다 선택 틱(끌어서 여러 단계를 지나도 단계마다 한 번)
    void pick(int k) {
      final v = readerScales[k.clamp(0, n - 1)].$1;
      if (v != value) HapticFeedback.selectionClick();
      onChanged(v);
    }
    return Semantics(
      slider: true,
      label: '글자 크기',
      value: readerScales[i].$2,
      increasedValue: i < n - 1 ? readerScales[i + 1].$2 : null,
      decreasedValue: i > 0 ? readerScales[i - 1].$2 : null,
      onIncrease: i < n - 1 ? () => pick(i + 1) : null,
      onDecrease: i > 0 ? () => pick(i - 1) : null,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, c) {
        const inset = 12.0; // 손잡이 반지름: 양 끝 단계가 트랙 끝에 오게
        final w = c.maxWidth - inset * 2;
        int at(double dx) => (((dx - inset) / w) * (n - 1)).round();
        // 칸을 n등분하고 칸 안 정렬을 -1→1로 옮기면 양 끝은 트랙 끝, 가운데 단계는 손잡이 자리 근처에 온다
        Widget row(List<Widget> cells) => Row(children: [for (final x in cells) Expanded(child: x)]);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(at(d.localPosition.dx)),
          onHorizontalDragUpdate: (d) => pick(at(d.localPosition.dx)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            row([
              for (var k = 0; k < n; k++)
                Align(
                  alignment: Alignment(-1 + 2 * k / (n - 1), 1),
                  child: Text(
                    '가',
                    textScaler: TextScaler.noScaling,
                    style: RgText.bodySmall.copyWith(
                      fontSize: _glyph[k],
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: k == i ? RgColors.textPrimary : RgColors.textTertiary,
                    ),
                  ),
                ),
            ]),
            SizedBox(
              height: 40,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Positioned(
                  left: inset,
                  right: inset,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Positioned(
                  left: inset,
                  width: w * i / (n - 1),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(color: RgColors.actionPrimary, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  left: inset + w * i / (n - 1) - 12,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(color: RgColors.surfaceRaised, shape: BoxShape.circle, boxShadow: RgShadow.thumb),
                  ),
                ),
              ]),
            ),
            row([
              for (var k = 0; k < n; k++)
                Align(
                  alignment: Alignment(-1 + 2 * k / (n - 1), 0),
                  child: Text(
                    readerScales[k].$2,
                    style: RgText.caption.copyWith(
                      fontSize: 12.5,
                      fontWeight: k == i ? FontWeight.w600 : FontWeight.w400,
                      color: k == i ? RgColors.textPrimary : RgColors.textSecondary,
                    ),
                  ),
                ),
            ]),
          ]),
        );
      }),
    );
  }
}
