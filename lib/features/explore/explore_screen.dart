import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_states.dart';
import 'official_news.dart';

// S04 탐색 (HANDOFF 7.6). 오늘은 홈에서 보이므로 뺀다.
// 위쪽 「논문 | 공식 소식」 칸(PROPOSALS P9 A안의 첫 단계, 브랜치 feature/official-news).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _req = Reloadable(() async {
    final today = await repository.todayKey();
    return [
      for (final d in await repository.listDigests())
        if (d.dateKey != today) d,
    ];
  });

  var _tab = 0; // 0 논문, 1 공식 소식
  final _pages = PageController();

  @override
  void dispose() {
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
                  child: Semantics(header: true, child: Text('탐색', style: RgText.titleDetail)),
                ),
              ),
            ),
          ),
          _Tabs(
            labels: const ['논문', '공식 소식'],
            selected: _tab,
            onTap: (i) => _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _tab = i),
              children: [_papers(), const OfficialNewsSection()],
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
          final months = groupByMonth(snap.data ?? const []);
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s16, RgSpace.gutterText, 0),
                child: Text('지난 날짜의 연구를 다시 볼 수 있어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
              ),
              if (snap.hasError) ...[
                const SizedBox(height: RgSpace.s28),
                RgErrorCard(error: snap.error, onRetry: _req.reload),
              ] else if (snap.connectionState != ConnectionState.done)
                const RgSkeleton(
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
                ),
              for (final (i, (month, days)) in months.indexed) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    RgSpace.gutterText,
                    i == 0 ? RgSpace.s28 : RgSpace.s32,
                    RgSpace.gutterText,
                    RgSpace.s12,
                  ),
                  child: Semantics(header: true, child: Text(month, style: RgText.titleSection)),
                ),
                RgCard(
                  child: Column(
                    children: [for (final (j, d) in days.indexed) _DayRow(day: d, last: j == days.length - 1)],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.last});
  final Digest day;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final published = day.status == 'published';
    final sub = switch (day.status) {
      'published' => '${day.paperCount}편 · ${topicLabels[day.primaryTopic] ?? '기타'}${day.paperCount > 1 ? ' 외' : ''}',
      'delayed' => '수집이 늦어지고 있어요${day.lastSuccessAt == null ? '' : ' · 마지막 정상 수집 ${kstTime(day.lastSuccessAt!)}'}',
      _ => '이날은 올라온 논문이 없어요',
    };
    return RgListRow(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      crossAxisAlignment: CrossAxisAlignment.center,
      showDivider: !last,
      onTap: published ? () => context.go('/explore/${day.dateKey}') : null,
      trailing: switch (day.status) {
        'published' => const Padding(
          padding: EdgeInsets.only(left: RgSpace.s4), // 시안 간격 12 = 행 기본 8 + 4
          child: RgIcon('chevron-right', size: 20, color: RgColors.textTertiary),
        ),
        'delayed' => const Padding(
          padding: EdgeInsets.only(left: RgSpace.s4),
          child: RgBadge(label: '지연'),
        ),
        _ => null,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeepAllText(
            koreanDate(day.date), // 큰 글자에서 「토 / 요일」로 갈라지지 않게
            style: day.status == 'empty' ? RgText.titleList.copyWith(color: RgColors.textSecondary) : RgText.titleList,
          ),
          const SizedBox(height: RgSpace.s2),
          Text(sub, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        ],
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

// 출처별 가로 탭(P9 시안): 글자 + 선택된 칸 아래 2pt 선, 전체 아래 구분선. 칸이 늘면 가로로 넘긴다.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.selected, required this.onTap});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onTap;

  // 하단 탭바처럼 화면 틀이라 글자 배율은 1.35배에서 멈춘다(ChromeTextScale)
  @override
  Widget build(BuildContext context) {
    return ChromeTextScale(child: _row());
  }

  Widget _row() {
    return Container(
      margin: const EdgeInsets.only(top: RgSpace.s4),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.borderDefault))),
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
      child: Row(spacing: RgSpace.s20, children: [
        for (final (i, label) in labels.indexed)
          Semantics(
            button: true,
            selected: i == selected,
            child: RgPressable(
              onTap: () => onTap(i),
              child: Container(
                constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == selected ? RgColors.textPrimary : Colors.transparent, width: 2)),
                ),
                child: Text(
                  label,
                  style: RgText.titleList.copyWith(
                    fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                    color: i == selected ? RgColors.textPrimary : RgColors.textSecondary,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
