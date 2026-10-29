import '../../analytics/posthog_sink.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_segmented.dart';
import '../../design/widgets/rg_states.dart';
import '../common/term_text.dart';
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
      if (mounted) analytics.readerLoaded(widget.paperId);
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
    analytics.readerDisposed(widget.paperId);
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
    // 하단 조절 바(레퍼런스 009): 떠 있는 검정 세그먼트(함께·번역·원문) + 「가」. 탭바는 없다(글에 집중).
    final barBottom = padding.bottom > RgSpace.floatingBottom ? padding.bottom : RgSpace.floatingBottom;
    return Scaffold(
      backgroundColor: RgColors.bgReading,
      body: Stack(children: [
        Column(
        children: [
          // 상단 바는 스크롤 밖에 두어 고정한다. 가운데에 「초록 · N문장」
          Container(
            color: RgColors.bgReading,
            padding: EdgeInsets.only(top: padding.top),
            height: padding.top + RgSpace.topBar,
            child: ChromeTextScale(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: Row(
                  children: [
                    RgBackButton(onTap: () => context.pop()),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _req,
                        builder: (context, _) => FutureBuilder(
                          future: _req.future,
                          builder: (context, snap) => Text(
                            [
                              '초록',
                              if (snap.data case final p?) '${p.sentences.where((s) => s.kind == 'text').length}문장',
                            ].join(' · '),
                            textAlign: TextAlign.center,
                            style: RgText.meta.copyWith(color: RgColors.textSecondary),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: RgSpace.minTouch - RgSpace.s16), // 뒤로 버튼(당겨진 폭)과 균형
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
                              const RgBar(lineHeight: 18, widthFactor: 0.3),
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
                  return SingleChildScrollView(
                    controller: _scroll,
                    // 아래 조절 바(52) 밑으로 마지막 문장이 가리지 않게
                    padding: EdgeInsets.fromLTRB(
                      RgSpace.gutterReader,
                      RgSpace.s8,
                      RgSpace.gutterReader,
                      barBottom + 52 + RgSpace.s40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        HeadingTextScale(child: Semantics(header: true, child: KeepAllText(p.title, style: RgText.titleReader))),
                        const SizedBox(height: RgSpace.s6),
                        Text('원문과 번역을 문장마다 맞대어 읽어요', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                        const SizedBox(height: RgSpace.s24),
                        // 글자 크기 단계는 본문에만, 시스템 글자 크기와 곱해서 적용한다.
                        MediaQuery(
                          data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * readerScale.value)),
                          child: _PairList(paper: p, mode: _mode, keys: _keys),
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
        // 바 아래로 사라지는 글이 버튼과 겹쳐 보이지 않게 바탕색 페이드
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: barBottom + 52 + RgSpace.s40,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FAFAF7), RgColors.bgReading],
                  stops: [0, 0.55],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: RgSpace.gutterText,
          right: RgSpace.gutterText,
          bottom: barBottom,
          child: ChromeTextScale(
            child: Row(spacing: RgSpace.s8, children: [
              Expanded(
                child: RgSegmented(
                  ink: true,
                  height: 52,
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
                size: 52,
                variant: RgCircleVariant.filled,
                onTap: () => showTextSizeSheet(context),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// 본문 문장 쌍 목록. 쌍마다 문장 번호, 쌍 사이 구분선(iOS QA 디자인 A+B). keys는 쌍마다 달아 스크롤 보정에 쓴다.
class _PairList extends StatelessWidget {
  const _PairList({required this.paper, required this.mode, required this.keys});
  final PaperDetail paper;
  final ReaderMode mode;
  final Map<String, GlobalKey> keys;

  @override
  Widget build(BuildContext context) {
    final highlights = firstHighlights(paper);
    final highlightsKo = firstHighlights(paper, korean: true);
    final pairs = [
      for (final s in paper.sentences.where((s) => s.kind == 'text'))
        _Pair(
          key: keys.putIfAbsent(s.id, GlobalKey.new),
          sentence: s,
          mode: mode,
          highlights: highlights[s.id] ?? const [],
          highlightsKo: highlightsKo[s.id] ?? const [],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, pair) in pairs.indexed) ...[
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(vertical: RgSpace.s12),
              child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
            ),
          pair,
        ],
      ],
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
    // 「함께」에서 원문 쪽 용어는 옅은 회색(노란색은 번역문의 용어에만)
    final enText = Text.rich(highlightedSpan(latexDisplay(sentence.text), highlights, enStyle, (s) => s, original: showKo));
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RgSpace.s8,
      children: [
        if (showKo) Text.rich(highlightedSpan(ko, highlightsKo, RgText.bodyReaderKo, keepAll)),
        if (showEn)
          if (showKo)
            // A: 번역 아래 원문은 왼쪽 세로선 + 들여쓰기
            Container(
              padding: const EdgeInsets.only(left: RgSpace.s12),
              decoration: BoxDecoration(border: Border(left: BorderSide(color: RgColors.borderDefault, width: 2))),
              child: enText,
            )
          else
            enText,
      ],
    );
    // B: 문장 번호(상세 「초록 N번째 문장」과 같은 번호). 첫 줄 행간에 맞춰 세로 가운데.
    final firstLine = showKo ? 29.0 : (mode == ReaderMode.together ? enStyle.fontSize! * enStyle.height! : 30.0);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: RgSpace.s20,
          child: ExcludeSemantics(
            child: Text(
              '${sentenceNumber(sentence.id)}',
              style: RgText.meta.copyWith(height: firstLine / RgText.meta.fontSize!, fontWeight: FontWeight.w600, color: RgColors.textTertiary),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

// 문장 ID → [(시작 위치, 용어, 표기)]. 용어마다 리더 전체에서 처음 나온 1회만.
// 영문: 표시 문자열(8.3 변환 후)에서 원어를 찾는다. highlight=false 이거나 정의가 빈 용어는 강조하지 않는다(8.4, 7.5).
// 한국어(G2): 번역문에서 찾는다. 이 논문 번역문의 실제 표기(termKoSpan) → 사전 대응어 → 번역문에 남은 영문(SFT·VLM).
// 사전에 없는 용어도 찾는다. 「강화 학습 (RL)」처럼 뒤 괄호는 떼고 찾는다.
Map<String, List<Highlight>> firstHighlights(PaperDetail p, {bool korean = false}) {
  final out = <String, List<Highlight>>{};
  final terms = p.glossary.where((t) => t.definition.isNotEmpty && (korean || t.highlight));
  for (final t in terms) {
    found:
    for (final s in p.sentences.where((s) => s.kind == 'text' && t.sentenceIds.contains(s.id))) {
      final text = korean ? s.translation ?? '' : latexDisplay(s.text);
      for (final label in korean ? t.koreanLabels : [t.term]) {
        final start = findTerm(text, label);
        if (start < 0) continue;
        final list = out.putIfAbsent(s.id, () => []);
        final end = start + label.length;
        if (list.every((h) => end <= h.$1 || start >= h.$1 + h.$3.length)) list.add((start, t, label)); // 겹침 제외
        break found;
      }
    }
  }
  for (final list in out.values) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
  }
  return out;
}
