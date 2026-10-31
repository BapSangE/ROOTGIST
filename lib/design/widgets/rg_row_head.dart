import 'package:flutter/material.dart';

import '../tokens.dart';
import '../typography.dart';
import 'rg_new_dot.dart';

// 칩: 높이 24 알약, 12.5/600. 출처는 회사 대표 색(RgBrand), 주제·종류는 중립 fill. onInk는 다크 카드 위(흰 알약 + 잉크 글자).
class RgChip extends StatelessWidget {
  const RgChip(this.label, {super.key, this.source, this.onInk = false});
  final String label;
  final String? source; // 공식 소식 출처 id 또는 이름. 대표 색이 있으면 그 색
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    // 다크 카드 위에서 검정 대표 색(OpenAI)은 카드에 묻혀 흰 칩으로
    final brand = switch (brandOf(source)) {
      (final bg, _) when onInk && bg.computeLuminance() < 0.05 => null,
      final b => b,
    };
    final (bg, fg) = brand ??
        (onInk ? (RgColors.chipOnInk, RgColors.ink) : (RgColors.fillNeutral, RgColors.textBody));
    return Container(
      constraints: const BoxConstraints(minHeight: 24), // 고정 높이면 큰 글자에서 잘린다
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(RgRadius.pill)),
      child: Text(label, style: RgText.caption.copyWith(fontSize: 12.5, height: 1.25, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

// 출처 → (바탕, 글자). 같은 회사는 같은 색(SDK 릴리스도 그 회사 색). id(official_news.source)와 보관함에 저장된 이름 둘 다 받는다.
// 수집기에 출처를 더하면 여기에도 더한다(worker/official_news.py RSS_SOURCES·RELEASE_SOURCES).
// 로고·글꼴은 따라 하지 않고 이름 글자만(docs/RIGHTS.md 4장 「출처 배지 색」).
(Color, Color)? brandOf(String? source) => switch (source) {
  'anthropic' || 'claude_code' || 'claude_api' || 'anthropic_sdk' ||
  'Anthropic' || 'Claude Code' || 'Claude API' || 'Anthropic Python SDK' => (RgBrand.anthropic, RgColors.onInk),
  'openai' || 'openai_community' || 'openai_sdk' || 'OpenAI' || 'OpenAI 커뮤니티' || 'OpenAI Python SDK' => (RgBrand.openai, RgColors.onInk),
  // 모델 칩은 발표한 회사 이름(makerName). 대표 색이 있는 회사만 그 색, 나머지는 중립
  'deepmind' || 'google_research' || 'google' || 'Google DeepMind' || 'Google Research' || 'Google' => (RgBrand.google, RgColors.onInk),
  'huggingface' || 'Hugging Face' => (RgBrand.huggingface, RgColors.ink),
  'nvidia' || 'nvidia_dev' || 'NVIDIA' || 'NVIDIA 개발자' => (RgBrand.nvidia, RgColors.ink),
  'meta' || 'Meta' => (RgBrand.meta, RgColors.onInk),
  'xai' || 'xai_sdk' || 'xAI' || 'xAI Python SDK' => (RgBrand.xai, RgColors.onInk),
  _ => null,
};

// 목록 행의 머리 줄: [칩] 보조 글자 [새 글]. 앱의 모든 목록 행이 이 모양을 쓴다(논문·공식 소식·모델·보관함).
// 줄이 넘치면 칩 다음에서 줄을 바꾼다. 「새 글」은 읽으면 작아지며 사라진다(RgNewLabel).
class RgRowHead extends StatelessWidget {
  const RgRowHead({super.key, this.chip, this.meta, this.isNew = false, this.newLabel = '새 글', this.onInk = false});
  final Widget? chip;
  final String? meta;
  final bool isNew;
  final String newLabel;
  final bool onInk;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ?chip,
      if (meta != null && meta!.isNotEmpty)
        KeepAllText(meta!, style: RgText.meta.copyWith(fontSize: 13.5, height: 19 / 13.5, color: onInk ? RgColors.onInkSecondary : RgColors.textSecondary)),
      RgNewLabel(visible: isNew, label: newLabel),
    ],
  );
}

// 칩으로 거른 목록이 바뀔 때: 새 목록이 위로 8pt 떠오르며 나타나고(160ms 페이드), 높이는 부드럽게 맞춘다.
// switchKey가 바뀔 때만 움직인다(같은 거르기에서 다시 그리기는 그대로). 「동작 줄이기」면 바로 바뀐다.
class RgFilterSwitch extends StatelessWidget {
  const RgFilterSwitch({super.key, required this.switchKey, required this.child});
  final Object? switchKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, const Duration(milliseconds: 160));
    return AnimatedSize(
      duration: RgMotion.of(context, RgMotion.base),
      curve: RgMotion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        reverseDuration: const Duration(milliseconds: 1), // 이전 목록은 바로 비켜 겹쳐 보이지 않게
        switchInCurve: RgMotion.curve,
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.02), end: Offset.zero).animate(a), child: child),
        ),
        child: KeyedSubtree(key: ValueKey(switchKey), child: child),
      ),
    );
  }
}
