import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_states.dart';

// S01 오늘의 연구 (HANDOFF 7.1). 로딩·오류·지연·빈 상태는 8.1.
// S04에서 지난 날짜로 들어오면 같은 레이아웃에 뒤로 버튼만 더한다(7.6).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.date});
  final String? date; // YYYY-MM-DD, null = 오늘

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final _req = Reloadable(_load);
  String? _topic; // null = 전체

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  // 오늘이 비었으면(0편이거나 아직 없음) 가장 최근 정상 다이제스트를 함께 불러온다(iOS QA P4).
  // 다이제스트는 HF 전날분이라 일·월요일은 늘 비어 홈이 이틀 연속 빈 화면이 됐다.
  Future<(Digest?, Digest?)> _load() async {
    final digest = await repository.getDigest(widget.date);
    if (widget.date != null || (digest != null && digest.status != 'empty')) return (digest, null);
    try {
      final today = await repository.todayKey();
      final last = (await repository.listDigests())
          .where((d) => d.status == 'published' && d.dateKey.compareTo(today) < 0)
          .firstOrNull; // 최신순
      return (digest, last == null ? null : await repository.getDigest(last.dateKey));
    } catch (_) {
      return (digest, null); // 못 불러오면 지금처럼 빈 안내만
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final children = switch (snap) {
            AsyncSnapshot(hasError: true) => [
              const SizedBox(height: RgSpace.s20),
              RgErrorCard(error: snap.error, onRetry: _req.reload),
            ],
            AsyncSnapshot(connectionState: ConnectionState.done) => null,
            _ => const [_HomeSkeleton()],
          };
          return ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              _topBar(context),
              ...?children,
              if (children == null)
                ValueListenableBuilder(
                  valueListenable: bookmarks,
                  builder: (context, saved, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _body(snap.data?.$1, snap.data?.$2, saved),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _topBar(BuildContext context) => ChromeTextScale(
    child: SizedBox(
      height: RgSpace.topBar,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.date == null ? RgSpace.gutterText : RgSpace.gutterCard),
        child: Row(
          spacing: RgSpace.s12,
          children: [
            if (widget.date != null)
              RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => context.pop()),
            Text('ROOTGIST', style: RgText.wordmark),
          ],
        ),
      ),
    ),
  );

  // fallback: 오늘이 비었을 때 대신 보여 줄 가장 최근 다이제스트(헤드라인은 오늘 기준 그대로).
  List<Widget> _body(Digest? digest, Digest? fallback, Map<String, Bookmark> saved) {
    final view = HomeView((fallback ?? digest)?.papers ?? const [], _topic);
    final status = digest?.status;
    final headline = switch (status) {
      'delayed' => '오늘 논문을 아직 모으는 중이에요',
      'empty' when fallback != null => '오늘은 새 논문이 없어요',
      _ when fallback != null || view.total == 0 => '아직 올라온 논문이 없어요',
      _ => '새 논문 ${view.total}편이 올라왔어요',
    };
    final date = digest?.date ?? DateTime.now();
    // 일·월요일 다이제스트는 HF 토·일요일분(arXiv 발표 없음)
    final weekend = status == 'empty' && (date.weekday == DateTime.sunday || date.weekday == DateTime.monday);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, 0),
        child: Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${keepAll(koreanDate(date))}\n', // 큰 글자에서 「25 / 일」로 갈라지지 않게
                  style: const TextStyle(color: RgColors.textTertiary),
                ),
                TextSpan(text: keepAll(headline)),
              ],
            ),
            style: RgText.displayHome,
            semanticsLabel: '${koreanDate(date)} $headline', // 화면 읽기에는 숨은 문자 없이
          ),
        ),
      ),
      if (fallback != null) ...[
        const SizedBox(height: RgSpace.s20),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: KeepAllText(
            [if (weekend) '주말에는 새 논문이 발표되지 않아요.', '가장 최근인 ${koreanDate(fallback.date)} 연구를 보여 드려요.'].join(' '),
            style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
          ),
        ),
      ],
      if (view.chips.isNotEmpty) ...[
        // 칩 시각 높이 36, 터치 44(더 큰 텍스트에서는 늘어난다). 시안의 위아래 20은 시각 기준이라 4씩 덜어낸다.
        const SizedBox(height: RgSpace.s16),
        SizedBox(
          height: RgFilterChip.touchHeight(context),
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
        _FeaturedCard(
          paper: p,
          saved: saved.containsKey(p.id),
          label: fallback == null ? '오늘의 주요 연구' : '${fallback.date.month}월 ${fallback.date.day}일 주요 연구',
        ),
      ],
      // 8.1 당일 지연: 추천 카드 자리에 마지막 수집 시각 안내.
      if (status == 'delayed') ...[
        const SizedBox(height: RgSpace.s20),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: KeepAllText(
            [if (digest?.lastSuccessAt case final t?) '마지막 정상 수집 ${kstDateTime(t)}.', '모이는 대로 이 화면에 올라와요.'].join(' '),
            style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
          ),
        ),
      ],
      if (view.list.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s28, RgSpace.gutterText, RgSpace.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: RgSpace.s8,
            children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(fallback == null ? '새로 올라온 연구' : '그날 올라온 연구', style: RgText.titleSection),
                ),
              ),
              Text('${view.list.length}편', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
            ],
          ),
        ),
        RgCard(
          child: Column(
            children: [
              for (final (i, p) in view.list.indexed)
                RgListRow(
                  showDivider: i < view.list.length - 1,
                  onTap: () => context.push('/paper/${p.id}'),
                  trailing: RgBookmarkButton(
                    saved: saved.containsKey(p.id),
                    variant: RgCircleVariant.plain,
                    onTap: () => toggleBookmark(p.id, p.title),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_topic == null && p.topicLabel != null) ...[
                        Text(p.topicLabel!, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                        const SizedBox(height: RgSpace.s4),
                      ],
                      KeepAllText(p.title, style: RgText.titleList),
                      const SizedBox(height: RgSpace.s4),
                      KeepAllText('${p.date} · ${p.authors}', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

// 헤드라인 2줄 + 칩 + 추천 카드 + 목록 행 모양.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return RgSkeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, 0),
            child: Column(
              children: [RgBar(lineHeight: 39, widthFactor: 0.5), RgBar(lineHeight: 39, widthFactor: 0.85)],
            ),
          ),
          const SizedBox(height: RgSpace.s20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
            child: Row(
              spacing: RgSpace.s8,
              children: [
                for (final w in const [56.0, 88.0, 80.0])
                  Container(
                    width: w,
                    height: 36,
                    decoration: BoxDecoration(
                      color: RgColors.fillNeutral,
                      borderRadius: BorderRadius.circular(RgRadius.pill),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RgSpace.s20),
          const RgCard(
            padding: EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
            child: Column(
              spacing: RgSpace.s6,
              children: [
                RgBar(lineHeight: 24, widthFactor: 0.4),
                RgBar(lineHeight: 29, widthFactor: 0.9),
                RgBar(lineHeight: 18, widthFactor: 0.45),
                SizedBox(height: RgSpace.s8),
                RgBar(lineHeight: 23),
                RgBar(lineHeight: 23, widthFactor: 0.7),
                SizedBox(height: RgSpace.s12),
                RgBar(lineHeight: 48, barHeight: 48),
              ],
            ),
          ),
          const SizedBox(height: RgSpace.s28 + 25 + RgSpace.s12),
          const RgSkeletonRows(count: 2),
        ],
      ),
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.paper, required this.saved, required this.label});
  final PaperItem paper;
  final bool saved;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bullets = paper.keyPoints.take(2); // G11
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 큰 글자에서 한 줄에 안 들어가면 다음 줄로
          Wrap(
            spacing: RgSpace.s8,
            runSpacing: RgSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (paper.topicLabel != null) RgBadge(label: paper.topicLabel!),
              Text(label, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
            ],
          ),
          const SizedBox(height: RgSpace.s12),
          KeepAllText(paper.title, style: RgText.titleFeatured),
          const SizedBox(height: RgSpace.s6),
          KeepAllText('${paper.authors} · ${paper.date}', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
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
                        // 첫 줄(행간 23 × 글자 배율)의 가운데. 고정 10이면 큰 글자에서 점이 위로 뜬다(에뮬레이터 QA)
                        margin: EdgeInsets.only(top: (MediaQuery.textScalerOf(context).scale(23) - 4) / 2),
                        decoration: const BoxDecoration(color: RgColors.textBody, shape: BoxShape.circle),
                      ),
                      Expanded(
                        // 실제 핵심 내용은 3~5줄짜리 문장이라 카드가 길어진다(2026-10-22 실데이터). 항목당 2줄, 전문은 S02.
                        child: KeepAllText(
                          b,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: RgText.bodySummary.copyWith(color: RgColors.textBody),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
          const SizedBox(height: RgSpace.s18),
          Row(
            spacing: RgSpace.s8,
            children: [
              Expanded(
                child: RgPrimaryButton(label: '자세히 읽기', onTap: () => context.push('/paper/${paper.id}')),
              ),
              RgBookmarkButton(saved: saved, size: 48, onTap: () => toggleBookmark(paper.id, paper.title)),
            ],
          ),
        ],
      ),
    );
  }
}

// 필터·주요 연구 선정 규칙(7.1, G6, G9, G14). 화면과 떼어 테스트한다.
class HomeView {
  HomeView(List<PaperItem> papers, String? topic) : total = papers.length {
    chips = [
      for (final t in topicLabels.keys)
        if (papers.any((p) => p.ready && p.topic == t)) t,
    ];
    final shown = topic == null ? papers : papers.where((p) => p.ready && p.topic == topic).toList();
    featured = shown.where((p) => p.ready && p.keyPoints.isNotEmpty).firstOrNull;
    list = [
      for (final p in shown)
        if (p != featured) p,
    ];
  }

  final int total; // 헤드라인 편수는 필터와 무관
  late final List<String> chips;
  late final PaperItem? featured;
  late final List<PaperItem> list;
}
