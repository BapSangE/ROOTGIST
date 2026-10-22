import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_segmented.dart';
import 'term_sheet.dart';

// S03 초록 원문·번역 리더 (HANDOFF 7.4). 기본 모드는 S06 설정값.
// M3: 글자 크기 시트, 모드 전환 시 스크롤 보정.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.paperId, this.initialSentenceId});
  final String paperId;
  final String? initialSentenceId; // C01에서 들어오면 이 쌍으로 스크롤

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final _paper = repository.getPaper(widget.paperId).then((p) {
    if (widget.initialSentenceId case final id?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[id]?.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx);
      });
    }
    return p;
  });
  final _keys = <String, GlobalKey>{};
  var _mode = readerDefaultMode.value;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: RgColors.bgReading,
      body: Column(children: [
        // 상단 바는 스크롤 밖에 두어 고정한다.
        Container(
          color: RgColors.bgReading,
          padding: EdgeInsets.only(top: padding.top),
          height: padding.top + RgSpace.topBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
            child: Row(spacing: RgSpace.s8, children: [
              RgCircleButton(
                semanticLabel: '뒤로',
                icon: 'chevron-left',
                variant: RgCircleVariant.neutral,
                onTap: () => context.pop(),
              ),
              Expanded(
                child: RgSegmented(
                  options: const [
                    (ReaderMode.together, '함께'),
                    (ReaderMode.translation, '번역'),
                    (ReaderMode.original, '원문'),
                  ],
                  value: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ),
              const RgCircleButton(semanticLabel: '글자 크기', text: '가', variant: RgCircleVariant.neutral, onTap: null),
            ]),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            future: _paper,
            builder: (context, snap) {
              final p = snap.data;
              if (p == null) return const SizedBox.shrink();
              final highlights = firstHighlights(p);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(RgSpace.gutterReader, RgSpace.s20, RgSpace.gutterReader, 40 + padding.bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('초록 · 원문과 번역', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                    const SizedBox(height: RgSpace.s6),
                    Semantics(header: true, child: Text(keepAll(p.title), style: RgText.titleReader)),
                    const SizedBox(height: RgSpace.s28),
                    Column(
                      spacing: RgSpace.s28,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in p.sentences.where((s) => s.kind == 'text'))
                          _Pair(
                            key: _keys.putIfAbsent(s.id, GlobalKey.new),
                            sentence: s,
                            mode: _mode,
                            highlights: highlights[s.id] ?? const [],
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({super.key, required this.sentence, required this.mode, required this.highlights});
  final Sentence sentence;
  final ReaderMode mode;
  final List<(int, GlossaryTerm)> highlights;

  @override
  Widget build(BuildContext context) {
    final ko = sentence.translation;
    // Q13: 번역이 없는 문장은 모드와 상관없이 원문만 보인다.
    final showKo = ko != null && mode != ReaderMode.original;
    final showEn = ko == null || mode != ReaderMode.translation;
    final enStyle = mode == ReaderMode.together
        ? RgText.serifTogether.copyWith(color: RgColors.textBody)
        : RgText.serifOnly;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RgSpace.s8,
      children: [
        if (showKo) Text(keepAll(ko), style: RgText.bodyReaderKo),
        if (showEn) Text.rich(_highlighted(context, latexDisplay(sentence.text), enStyle)),
      ],
    );
  }

  TextSpan _highlighted(BuildContext context, String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (start, t) in highlights) {
      spans.add(TextSpan(text: text.substring(at, start)));
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: _Term(term: t, style: style),
      ));
      at = start + t.term.length;
    }
    spans.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: spans);
  }
}

// 용어 하이라이트: highlight 배경, 모서리 4, 여백 3/1. 누름·시트 열림 동안 highlightActive.
// ponytail: WidgetSpan이라 여러 단어 용어가 줄 끝에서 통째로 다음 줄로 넘어간다. 시안처럼 쪼개려면 TextSpan 배경 + 직접 그리기.
class _Term extends StatefulWidget {
  const _Term({required this.term, required this.style});
  final GlossaryTerm term;
  final TextStyle style;

  @override
  State<_Term> createState() => _TermState();
}

class _TermState extends State<_Term> {
  var _active = false;

  Future<void> _open() async {
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
      child: RgPressable(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: _active ? RgColors.highlightActive : RgColors.highlight,
            borderRadius: BorderRadius.circular(RgRadius.term),
          ),
          child: Text(widget.term.term, style: widget.style),
        ),
      ),
    );
  }
}

// 문장 ID → [(시작 위치, 용어)]. 용어마다 리더 전체에서 처음 나온 1회만, 표시 문자열(8.3 변환 후) 기준.
// highlight=false 이거나 정의가 빈 용어는 강조하지 않는다(8.4, 7.5).
Map<String, List<(int, GlossaryTerm)>> firstHighlights(PaperDetail p) {
  final out = <String, List<(int, GlossaryTerm)>>{};
  for (final t in p.glossary.where((t) => t.highlight && t.definition.isNotEmpty)) {
    for (final s in p.sentences.where((s) => s.kind == 'text' && t.sentenceIds.contains(s.id))) {
      final start = latexDisplay(s.text).indexOf(t.term);
      if (start < 0) continue;
      final list = out.putIfAbsent(s.id, () => []);
      final end = start + t.term.length;
      if (list.every((h) => end <= h.$1 || start >= h.$1 + h.$2.term.length)) list.add((start, t)); // 겹침 제외
      break;
    }
  }
  for (final list in out.values) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
  }
  return out;
}
