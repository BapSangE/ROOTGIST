import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';

// S01 오늘의 연구 (HANDOFF 7.1). 로딩·오류·지연 카드는 M3.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _digest = repository.today();
  String? _topic; // null = 전체

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _digest,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const SizedBox.shrink();
        return ValueListenableBuilder(
          valueListenable: bookmarks,
          builder: (context, saved, _) => _body(snap.data, saved),
        );
      },
    );
  }

  Widget _body(Digest? digest, Set<String> saved) {
    final view = HomeView(digest?.papers ?? const [], _topic);
    final status = digest?.status;
    final headline = switch (status) {
      'delayed' => '오늘 논문을 아직 모으는 중이에요',
      _ when view.total == 0 => '아직 올라온 논문이 없어요',
      _ => '새 논문 ${view.total}편이 올라왔어요',
    };
    final date = digest?.date ?? DateTime.now();

    return ListView(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
      children: [
        SizedBox(
          height: RgSpace.topBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
            child: Align(alignment: Alignment.centerLeft, child: Text('ROOTGIST', style: RgText.wordmark)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, 0),
          child: Semantics(
            header: true,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: '${koreanDate(date)}\n', style: const TextStyle(color: RgColors.textTertiary)),
              TextSpan(text: keepAll(headline)),
            ]), style: RgText.displayHome),
          ),
        ),
        if (view.chips.isNotEmpty) ...[
          // 칩 시각 높이 36, 터치 44. 시안의 위아래 20은 시각 기준이라 4씩 덜어낸다.
          const SizedBox(height: RgSpace.s16),
          SizedBox(
            height: RgSpace.minTouch,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
              itemCount: view.chips.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: RgSpace.s8),
              itemBuilder: (_, i) {
                final topic = i == 0 ? null : view.chips[i - 1];
                return RgFilterChip(
                  label: topic == null ? '전체' : topicLabels[topic]!,
                  selected: _topic == topic,
                  onTap: () => setState(() => _topic = topic),
                );
              },
            ),
          ),
        ],
        if (view.featured case final p?) ...[
          SizedBox(height: view.chips.isEmpty ? RgSpace.s20 : RgSpace.s16),
          _FeaturedCard(paper: p, saved: saved.contains(p.id)),
        ],
        if (view.list.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s28, RgSpace.gutterText, RgSpace.s12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              spacing: RgSpace.s8,
              children: [
                Semantics(header: true, child: Text('새로 올라온 연구', style: RgText.titleSection)),
                Text('${view.list.length}편', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
              ],
            ),
          ),
          RgCard(
            child: Column(children: [
              for (final (i, p) in view.list.indexed)
                RgListRow(
                  showDivider: i < view.list.length - 1,
                  onTap: () => context.push('/paper/${p.id}'),
                  trailing: RgBookmarkButton(
                    saved: saved.contains(p.id),
                    variant: RgCircleVariant.plain,
                    onTap: () => toggleBookmark(p.id),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (_topic == null && p.topicLabel != null) ...[
                      Text(p.topicLabel!, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                      const SizedBox(height: RgSpace.s4),
                    ],
                    Text(keepAll(p.title), style: RgText.titleList),
                    const SizedBox(height: RgSpace.s4),
                    Text('${p.date} · ${p.authors}', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                  ]),
                ),
            ]),
          ),
        ],
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.paper, required this.saved});
  final PaperItem paper;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final bullets = paper.keyPoints.take(2); // G11
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(spacing: RgSpace.s8, children: [
            if (paper.topicLabel != null) RgBadge(label: paper.topicLabel!),
            Text('오늘의 주요 연구', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
          ]),
          const SizedBox(height: RgSpace.s12),
          Text(keepAll(paper.title), style: RgText.titleFeatured),
          const SizedBox(height: RgSpace.s6),
          Text('${paper.authors} · ${paper.date}', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
          if (bullets.isNotEmpty) ...[
            const SizedBox(height: RgSpace.s14),
            Column(
              spacing: RgSpace.s6,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final b in bullets)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: RgSpace.s10,
                    children: [
                      Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(top: RgSpace.s10),
                        decoration: const BoxDecoration(color: RgColors.textBody, shape: BoxShape.circle),
                      ),
                      Expanded(child: Text(keepAll(b), style: RgText.bodySummary.copyWith(color: RgColors.textBody))),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: RgSpace.s18),
          Row(spacing: RgSpace.s8, children: [
            Expanded(child: RgPrimaryButton(label: '자세히 읽기', onTap: () => context.push('/paper/${paper.id}'))),
            RgBookmarkButton(saved: saved, size: 48, onTap: () => toggleBookmark(paper.id)),
          ]),
        ],
      ),
    );
  }
}

// 필터·주요 연구 선정 규칙(7.1, G6, G9, G14). 화면과 떼어 테스트한다.
class HomeView {
  HomeView(List<PaperItem> papers, String? topic) : total = papers.length {
    chips = [for (final t in topicLabels.keys) if (papers.any((p) => p.ready && p.topic == t)) t];
    final shown = topic == null ? papers : papers.where((p) => p.ready && p.topic == topic).toList();
    featured = shown.where((p) => p.ready && p.keyPoints.isNotEmpty).firstOrNull;
    list = [for (final p in shown) if (p != featured) p];
  }

  final int total; // 헤드라인 편수는 필터와 무관
  late final List<String> chips;
  late final PaperItem? featured;
  late final List<PaperItem> list;
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
String koreanDate(DateTime d) => '${d.month}월 ${d.day}일 ${_weekdays[d.weekday - 1]}요일';
