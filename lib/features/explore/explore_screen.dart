import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_states.dart';

// S04 탐색 (HANDOFF 7.6). 오늘은 홈에서 보이므로 뺀다.
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
          final months = groupByMonth(snap.data ?? const []);
          return ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              SizedBox(
                height: RgSpace.topBar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(header: true, child: Text('탐색', style: RgText.titleDetail)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, 0),
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
          Text(
            koreanDate(day.date),
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
