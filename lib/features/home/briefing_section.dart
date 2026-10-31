import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  const BriefingSection({super.key, required this.news, required this.paperCount, this.paperKey, this.updatesKey});
  final List<OfficialNews>? news; // null = 아직 불러오는 중
  final int paperCount;
  final GlobalKey? paperKey, updatesKey; // 배지 「새 논문」「바뀐 도구」가 스크롤해 갈 홈 칸(브리핑 바깥)

  @override
  State<BriefingSection> createState() => _BriefingSectionState();
}

class _BriefingSectionState extends State<BriefingSection> {
  var _open = false;
  final _storiesKey = GlobalKey(), _talkKey = GlobalKey();

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
        const SizedBox(height: RgSpace.s4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          // 배지를 누르면 그 칸으로 스크롤한다. 홈 화제 카드가 없으면(화제가 모두 주요 소식에 오름) 탐색 개발자 화제로
          child: Wrap(spacing: RgSpace.s6, children: [
            if (b.stories.isNotEmpty) _Pill('주요 소식', '${b.stories.length}', onTap: () => revealSection(_storiesKey)),
            if (b.hotCount > 0)
              _Pill('개발자 화제', '${b.hotCount}', onTap: () {
                if (b.talk.isEmpty) {
                  openExplore(context, const ExploreJump(1, hot: true));
                } else {
                  revealSection(_talkKey);
                }
              }),
            if (widget.paperCount > 0) _Pill('새 논문', '${widget.paperCount}편', onTap: () => revealSection(widget.paperKey)),
            if (b.updates > 0) _Pill('바뀐 도구', '${b.updates}', onTap: () => revealSection(widget.updatesKey)),
          ]),
        ),
      ],
      if (b != null && b.stories.isNotEmpty) ...[
        const SizedBox(height: RgSpace.s12), // 배지 누르는 영역(44)이 위아래로 8씩 더 차지한다
        RgCard(
          key: _storiesKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s20, RgSpace.s4),
              // 「중요한 순」은 기준이 안 보였다(피드백 3번): 제목 아래 한 줄로 고른 기준(importance)을 밝힌다
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s2, children: [
                Semantics(header: true, child: Text(b.stale ? '최근 소식' : b.wide ? '최근 주요 소식' : '오늘의 주요 소식', style: RgText.titleCard)),
                if (!b.stale)
                  KeepAllText('큰 연구소 발표·모델 출시·여러 곳에서 다룬 소식을 먼저 골랐어요', style: RgText.caption.copyWith(fontSize: 12.5, color: RgColors.textSecondary)),
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
                        child: RgIcon('chevron-right', size: 16, color: RgColors.textBody),
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
          key: _talkKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.s20, RgSpace.s18, RgSpace.s20, RgSpace.s4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s2, children: [
                Semantics(header: true, child: Text('개발자 화제', style: RgText.titleCard)),
                KeepAllText('Hacker News에서 개발자 추천을 많이 받은 글', style: RgText.caption.copyWith(fontSize: 12.5, color: RgColors.textSecondary)),
              ]),
            ),
            // 화제는 「얼마나 뜨거운가 + 무슨 일인가」(피드백 5번): 점수를 순위 자리에, 요약은 탐색에서
            for (final (i, n) in b.talk.take(2).indexed) HotRow(news: n, now: now, divider: i > 0, summary: false),
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
                    Flexible(child: Text('개발자 화제 ${b.hotCount}건 모두 보기', textAlign: TextAlign.center, style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textBody))),
                    RgIcon('chevron-right', size: 16, color: RgColors.textBody),
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

// 브리핑 배지: 누르면 그 칸으로(revealSection). 보이는 알약은 28, 누르는 영역은 위아래로 늘려 44
class _Pill extends StatelessWidget {
  const _Pill(this.label, this.value, {required this.onTap});
  final String label, value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: RgPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
        child: Center(
          widthFactor: 1,
          child: Container(
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
          ),
        ),
      ),
    ),
  );
}

// 홈 배지 → 그 칸이 상태 표시줄 아래(8pt 띄워) 오도록 부드럽게 스크롤(260ms, 동작 줄이기면 바로).
// 홈 목록(ListView)은 먼 칸도 미리 그려 둔다(home_screen.dart scrollCacheExtent). 그래도 칸이 없으면(아직 불러오는 중) 그대로 둔다.
Future<void> revealSection(GlobalKey? key) async {
  final ctx = key?.currentContext;
  if (ctx == null) return;
  final d = RgMotion.of(ctx, const Duration(milliseconds: 260));
  final pos = Scrollable.of(ctx).position;
  final top = MediaQuery.paddingOf(ctx).top + RgSpace.s8;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null) return;
  final viewport = RenderAbstractViewport.of(box);
  final target = (viewport.getOffsetToReveal(box, 0).offset - top).clamp(pos.minScrollExtent, pos.maxScrollExtent);
  if (d == Duration.zero) {
    pos.jumpTo(target);
  } else {
    await pos.animateTo(target, duration: d, curve: RgMotion.curve);
  }
}

// 브리핑 한 줄: (번호) · 회사 칩 · 「6시간 전」 · 새 글 점 → 제목 두 줄 → 한 줄 요약 → 「같은 소식 N곳」. 누르면 소식 상세.
// 위계(디자인 피드백 2026-10-31 4번): 칩 > 제목 > 요약 > 보조. 「관련 N」은 뜻이 안 보여 요약 아래 「같은 소식 N곳」으로 뺐다.
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s10, children: [
            // 순위 숫자는 작게, 1위만 진하게(피드백 8번과 같은 규칙)
            if (number != null)
              SizedBox(
                width: 18,
                child: Text('$number', style: RgText.meta.copyWith(height: 22 / 14, fontWeight: FontWeight.w700, color: number == 1 ? RgColors.textPrimary : RgColors.textTertiary)),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ValueListenableBuilder(
                  valueListenable: readItems,
                  builder: (context, _, _) => RgRowHead(
                    chip: RgChip(n.sourceLabel, source: n.source),
                    meta: [relativeKo(n.publishedAt, now), ?n.reaction].join(' · '),
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
                if (n.related.isNotEmpty) ...[
                  const SizedBox(height: RgSpace.s6),
                  Text('같은 소식 ${n.related.length}곳', style: RgText.caption.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500, color: RgColors.textSecondary)),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
