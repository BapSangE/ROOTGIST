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
import '../../design/widgets/rg_states.dart';
import 'term_sheet.dart';
import 'text_size_sheet.dart';

// S03 초록 원문·번역 리더 (HANDOFF 7.4). 기본 모드는 S06 설정값.
// 모드·글자 크기를 바꿔도 화면 맨 위에 걸친 문장 쌍이 같은 자리에 남도록 스크롤을 보정한다.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.paperId, this.initialSentenceId});
  final String paperId;
  final String? initialSentenceId; // C01에서 들어오면 이 쌍으로 스크롤

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late final _req = Reloadable(
    () => repository.getPaper(widget.paperId).then((p) {
      if (widget.initialSentenceId case final id?) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _keys[id]?.currentContext;
          if (ctx != null) Scrollable.ensureVisible(ctx);
        });
      }
      return p;
    }),
  );
  final _keys = <String, GlobalKey>{}; // 문장 순서대로 들어간다
  final _scroll = ScrollController();
  var _mode = readerDefaultMode.value;

  @override
  void initState() {
    super.initState();
    readerScale.addListener(_onScale);
  }

  @override
  void dispose() {
    readerScale.removeListener(_onScale);
    _scroll.dispose();
    _req.dispose();
    super.dispose();
  }

  void _onScale() => _keepPosition(() => setState(() {}));

  void _keepPosition(VoidCallback change) {
    final viewportTop = MediaQuery.paddingOf(context).top + RgSpace.topBar;
    RenderBox? boxOf(String id) => _keys[id]?.currentContext?.findRenderObject() as RenderBox?;
    (String, double)? anchor;
    for (final id in _keys.keys) {
      final box = boxOf(id);
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > viewportTop) {
        anchor = (id, top);
        break;
      }
    }
    change();
    if (anchor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = boxOf(anchor!.$1);
      if (box == null || !_scroll.hasClients) return;
      final p = _scroll.position;
      final target = p.pixels + box.localToGlobal(Offset.zero).dy - anchor.$2;
      _scroll.jumpTo(target.clamp(p.minScrollExtent, p.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final mq = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: RgColors.bgReading,
      body: Column(
        children: [
          // 상단 바는 스크롤 밖에 두어 고정한다.
          Container(
            color: RgColors.bgReading,
            padding: EdgeInsets.only(top: padding.top),
            height: padding.top + RgSpace.topBar,
            child: ChromeTextScale(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: Row(
                  spacing: RgSpace.s8,
                  children: [
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
                        onChanged: (m) => _keepPosition(() => setState(() => _mode = m)),
                      ),
                    ),
                    RgCircleButton(
                      semanticLabel: '글자 크기',
                      text: '가',
                      variant: RgCircleVariant.neutral,
                      onTap: () => showTextSizeSheet(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _req,
              builder: (context, _) => FutureBuilder(
                future: _req.future,
                builder: (context, snap) {
                  final p = snap.data;
                  if (snap.hasError) {
                    return ListView(
                      padding: const EdgeInsets.only(top: RgSpace.s20),
                      children: [RgErrorCard(error: snap.error, onRetry: _req.reload)],
                    );
                  }
                  if (p == null) {
                    // 짧은 화면에서 넘치지 않게 스크롤 없는 목록에 넣어 잘라 낸다.
                    return ListView(
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(RgSpace.gutterReader, RgSpace.s20, RgSpace.gutterReader, 0),
                      children: [
                        RgSkeleton(
                          child: Column(
                            children: [
                              const RgBar(lineHeight: 16, widthFactor: 0.3),
                              const SizedBox(height: RgSpace.s6),
                              const RgBar(lineHeight: 31, widthFactor: 0.8),
                              const SizedBox(height: RgSpace.s28),
                              for (var i = 0; i < 3; i++) ...const [
                                RgBar(lineHeight: 29),
                                RgBar(lineHeight: 29, widthFactor: 0.6),
                                SizedBox(height: RgSpace.s8),
                                RgBar(lineHeight: 25),
                                RgBar(lineHeight: 25, widthFactor: 0.75),
                                SizedBox(height: RgSpace.s28),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  final highlights = firstHighlights(p);
                  final highlightsKo = firstHighlights(p, korean: true);
                  return SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(
                      RgSpace.gutterReader,
                      RgSpace.s20,
                      RgSpace.gutterReader,
                      40 + padding.bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('초록 · 원문과 번역', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                        const SizedBox(height: RgSpace.s6),
                        Semantics(header: true, child: KeepAllText(p.title, style: RgText.titleReader)),
                        const SizedBox(height: RgSpace.s28),
                        // 글자 크기 단계는 본문에만, 시스템 글자 크기와 곱해서 적용한다.
                        MediaQuery(
                          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * readerScale.value)),
                          child: Column(
                            spacing: RgSpace.s28,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final s in p.sentences.where((s) => s.kind == 'text'))
                                _Pair(
                                  key: _keys.putIfAbsent(s.id, GlobalKey.new),
                                  sentence: s,
                                  mode: _mode,
                                  highlights: highlights[s.id] ?? const [],
                                  highlightsKo: highlightsKo[s.id] ?? const [],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair({
    super.key,
    required this.sentence,
    required this.mode,
    required this.highlights,
    required this.highlightsKo,
  });
  final Sentence sentence;
  final ReaderMode mode;
  final List<Highlight> highlights;
  final List<Highlight> highlightsKo;

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
        if (showKo) Text.rich(_highlighted(ko, highlightsKo, RgText.bodyReaderKo, keepAll)),
        if (showEn) Text.rich(_highlighted(latexDisplay(sentence.text), highlights, enStyle, (s) => s)),
      ],
    );
  }

  // 한국어는 하이라이트 사이 조각마다 keepAll을 적용한다(위치는 원래 문자열 기준이라 먼저 나눈 뒤 변환).
  TextSpan _highlighted(String text, List<Highlight> hs, TextStyle style, String Function(String) wrap) {
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
              Flexible(child: _Term(term: t, label: label, style: style)),
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
}

// 용어 하이라이트: highlight 배경, 모서리 4, 여백 3/1. 누름·시트 열림 동안 highlightActive.
// ponytail: WidgetSpan이라 여러 단어 용어가 줄 끝에서 통째로 다음 줄로 넘어간다. 시안처럼 쪼개려면 TextSpan 배경 + 직접 그리기.
class _Term extends StatefulWidget {
  const _Term({required this.term, required this.label, required this.style});
  final GlossaryTerm term;
  final String label; // 화면에 보이는 표기(영문 원어 또는 한국어 대응어)
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
      onTap: _open,
      child: RgPressable(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(
            color: _active ? RgColors.highlightActive : RgColors.highlight,
            borderRadius: BorderRadius.circular(RgRadius.term),
          ),
          // 문장 Text.rich가 WidgetSpan 자리를 이미 글자 배율만큼 키우므로 여기서 또 키우지 않는다.
          child: Text(widget.label, style: widget.style, textScaler: TextScaler.noScaling),
        ),
      ),
    );
  }
}

typedef Highlight = (int start, GlossaryTerm term, String label);

// 문장 ID → [(시작 위치, 용어, 표기)]. 용어마다 리더 전체에서 처음 나온 1회만.
// 영문: 표시 문자열(8.3 변환 후)에서 원어를 찾는다. highlight=false 이거나 정의가 빈 용어는 강조하지 않는다(8.4, 7.5).
// 한국어(G2): 사전에 연결된 용어를 번역문에서 찾는다. 이 논문 번역문의 실제 표기(termKoSpan)가 있으면 그것,
// 없으면 대응어. 「강화 학습 (RL)」처럼 뒤 괄호는 떼고 찾는다.
Map<String, List<Highlight>> firstHighlights(PaperDetail p, {bool korean = false}) {
  final out = <String, List<Highlight>>{};
  final terms = korean
      ? p.glossary.where((t) => t.termKo != null && t.definition.isNotEmpty)
      : p.glossary.where((t) => t.highlight && t.definition.isNotEmpty);
  for (final t in terms) {
    final label = korean ? (t.termKoSpan ?? t.termKo!).replaceFirst(RegExp(r'\s*\(.*\)$'), '') : t.term;
    if (label.isEmpty) continue;
    for (final s in p.sentences.where((s) => s.kind == 'text' && t.sentenceIds.contains(s.id))) {
      final start = (korean ? s.translation ?? '' : latexDisplay(s.text)).indexOf(label);
      if (start < 0) continue;
      final list = out.putIfAbsent(s.id, () => []);
      final end = start + label.length;
      if (list.every((h) => end <= h.$1 || start >= h.$1 + h.$3.length)) list.add((start, t, label)); // 겹침 제외
      break;
    }
  }
  for (final list in out.values) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
  }
  return out;
}
