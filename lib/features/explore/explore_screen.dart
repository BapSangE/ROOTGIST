import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_states.dart';
import '../../data/unread.dart';
import '../../design/widgets/rg_segmented.dart';
import '../home/home_screen.dart';
import 'official_news.dart';
import 'trending_models.dart';

// S04 탐색 (HANDOFF 7.6). 위쪽 「논문 | 공식 소식 | 모델」 칸(PROPOSALS P9 A안). 옆으로 밀어 넘긴다.
// 논문 칸: 오늘의 논문 전체(홈은 3편만 미리 보여 준다) → 아래로 지난 논문을 달마다. 이번 달은 펼치고 지난달부터는 접는다.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _req = Reloadable(() async {
    final (digest, fallback) = await loadDigest();
    final shown = (fallback ?? digest)?.dateKey;
    final today = await repository.todayKey();
    return (
      digest,
      fallback,
      [
        for (final d in await repository.listDigests())
          if (d.dateKey != today && d.dateKey != shown) d,
      ],
    );
  });

  // 「공식 소식」 칸 이름 옆 새 글 점
  final _news = repository.listOfficialNews().catchError((_) => <OfficialNews>[]);
  late var _tab = exploreTab.value = exploreJump.value?.tab ?? 0; // 0 논문, 1 공식 소식, 2 모델
  late final _pages = PageController(initialPage: _tab);
  final _open = <String>{}; // 펼친 지난달

  // 홈 「더 보기」 → 그 칸으로
  void _jump() {
    final j = exploreJump.value;
    if (j == null || !_pages.hasClients) return;
    if (j.animate) {
      _pages.animateToPage(j.tab, duration: RgMotion.base, curve: RgMotion.curve);
    } else {
      _pages.jumpToPage(j.tab);
    }
  }

  @override
  void initState() {
    super.initState();
    exploreJump.addListener(_jump);
  }

  @override
  void dispose() {
    exploreJump.removeListener(_jump);
    _req.dispose();
    _pages.dispose();
    super.dispose();
  }

  // 위 칸을 누르거나 옆으로 밀어 넘긴다(실기기 QA 요청). 제목·칸은 고정, 아래 목록만 넘어간다.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChromeTextScale(
            child: SizedBox(
              height: RgSpace.topBar,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Semantics(header: true, child: Text('탐색', style: RgText.display)),
                ),
              ),
            ),
          ),
          FutureBuilder(
            future: _news,
            builder: (context, snap) => ValueListenableBuilder(
              valueListenable: readItems,
              // 알약 세그먼트(레퍼런스 006). 공식 소식 안 「발표 | 업데이트」는 밑줄 탭으로 위계를 나눈다.
              builder: (context, _, _) => Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, RgSpace.s4),
                child: ChromeTextScale(
                  child: RgSegmented(
                    options: const [(0, '논문'), (1, '소식'), (2, '모델')],
                    value: _tab,
                    dots: {if (hasNewNews(snap.data ?? const [])) 1},
                    onChanged: (i) => _pages.animateToPage(i, duration: RgMotion.base, curve: RgMotion.curve),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            // 옆으로 밀기는 쉘이 맡는다(홈 → 탐색 칸들 → 공식 소식 발표·업데이트 → 보관함 → 설정이 한 줄로 이어진다).
            // PageView가 끌기를 먼저 가져가면 모델 칸 끝에서 보관함으로, 공식 소식 안에서 업데이트로 넘어가지 못한다.
            child: PageView(
              controller: _pages,
              physics: const NeverScrollableScrollPhysics(),
              allowImplicitScrolling: true, // 옆 칸을 미리 만들어 두어 넘기자마자 내용이 보인다
              onPageChanged: (i) => setState(() => _tab = exploreTab.value = i),
              children: [_papers(), const OfficialNewsSection(), const TrendingModelsSection()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _papers() {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          if (snap.hasError) {
            return ListView(children: [const SizedBox(height: RgSpace.s28), RgErrorCard(error: snap.error, onRetry: _req.reload)]);
          }
          if (snap.connectionState != ConnectionState.done) {
            return const RgSkeleton(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s28, RgSpace.gutterText, RgSpace.s12),
                    child: RgBar(lineHeight: 25, widthFactor: 0.3),
                  ),
                  RgSkeletonRows(count: 4),
                ],
              ),
            );
          }
          final (digest, fallback, past) = snap.data!;
          final shown = fallback ?? digest;
          final months = groupByMonth(past);
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              if (shown != null && shown.papers.isNotEmpty) ...[
                SectionTitle(fallback == null ? '오늘의 논문' : '${shown.date.month}월 ${shown.date.day}일 논문', count: '${shown.papers.length}편'),
                DigestPapers(digest: digest, fallback: fallback, title: '그 밖의 논문'),
              ],
              if (months.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s36, RgSpace.gutterText, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
                    Semantics(header: true, child: Text('지난 논문', style: RgText.titleSection)),
                    Text('날짜를 누르면 그날의 논문을 볼 수 있어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
                  ]),
                ),
              for (final (i, (month, days)) in months.indexed) ...[
                // 이번 달(맨 위)은 늘 펼친다. 지난달부터는 눌러서 펼친다.
                if (i == 0 || _open.contains(month)) ...[
                  _MonthHeader(month: month, count: days.length, open: true, onTap: i == 0 ? null : () => setState(() => _open.remove(month))),
                  RgCard(
                    child: Column(
                      children: [for (final (j, d) in days.indexed) _DayRow(day: d, last: j == days.length - 1)],
                    ),
                  ),
                ] else
                  _MonthHeader(month: month, count: days.length, open: false, onTap: () => setState(() => _open.add(month))),
              ],
            ],
          );
        },
      ),
    );
  }
}

// 달 묶음 머리: 「2026년 9월 · 22일치」. 접힌 달은 누르면 펼친다.
class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.count, required this.open, this.onTap});
  final String month;
  final int count;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s20, RgSpace.gutterText, RgSpace.s8),
      child: Row(spacing: RgSpace.s8, children: [
        Expanded(child: Semantics(header: true, child: Text(month, style: RgText.titleList.copyWith(fontWeight: FontWeight.w700)))),
        Text('$count일치', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        if (onTap != null)
          Transform.rotate(
            angle: open ? -1.5708 : 1.5708, // 펼침 ▲ / 접힘 ▼
            child: const RgIcon('chevron-right', size: 16, color: RgColors.textSecondary),
          ),
      ]),
    );
    if (onTap == null) return row;
    return Semantics(button: true, expanded: open, child: RgPressable(onTap: onTap, child: row));
  }
}

// 지난 날짜 한 줄: 왼쪽에 큰 날짜 숫자 + 요일, 오른쪽에 편수·주제(또는 지연·없음).
class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.last});
  final Digest day;
  final bool last;

  static const _weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

  @override
  Widget build(BuildContext context) {
    final published = day.status == 'published';
    final empty = day.status == 'empty';
    final (title, sub) = switch (day.status) {
      'published' => ('${day.paperCount}편', '${topicLabels[day.primaryTopic] ?? '기타'}${day.paperCount > 1 ? ' 외' : ''}'),
      'delayed' => ('수집이 늦어지고 있어요', day.lastSuccessAt == null ? null : '마지막 정상 수집 ${kstTime(day.lastSuccessAt!)}'),
      _ => ('올라온 논문이 없어요', null),
    };
    final ink = empty ? RgColors.textSecondary : RgColors.textPrimary;
    return Semantics(
      label: koreanDate(day.date),
      child: RgListRow(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
        crossAxisAlignment: CrossAxisAlignment.center,
        showDivider: !last,
        onTap: published ? () => context.go('/explore/${day.dateKey}') : null,
        trailing: switch (day.status) {
          'published' => const Padding(
            padding: EdgeInsets.only(left: RgSpace.s4), // 시안 간격 12 = 행 기본 8 + 4
            child: RgIcon('chevron-right', size: 20, color: RgColors.textTertiary),
          ),
          'delayed' => const Padding(padding: EdgeInsets.only(left: RgSpace.s4), child: RgTag(label: '지연')),
          _ => null,
        },
        child: Row(spacing: RgSpace.s16, children: [
          ExcludeSemantics(
            child: SizedBox(
              width: 46,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${day.date.day}', style: RgText.titleDetail.copyWith(fontSize: 24, height: 1.1, fontWeight: FontWeight.w800, color: ink)),
                Text(_weekdays[day.date.weekday - 1], style: RgText.caption.copyWith(fontSize: 12, color: RgColors.textSecondary)),
              ]),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeepAllText(title, style: RgText.titleList.copyWith(color: ink)),
              if (sub != null) ...[
                const SizedBox(height: RgSpace.s2),
                Text(sub, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

// 최신순 날짜 목록 → [(「YYYY년 M월」, 그 달 날짜들)], 순서 유지.
List<(String, List<Digest>)> groupByMonth(List<Digest> days) {
  final out = <(String, List<Digest>)>[];
  for (final d in days) {
    final label = '${d.date.year}년 ${d.date.month}월';
    if (out.isEmpty || out.last.$1 != label) out.add((label, []));
    out.last.$2.add(d);
  }
  return out;
}
