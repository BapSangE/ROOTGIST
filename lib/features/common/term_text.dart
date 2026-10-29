import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_pressable.dart';
import '../reader/term_sheet.dart';

// 용어 하이라이트 공용 부품. 리더 문장, 논문 상세 카드(AI 요약·핵심 내용), 공식 소식·모델 상세가 같이 쓴다.
typedef Highlight = (int start, GlossaryTerm term, String label);

final _ascii = RegExp(r'[A-Za-z0-9]');
final _hangul = RegExp(r'[가-힣]');

// text에서 label이 낱말로 나오는 첫 자리(없으면 -1).
// 영문 표기는 앞뒤가 영문·숫자가 아닐 때만(RAG ≠ RAGAS), 한글 표기는 앞이 한글이 아닐 때만(뒤는 조사가 붙는다).
int findTerm(String text, String label) {
  if (label.isEmpty) return -1;
  final asciiStart = _ascii.hasMatch(label[0]), asciiEnd = _ascii.hasMatch(label[label.length - 1]);
  final hangulStart = _hangul.hasMatch(label[0]);
  for (var at = text.indexOf(label); at >= 0; at = text.indexOf(label, at + 1)) {
    final before = at > 0 ? text[at - 1] : '';
    final after = at + label.length < text.length ? text[at + label.length] : '';
    if (asciiStart && before.isNotEmpty && _ascii.hasMatch(before)) continue;
    if (asciiEnd && after.isNotEmpty && _ascii.hasMatch(after)) continue;
    if (hangulStart && before.isNotEmpty && _hangul.hasMatch(before)) continue;
    return at;
  }
  return -1;
}

// 한국어 글 하나에서 용어마다 처음 1번(겹치는 것은 먼저 찾은 쪽). used에 든 용어는 건너뛰고, 찾은 용어를 used에 넣는다
// (카드 안 여러 문단에서 용어당 1번만 강조하려고).
List<Highlight> findHighlights(String text, Iterable<GlossaryTerm> terms, {Set<GlossaryTerm>? used}) {
  final out = <Highlight>[];
  for (final t in terms) {
    if (t.definition.isEmpty || (used?.contains(t) ?? false)) continue;
    for (final label in t.koreanLabels) {
      final start = findTerm(text, label);
      if (start < 0) continue;
      final end = start + label.length;
      if (out.every((h) => end <= h.$1 || start >= h.$1 + h.$3.length)) {
        out.add((start, t, label));
        used?.add(t);
      }
      break;
    }
  }
  return out..sort((a, b) => a.$1.compareTo(b.$1));
}

// 하이라이트 사이 조각마다 wrap(한국어는 keepAll)을 적용한다(위치는 원래 문자열 기준이라 먼저 나눈 뒤 변환).
TextSpan highlightedSpan(String text, List<Highlight> hs, TextStyle style, String Function(String) wrap, {bool original = false}) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final (start, t, label) in hs) {
    spans.add(TextSpan(text: wrap(text.substring(at, start))));
    // 용어 뒤에 공백 없이 붙은 글자(조사 「을」, 복수 「s.」)는 같은 덩어리로 묶어 줄 끝에서 갈라지지 않게 한다.
    final end = start + label.length;
    final gap = text.indexOf(RegExp(r'\s'), end);
    final suffix = text.substring(end, gap < 0 ? text.length : gap);
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // 한 줄보다 긴 용어(큰 글씨·좁은 화면)는 하이라이트 안에서 줄을 바꿀 수 있어야 한다
            Flexible(child: TermHighlight(term: t, label: label, style: style, original: original)),
            if (suffix.isNotEmpty) Text(suffix, style: style, textScaler: TextScaler.noScaling),
          ],
        ),
      ),
    );
    at = end + suffix.length;
  }
  spans.add(TextSpan(text: wrap(text.substring(at))));
  return TextSpan(style: style, children: spans);
}

// 카드 하나의 글 여러 덩어리(문단·핵심 내용) → 덩어리마다 하이라이트. 카드 안에서 용어당 처음 1번만.
List<List<Highlight>> cardHighlights(List<String> texts, Iterable<GlossaryTerm> terms) {
  final used = <GlossaryTerm>{};
  return [for (final t in texts) findHighlights(t, terms, used: used)];
}

// 카드 글 한 덩어리. 하이라이트가 없으면 그냥 글자(KeepAllText와 같은 줄바꿈).
class TermText extends StatelessWidget {
  const TermText(this.text, {super.key, required this.highlights, required this.style});
  final String text;
  final List<Highlight> highlights;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text.rich(highlightedSpan(text, highlights, style, keepAll));
}

// 용어 하이라이트: 노란 highlight 배경(레퍼런스 011), 모서리 4, 여백 3/1. 누르면 진해지고(100ms) 시트가 열린다.
// 시트가 닫히면 원래 노랑으로(160ms). 「동작 줄이기」면 바로 바뀐다.
// ponytail: WidgetSpan이라 여러 단어 용어가 줄 끝에서 통째로 다음 줄로 넘어간다. 시안처럼 쪼개려면 TextSpan 배경 + 직접 그리기.
class TermHighlight extends StatefulWidget {
  const TermHighlight({super.key, required this.term, required this.label, required this.style, this.original = false});
  final GlossaryTerm term;
  final String label; // 화면에 보이는 표기(영문 원어 또는 한국어 표기)
  final TextStyle style;
  final bool original; // 번역 아래 대조용 원문(옅은 회색)

  @override
  State<TermHighlight> createState() => _TermHighlightState();
}

class _TermHighlightState extends State<TermHighlight> {
  var _active = false;

  Future<void> _open() async {
    HapticFeedback.selectionClick();
    setState(() => _active = true);
    await showTermSheet(context, widget.term);
    if (mounted) setState(() => _active = false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true, // 문장 Text에 합쳐지지 않고 따로 조작되게
      button: true,
      label: '용어 설명: ${widget.term.term}',
      excludeSemantics: true,
      onTap: _open,
      child: RgPressable(
        onTap: _open,
        child: AnimatedContainer(
          duration: RgMotion.of(context, _active ? RgMotion.press : RgMotion.release),
          curve: RgMotion.curve,
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: _active
                ? (widget.original ? RgColors.dividerCard : RgColors.highlightActive)
                : (widget.original ? RgColors.highlightOriginal : RgColors.highlight),
            borderRadius: BorderRadius.circular(RgRadius.term),
          ),
          // 문장 Text.rich가 WidgetSpan 자리를 이미 글자 배율만큼 키우므로 여기서 또 키우지 않는다.
          child: Text(widget.label, style: widget.style, textScaler: TextScaler.noScaling),
        ),
      ),
    );
  }
}
