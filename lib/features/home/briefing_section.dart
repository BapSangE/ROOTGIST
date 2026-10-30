import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/unread.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../data/repository.dart';
import '../explore/official_news.dart';
import 'home_screen.dart' show openExplore;
import 'briefing.dart';

// 홈 맨 위 「오늘의 브리핑」(시안 A): 날짜·브리핑 이름 → 「어제 이후 새 소식 N건」 → 요약 알약 → 주요 소식 5개 카드.
// 나머지 새 소식은 같은 카드 안에서 펼친다(220ms, 보관함 접힘과 같은 SizeTransition). 「동작 줄이기」면 바로.
class BriefingSection extends StatefulWidget {
  const BriefingSection({super.key, required this.news, required this.paperCount});
  final List<OfficialNews>? news; // null = 아직 불러오는 중
  final int paperCount;

  @override
  State<BriefingSection> createState() => _BriefingSectionState();
}

class _BriefingSectionState extends State<BriefingSection> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final now = clock();
    final news = widget.news;
    final b = news == null ? null : Briefing(news, now);
    final headline = switch (b) {
      null => '소식을 모으는 중이에요',
      Briefing(total: 0) => '새 소식이 없어요',
      Briefing(wide: true) => '최근 3일 새 소식 ${b.total}건',
      _ => '어제 이후 새 소식 ${b.total}건',
    };
    final date = '${koreanDate(now.toUtc().add(const Duration(hours: 9)))} · ${briefingLabel(now)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s8, RgSpace.gutterText, 0),
        child: Semantics(
          header: true,
          label: '$date $headline',
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
            KeepAllText(date, style: RgText.meta.copyWith(fontSize: 15, fontWeight: FontWeight.w500, color: RgColors.textSecondary)),
            HeadingTextScale(child: KeepAllText(headline, style: RgText.displayHome)),
          ]),
        ),
      ),
      if (b != null) ...[
        const SizedBox(height: RgSpace.s12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          child: Wrap(spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: [
            if (b.stories.isNotEmpty) _Pill('주요 소식', '${b.stories.length}'),
            if (b.hotCount > 0) _Pill('개발자 화제', '${b.hotCount}'),
            if (widget.paperCount > 0) _Pill('새 논문', '${widget.paperCount}편'),
            if (b.updates > 0) _Pill('바뀐 도구', '${b.updates}'),
          ]),
        ),
      ],
      if (b != null && b.stories.isNotEmpty) ...[
        const SizedBox(height: RgSpace.s20),
        RgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s20, RgSpace.s4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(child: Semantics(header: true, child: Text(b.stale ? '최근 소식' : b.wide ? '최근 주요 소식' : '오늘의 주요 소식', style: RgText.titleCard))),
                if (!b.stale)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120), // 큰 글자에서는 줄을 바꾼다
                    child: Text('중요한 순', textAlign: TextAlign.end, style: RgText.meta.copyWith(fontSize: 13, color: RgColors.textSecondary)),
                  ),
              ]),
            ),
            for (final (i, n) in b.stories.indexed) BriefRow(news: n, number: i + 1, now: now, divider: i > 0),
            // 나머지: 펼치면 같은 카드 안에 최신순으로(번호 없이)
            AnimatedSize(
              duration: RgMotion.of(context, RgMotion.base),
              curve: RgMotion.curve,
              alignment: Alignment.topCenter,
              child: _open
                  ? Column(children: [for (final n in b.rest) BriefRow(news: n, now: now, divider: true)])
                  : const SizedBox(width: double.infinity),
            ),
            if (b.rest.isNotEmpty)
              Semantics(
                button: true,
                expanded: _open,
                child: RgPressable(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _open = !_open);
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: RgSpace.minTouch + 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: RgColors.dividerCard))),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s4, children: [
                      Flexible(child: Text(_open ? '접기' : b.stale ? '최근 소식 ${b.rest.length}건 더 보기' : '나머지 새 소식 ${b.rest.length}건 보기', textAlign: TextAlign.center, style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textBody))),
                      AnimatedRotation(
                        turns: _open ? -0.25 : 0.25,
                        duration: RgMotion.of(context, RgMotion.base),
                        curve: RgMotion.curve,
                        child: const RgIcon('chevron-right', size: 16, color: RgColors.textBody),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ],
      // 개발자 화제(시안 A): Hacker News 점수 순 2개, 나머지는 탐색의 화제 칸으로
      if (b != null && b.talk.isNotEmpty) ...[
        const SizedBox(height: RgSpace.s12),
        RgCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s20, RgSpace.s4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(child: Semantics(header: true, child: Text('개발자 화제', style: RgText.titleCard))),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text('Hacker News', textAlign: TextAlign.end, style: RgText.meta.copyWith(fontSize: 13, color: RgColors.textSecondary)),
                ),
              ]),
            ),
            for (final (i, n) in b.talk.take(2).indexed) BriefRow(news: n, number: i + 1, now: now, divider: i > 0),
            Semantics(
              button: true,
              child: RgPressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  openExplore(context, const ExploreJump(1, hot: true));
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: RgSpace.minTouch + 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border(top: BorderSide(color: RgColors.dividerCard))),
                  child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s4, children: [
                    Flexible(child: Text('화제 ${b.hotCount}건 모두 보기', textAlign: TextAlign.center, style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textBody))),
                    const RgIcon('chevron-right', size: 16, color: RgColors.textBody),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: RgSpace.s10, vertical: RgSpace.s4),
    decoration: BoxDecoration(color: RgColors.surfaceCard, borderRadius: BorderRadius.circular(RgRadius.pill)),
    child: Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label '),
        TextSpan(text: value, style: TextStyle(fontWeight: FontWeight.w500, color: RgColors.textSecondary)),
      ]),
      style: RgText.caption.copyWith(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: RgColors.textBody),
    ),
  );
}

// 브리핑 한 줄: (번호) · 회사 칩 · 「6시간 전」 · 관련 N · 새 글 → 제목 두 줄 → 한 줄 요약. 누르면 소식 상세.
class BriefRow extends StatelessWidget {
  const BriefRow({super.key, required this.news, required this.now, this.number, this.divider = true});
  final OfficialNews news;
  final DateTime now;
  final int? number;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final n = news;
    final one = n.summaryKo ?? n.keyPoints.firstOrNull?.text;
    final read = readItems.value.contains(newsKey(n));
    return Semantics(
      button: true,
      child: RgPressable(
        row: true,
        onTap: () => context.push('/news/${Uri.encodeComponent(n.id)}'),
        child: Container(
          padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s14, RgSpace.s18, RgSpace.s14),
          decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: RgColors.dividerCard)) : null),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
            if (number != null)
              SizedBox(width: 18, child: Text('$number', style: RgText.titleList.copyWith(fontWeight: FontWeight.w800))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ValueListenableBuilder(
                  valueListenable: readItems,
                  builder: (context, _, _) => RgRowHead(
                    chip: RgChip(n.sourceLabel, source: n.source),
                    meta: n.isHot
                        ? [?n.reaction, relativeKo(n.publishedAt, now)].join(' · ')
                        : [relativeKo(n.publishedAt, now), if (n.related.isNotEmpty) '관련 ${n.related.length}', ?n.reaction].join(' · '),
                    isNew: isNew(newsKey(n), n.publishedAt),
                  ),
                ),
                const SizedBox(height: RgSpace.s6),
                // 읽은 소식은 제목을 한 단계 옅게(150ms)
                AnimatedDefaultTextStyle(
                  duration: RgMotion.of(context, RgMotion.fast),
                  style: RgText.titleList.copyWith(
                    fontSize: 15.5,
                    height: 22 / 15.5,
                    fontWeight: read ? FontWeight.w500 : FontWeight.w600,
                    color: read ? RgColors.textBody : RgColors.textPrimary,
                  ),
                  child: KeepAllText(n.titleKo ?? n.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                if (one != null) ...[
                  const SizedBox(height: RgSpace.s2),
                  Text(one, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.meta.copyWith(fontSize: 13.5, color: RgColors.textSecondary)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
