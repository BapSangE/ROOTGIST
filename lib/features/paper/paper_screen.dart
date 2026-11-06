import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_bookmark_motion.dart';
import '../../design/widgets/rg_states.dart';
import '../common/term_text.dart';
import '../reader/text_size_sheet.dart';
import '../settings/ai_notice_sheet.dart';
import 'evidence_sheet.dart';

// 논문 상세는 한 장의 종이처럼 읽는다. 읽기·공유·저장은 하단 dock에 모은다.
class PaperScreen extends StatefulWidget {
  const PaperScreen({super.key, required this.paperId});
  final String paperId;

  @override
  State<PaperScreen> createState() => _PaperScreenState();
}

class _PaperScreenState extends State<PaperScreen> {
  late final _req = Reloadable(() => repository.getPaper(widget.paperId));

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final p = snap.data;
          final savedTitle = bookmarks.value[widget.paperId]?.title;
          return Scaffold(
            backgroundColor: RgColors.bgReading,
            bottomNavigationBar: p == null ? null : _Dock(paper: p),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ListView(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                      bottom: p == null
                          ? MediaQuery.paddingOf(context).bottom + RgSpace.s24
                          : 0,
                    ),
                    children: [
                      const _TopBar(),
                      if (p != null)
                        ..._content(context, p)
                      else if (snap.hasError) ...[
                        if (savedTitle != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              RgSpace.gutterText,
                              RgSpace.s16,
                              RgSpace.gutterText,
                              0,
                            ),
                            child: HeadingTextScale(
                              child: Semantics(
                                header: true,
                                child: KeepAllText(
                                  savedTitle,
                                  style: _PaperText.title,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: RgSpace.s24),
                        RgErrorCard(error: snap.error, onRetry: _req.reload),
                      ] else
                        const _PaperSkeleton(),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: MediaQuery.paddingOf(context).top,
                  child: ColoredBox(color: RgColors.bgReading),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _content(BuildContext context, PaperDetail p) {
    final paras = summaryParagraphs(p.summary ?? '');
    final points = p.keyPoints.take(3).toList();
    final marks = cardHighlights([
      ...paras,
      for (final k in points) k.claim,
    ], p.glossary);
    return [
      Container(
        padding: const EdgeInsets.fromLTRB(
          RgSpace.gutterText,
          RgSpace.s16,
          RgSpace.gutterText,
          RgSpace.s20,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: RgColors.borderDefault)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${p.topicLabel == null ? '' : '${p.topicLabel} · '}arXiv ${p.id}',
              style: _PaperText.metadata,
            ),
            const SizedBox(height: RgSpace.s8),
            HeadingTextScale(
              child: Semantics(
                header: true,
                child: KeepAllText(p.title, style: _PaperText.title),
              ),
            ),
            if (p.ready && p.titleKo != null) ...[
              const SizedBox(height: RgSpace.s8),
              Text(
                p.titleEn,
                style: RgText.serifSubtitle.copyWith(
                  fontSize: 15,
                  height: 19 / 15,
                  fontWeight: FontWeight.w300,
                  letterSpacing: -0.3,
                  color: RgColors.textPrimary,
                ),
              ),
            ],
            const SizedBox(height: RgSpace.s10),
            Wrap(
              spacing: RgSpace.s8,
              runSpacing: RgSpace.s8,
              children: [
                _MetaPill(icon: 'pen', label: p.authorLine),
                _MetaPill(icon: 'calendar', label: p.date),
              ],
            ),
          ],
        ),
      ),
      if (!p.ready)
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RgSpace.gutterText,
            vertical: RgSpace.s24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.aiStatus == 'failed' ? '해설을 만들지 못했어요' : '해설을 준비하고 있어요',
                style: _PaperText.section,
              ),
              const SizedBox(height: RgSpace.s8),
              KeepAllText(
                '다음 수집 때 다시 만들어요. 원문은 아래 링크에서 볼 수 있어요.',
                style: _PaperText.body.copyWith(color: RgColors.textSecondary),
              ),
            ],
          ),
        ),
      if (p.ready) ...[
        // 앱의 읽기 설정은 요약과 핵심 내용에도 계속 적용한다.
        ReaderTextScale(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              RgSpace.gutterText,
              RgSpace.s24,
              RgSpace.gutterText,
              RgSpace.s28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: RgSpace.s8,
                  runSpacing: RgSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text('AI 요약', style: _PaperText.section),
                    ),
                    Text(
                      '초록 기반',
                      style: RgText.meta.copyWith(
                        fontSize: 14,
                        height: 16 / 14,
                        fontWeight: FontWeight.w500,
                        color: RgColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: RgSpace.s16),
                for (final (i, s) in paras.indexed)
                  TermText(
                    s,
                    highlights: marks[i],
                    style: _PaperText.body,
                    backgroundColor: RgColors.fillNeutral,
                  ),
                if (points.isNotEmpty) ...[
                  const SizedBox(height: 56),
                  Semantics(
                    header: true,
                    child: Text('핵심 내용', style: _PaperText.section),
                  ),
                  const SizedBox(height: RgSpace.s16),
                  Column(
                    spacing: RgSpace.s12,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (i, k) in points.indexed)
                        _KeyPointItem(
                          paper: p,
                          index: i + 1,
                          point: k,
                          highlights: marks[paras.length + i],
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Semantics(
          button: true,
          child: RgPressable(
            onTap: () => showAiNoticeSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RgSpace.gutterText,
                vertical: RgSpace.s20,
              ),
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: RgColors.borderDefault),
                ),
              ),
              child: KeepAllText(
                '초록을 바탕으로 AI가 정리했어요. 논문 본문 전체를 반영하지는 않아요.',
                style: _PaperText.metadata.copyWith(height: 16 / 12),
              ),
            ),
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RgSpace.gutterText,
          vertical: RgSpace.s24,
        ),
        child: Column(
          children: [
            _InfoRow(
              label: '원문 출처',
              value: 'arXiv · ${p.id}',
              semanticsLabel: 'arXiv에서 원문 열기',
              onTap: () => launchUrl(
                Uri.parse(p.arxivUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            if (p.hfUrl.isNotEmpty)
              _InfoRow(
                label: '논문 페이지',
                value: 'Hugging Face',
                semanticsLabel: 'Hugging Face에서 논문 페이지 열기',
                onTap: () => launchUrl(
                  Uri.parse(p.hfUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            if (p.orgName != null) _InfoRow(label: '게시 조직', value: p.orgName!),
            _InfoRow(label: '발행일', value: p.date),
          ],
        ),
      ),
    ];
  }
}

abstract class _PaperText {
  static TextStyle get title => RgText.titleDetail.copyWith(
    fontSize: 26,
    height: 32 / 26,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.52,
  );
  static TextStyle get section => RgText.titleSection.copyWith(
    fontSize: 20,
    height: 24 / 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
  );
  static TextStyle get body => RgText.bodySummary.copyWith(
    fontSize: 14,
    height: 1.8,
    letterSpacing: -0.14,
    color: RgColors.textPrimary,
  );
  static TextStyle get metadata => RgText.meta.copyWith(
    fontSize: 12,
    height: 19 / 12,
    letterSpacing: -0.24,
    color: RgColors.textSecondary,
  );
}

class _PaperSkeleton extends StatelessWidget {
  const _PaperSkeleton();

  @override
  Widget build(BuildContext context) => const RgSkeleton(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        RgSpace.gutterText,
        RgSpace.s16,
        RgSpace.gutterText,
        RgSpace.s24,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RgBar(lineHeight: 19, widthFactor: 0.4),
          SizedBox(height: RgSpace.s8),
          RgBar(lineHeight: 32, widthFactor: 0.9),
          SizedBox(height: RgSpace.s8),
          RgBar(lineHeight: 19, widthFactor: 0.7),
          SizedBox(height: RgSpace.s10),
          RgBar(lineHeight: 28, widthFactor: 0.6),
          SizedBox(height: RgSpace.s40),
          RgBar(lineHeight: 24, widthFactor: 0.3),
          SizedBox(height: RgSpace.s16),
          RgBar(lineHeight: 25),
          SizedBox(height: RgSpace.s4),
          RgBar(lineHeight: 25),
          SizedBox(height: RgSpace.s4),
          RgBar(lineHeight: 25, widthFactor: 0.6),
        ],
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: RgSpace.s10),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: '뒤로',
        excludeSemantics: true,
        onTap: () => context.pop(),
        child: RgPressable(
          onTap: () => context.pop(),
          child: SizedBox.square(
            dimension: RgSpace.minTouch,
            child: Center(
              child: RgIcon(
                'chevron-left',
                size: 24,
                color: RgColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _KeyPointItem extends StatelessWidget {
  const _KeyPointItem({
    required this.paper,
    required this.index,
    required this.point,
    required this.highlights,
  });
  final PaperDetail paper;
  final int index;
  final KeyPoint point;
  final List<Highlight> highlights;

  @override
  Widget build(BuildContext context) {
    final n = sentenceNumber(point.evidenceIds.first);
    void open() => showEvidenceSheet(
      context,
      paper: paper,
      pointIndex: index,
      sentenceId: point.evidenceIds.first,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: RgSpace.s10,
      children: [
        SizedBox(
          width: RgSpace.s20,
          child: Text(
            '$index',
            textAlign: TextAlign.end,
            style: _PaperText.body.copyWith(
              fontSize: 12,
              height: 25.2 / 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: RgSpace.s2,
            children: [
              TermText(
                point.claim,
                highlights: highlights,
                style: _PaperText.body,
                backgroundColor: RgColors.fillNeutral,
              ),
              Semantics(
                button: true,
                label: '원문 근거, 초록 $n번째 문장',
                excludeSemantics: true,
                onTap: open,
                child: RgPressable(
                  onTap: open,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: RgSpace.minTouch,
                    ),
                    child: const Align(
                      alignment: Alignment.topLeft,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: _MetaPill(icon: 'search', label: '관련 원문 보기'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.onTap,
    this.semanticsLabel,
  });
  final String label;
  final String value;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: RgSpace.s10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RgSpace.s16,
          children: [
            Text(
              label,
              style: RgText.bodySmall.copyWith(
                fontSize: 14,
                height: 20 / 14,
                color: RgColors.textBody,
                decoration: onTap == null ? null : TextDecoration.underline,
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: RgText.bodySmall.copyWith(
                  fontSize: 14,
                  height: 20 / 14,
                  color: RgColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return onTap == null
        ? row
        : Semantics(
            link: true,
            label: semanticsLabel,
            excludeSemantics: semanticsLabel != null,
            onTap: onTap,
            child: RgPressable(onTap: onTap, child: row),
          );
  }
}

// 소수점 등 수치 안의 마침표는 보존하고 문장 사이에서만 문단을 나눈다.
List<String> summaryParagraphs(String s) => s
    .trim()
    .split(RegExp(r'(?<=[가-힣)\]][.!?])\s+'))
    .where((p) => p.isNotEmpty)
    .toList();

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});
  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: RgSpace.s28),
    padding: const EdgeInsets.symmetric(
      horizontal: RgSpace.s12,
      vertical: RgSpace.s6,
    ),
    decoration: BoxDecoration(
      color: RgColors.textPrimary.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(RgSpace.s8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: RgSpace.s4,
      children: [
        RgIcon(icon, size: 12, color: RgColors.textBody),
        Flexible(
          child: KeepAllText(
            label,
            style: _PaperText.metadata.copyWith(
              height: 16 / 12,
              letterSpacing: 0,
              fontWeight: FontWeight.w500,
              color: RgColors.textBody,
            ),
          ),
        ),
      ],
    ),
  );
}

class _Dock extends StatelessWidget {
  const _Dock({required this.paper});
  final PaperDetail paper;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return Container(
      decoration: BoxDecoration(
        color: RgColors.bgReading,
        border: Border(top: BorderSide(color: RgColors.borderDefault)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            RgSpace.gutterText,
            RgSpace.s16,
            RgSpace.gutterText,
            RgSpace.s2,
          ),
          child: ChromeTextScale(
            child: Row(
              spacing: RgSpace.s12,
              children: [
                if (p.ready)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      heightFactor: 1,
                      child: _ReadButton(paper: p),
                    ),
                  )
                else
                  const Spacer(),
                _DockIconButton(
                  label: '공유',
                  icon: RgIcon(
                    'reicon-share',
                    size: 38,
                    color: RgColors.textPrimary,
                  ),
                  onTap: () => SharePlus.instance.share(
                    ShareParams(text: '${p.title}\n${p.hfUrl}'),
                  ),
                ),
                ValueListenableBuilder(
                  valueListenable: bookmarks,
                  builder: (_, saved, _) {
                    final selected = saved.containsKey(p.id);
                    return RgBookmarkMotion(
                      saved: selected,
                      child: _DockIconButton(
                        label: selected ? '저장됨, 북마크 해제' : '북마크에 저장',
                        selected: selected,
                        icon: RgIcon(
                          selected ? 'reicon-detail-bookmark' : 'bookmark',
                          size: selected ? 38 : 20,
                          color: RgColors.textPrimary,
                        ),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          toggleBookmark(p.id, p.title);
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.paper});
  final PaperDetail paper;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: RgPressable(
      onTap: () => context.push('/paper/${paper.id}/reader'),
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth < 224 ? RgSpace.s16 : RgSpace.s24,
            vertical: RgSpace.s12,
          ),
          decoration: BoxDecoration(
            color: RgColors.actionPrimary,
            borderRadius: BorderRadius.circular(RgRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: RgSpace.s12,
            children: [
              RgIcon('translate', size: 24, color: RgColors.onAction),
              Flexible(
                child: Text(
                  '번역과 함께 초록 읽기',
                  textAlign: TextAlign.center,
                  style: RgText.bodySmall.copyWith(
                    fontSize: 15,
                    height: 16 / 15,
                    fontWeight: FontWeight.w600,
                    color: RgColors.onAction,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected,
  });
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool? selected;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: true,
    toggled: selected,
    enabled: true,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: RgPressable(
      onTap: onTap,
      child: SizedBox.square(
        dimension: RgSpace.minTouch,
        child: Center(child: icon),
      ),
    ),
  );
}
