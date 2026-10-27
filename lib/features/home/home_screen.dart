import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_states.dart';
import '../common/item_actions.dart';
import '../explore/official_news.dart';
import '../explore/trending_models.dart';

// S01 홈 (HANDOFF 7.1, 실기기 QA 요청으로 하이라이트 허브로): 오늘의 논문 3편 → 공식 발표 → 업데이트 → 주목받는 모델.
// 묶음마다 「더 보기」는 탐색의 그 칸으로. 로딩·오류·지연·빈 상태는 8.1.
// S04에서 지난 날짜로 들어오면(date) 그날의 논문 전체를 칩과 함께 보여 주고 뒤로 버튼을 더한다(7.6).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.date});
  final String? date; // YYYY-MM-DD, null = 오늘(홈)

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// 오늘이 비었으면(0편이거나 아직 없음) 가장 최근 정상 다이제스트를 함께 불러온다(iOS QA P4).
// 다이제스트는 HF 전날분이라 일·월요일은 늘 비어 홈이 이틀 연속 빈 화면이 됐다. 탐색 논문 칸도 같은 규칙.
Future<(Digest?, Digest?)> loadDigest([String? date]) async {
  final digest = await repository.getDigest(date);
  if (date != null || (digest != null && digest.status != 'empty')) return (digest, null);
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

// 홈 하이라이트에 올릴 소식·모델. 못 불러오면 그 묶음만 숨긴다(논문이 앱의 중심).
// 공식 발표·업데이트는 오늘(KST 배치일) 기준 7일 안의 것만: 며칠씩 비는 날에 오래된 글이 걸려 있지 않게.
Future<(List<OfficialNews>, List<TrendingModel>)> _loadExtras() async {
  final news = await repository.listOfficialNews().catchError((_) => <OfficialNews>[]);
  final models = await repository.listTrendingModels().catchError((_) => <TrendingModel>[]);
  final today = await repository.todayKey().then(DateTime.parse).catchError((_) => DateTime.now());
  final cutoff = today.subtract(const Duration(days: 7));
  return ([for (final n in news) if (n.publishedAt.isAfter(cutoff)) n], models);
}

class _HomeScreenState extends State<HomeScreen> {
  late final _req = Reloadable(() => loadDigest(widget.date));
  late final _extras = widget.date == null ? _loadExtras() : null;

  @override
  void initState() {
    super.initState();
    _extras; // 논문과 함께 바로 불러오기 시작한다
  }

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
          final children = switch (snap) {
            AsyncSnapshot(hasError: true) => [
              const SizedBox(height: RgSpace.s20),
              RgErrorCard(error: snap.error, onRetry: _req.reload),
            ],
            AsyncSnapshot(connectionState: ConnectionState.done) => null,
            _ => const [_HomeSkeleton()],
          };
          final (digest, fallback) = snap.data ?? (null, null);
          return ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              _topBar(context),
              ...?children,
              if (children == null) ...[
                _headline(digest, fallback),
                DigestPapers(digest: digest, fallback: fallback, limit: widget.date == null ? 3 : null, pastDay: widget.date != null),
                if (widget.date == null) ...[
                  if ((fallback ?? digest)?.papers.isNotEmpty ?? false)
                    MoreLink(label: '논문 더 보기', onTap: () => openExplore(context, const ExploreJump(0))),
                  FutureBuilder(future: _extras, builder: (context, s) => _extrasSection(context, s.data)),
                ],
              ],
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
        // 뒤로 화살표는 원 없이 16pt 왼쪽으로 당겨져 있어(RgBackButton), 워드마크도 그만큼 당긴다
        child: Row(
          children: [
            if (widget.date != null) RgBackButton(onTap: () => context.pop()),
            Transform.translate(
              offset: Offset(widget.date != null ? -12 : 0, 0),
              child: Text('ROOTGIST', style: RgText.wordmark),
            ),
          ],
        ),
      ),
    ),
  );

  // fallback: 오늘이 비었을 때 대신 보여 줄 가장 최근 다이제스트(헤드라인은 오늘 기준 그대로).
  Widget _headline(Digest? digest, Digest? fallback) {
    final total = digest?.papers.length ?? 0;
    final status = digest?.status;
    final headline = switch (status) {
      'delayed' => '오늘 논문을 아직 모으는 중이에요',
      'empty' when fallback != null => '오늘은 새 논문이 없어요',
      _ when fallback != null || total == 0 => '아직 올라온 논문이 없어요',
      _ => '새 논문 $total편이 올라왔어요',
    };
    final date = digest?.date ?? DateTime.now();
    // 일·월요일 다이제스트는 HF 토·일요일분(arXiv 발표 없음)
    final weekend = status == 'empty' && (date.weekday == DateTime.sunday || date.weekday == DateTime.monday);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s4, RgSpace.gutterText, 0),
        child: HeadingTextScale(
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
      ),
      if (fallback != null) ...[
        const SizedBox(height: RgSpace.s20),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: KeepAllText(
            [if (weekend) '주말에는 새 논문이 발표되지 않아요.', '가장 최근인 ${koreanDate(fallback.date)} 논문을 보여 드려요.'].join(' '),
            perSentence: true, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
          ),
        ),
      ],
      // 8.1 당일 지연: 추천 카드 자리에 마지막 수집 시각 안내.
      if (status == 'delayed') ...[
        const SizedBox(height: RgSpace.s20),
        RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: KeepAllText(
            [if (digest?.lastSuccessAt case final t?) '마지막 정상 수집 ${kstDateTime(t)}.', '모이는 대로 이 화면에 올라와요.'].join(' '),
            perSentence: true, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
          ),
        ),
      ],
    ]);
  }

  // 피드백 3차(A안 + C안의 대표 카드, 제목 문구 ① 담백한 설명형):
  // 연구소 소식 = 대표 1개(요약 한 줄) + 한 줄 1개, 바뀐 도구 = 버전 태그 한 줄 2개, 모델 = 큰 순위 숫자 2개.
  Widget _extrasSection(BuildContext context, (List<OfficialNews>, List<TrendingModel>)? data) {
    if (data == null) return const SizedBox.shrink();
    final (news, models) = data;
    final posts = news.where((n) => !n.isUpdate).take(2).toList();
    final updates = news.where((n) => n.isUpdate).take(2).toList();
    final top = models.take(2).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (posts.isNotEmpty) ...[
        const SectionTitle('연구소 소식', eyebrow: 'OpenAI · Anthropic · Google'),
        RgCard(
          child: Column(children: [
            FeaturedNews(news: posts.first, divider: posts.length > 1),
            for (final (i, n) in posts.skip(1).indexed) NewsRow(news: n, last: i == posts.length - 2),
          ]),
        ),
        MoreLink(label: '소식 더 보기', onTap: () => openExplore(context, const ExploreJump(1))),
      ],
      if (updates.isNotEmpty) ...[
        const SectionTitle('이번 주 바뀐 도구'),
        RgCard(child: Column(children: [for (final (i, n) in updates.indexed) UpdateRow(news: n, last: i == updates.length - 1)])),
        MoreLink(label: '업데이트 더 보기', onTap: () => openExplore(context, const ExploreJump(1, updates: true))),
      ],
      if (top.isNotEmpty) ...[
        const SectionTitle('요즘 많이 쓰는 모델'),
        RgCard(child: Column(children: [for (final (i, m) in top.indexed) ModelRow(model: m, last: i == top.length - 1)])),
        MoreLink(label: '모델 더 보기', onTap: () => openExplore(context, const ExploreJump(2))),
      ],
    ]);
  }
}

void openExplore(BuildContext context, ExploreJump jump) {
  exploreJump.value = jump;
  context.go('/explore');
}

// 묶음 제목(홈 하이라이트, 탐색 논문 칸)
// eyebrow: 제목 위 작은 머리말(출처 범위, 피드백 3차 C안). 예 「OpenAI · Anthropic · Google」
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.count, this.eyebrow});
  final String text;
  final String? count;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s28, RgSpace.gutterText, RgSpace.s12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s2, children: [
      if (eyebrow != null) Text(eyebrow!, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        spacing: RgSpace.s8,
        children: [
          Flexible(child: Semantics(header: true, child: Text(text, style: RgText.titleSection))),
          if (count != null) Text(count!, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        ],
      ),
    ]),
  );
}

// 카드 밑 「… 더 보기 ›」(터치 44)
class MoreLink extends StatelessWidget {
  const MoreLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Semantics(
      button: true,
      child: RgPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, spacing: RgSpace.s2, children: [
            Flexible(child: Text(label, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary, fontWeight: FontWeight.w500))),
            const RgIcon('chevron-right', size: 16, color: RgColors.textSecondary),
          ]),
        ),
      ),
    ),
  );
}

// 그날의 논문: 주제 칩 + 추천 카드 + 목록. limit이 있으면(홈) 칩 없이 앞에서 그만큼만.
class DigestPapers extends StatefulWidget {
  const DigestPapers({super.key, required this.digest, this.fallback, this.limit, this.title, this.pastDay = false});
  final Digest? digest;
  final Digest? fallback;
  final int? limit;
  final bool pastDay; // S04에서 연 지난 날짜: 「오늘의」 대신 그 날짜
  final String? title; // 목록 묶음 제목을 바꿀 때(탐색). null이면 「새로 올라온 논문」/「그날 올라온 논문」

  @override
  State<DigestPapers> createState() => _DigestPapersState();
}

class _DigestPapersState extends State<DigestPapers> {
  String? _topic; // null = 전체

  @override
  Widget build(BuildContext context) {
    final fallback = widget.fallback;
    final day = fallback ?? (widget.pastDay ? widget.digest : null); // 오늘이 아닌 날의 목록이면 그 날짜로 부른다
    final view = HomeView((fallback ?? widget.digest)?.papers ?? const [], _topic);
    final limit = widget.limit;
    final list = limit == null ? view.list : view.list.take(limit - (view.featured == null ? 0 : 1)).toList();
    final chips = limit == null ? view.chips : const <String>[];
    return ValueListenableBuilder(
      valueListenable: bookmarks,
      builder: (context, saved, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chips.isNotEmpty) ...[
          // 칩 시각 높이 36, 터치 44(더 큰 텍스트에서는 늘어난다). 시안의 위아래 20은 시각 기준이라 4씩 덜어낸다.
          const SizedBox(height: RgSpace.s16),
          SizedBox(
            height: RgFilterChip.touchHeight(context),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
              itemCount: chips.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: RgSpace.s8),
              itemBuilder: (_, i) {
                final topic = i == 0 ? null : chips[i - 1];
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
          SizedBox(height: chips.isEmpty ? RgSpace.s20 : RgSpace.s16),
          _FeaturedCard(
            paper: p,
            label: day == null ? '오늘의 주요 논문' : '${day.date.month}월 ${day.date.day}일 주요 논문',
          ),
        ],
        if (list.isNotEmpty) ...[
          if (limit == null)
            SectionTitle(widget.title ?? (day == null ? '새로 올라온 논문' : '그날 올라온 논문'), count: '${list.length}편')
          else
            const SizedBox(height: RgSpace.s12),
          RgCard(
            child: Column(
              children: [
                for (final (i, p) in list.indexed)
                  RgListRow(
                    showDivider: i < list.length - 1,
                    onTap: () => context.push('/paper/${p.id}'),
                    trailing: ItemActions(id: p.id, title: p.title, url: paperUrl(p.id)),
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
      ]),
    );
  }
}

// 헤드라인 2줄 + 추천 카드 + 목록 행 모양(홈에는 칩이 없다).
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
          const RgCard(
            padding: EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
            child: Column(
              spacing: RgSpace.s6,
              children: [
                RgBar(lineHeight: 24, widthFactor: 0.4),
                RgBar(lineHeight: 29, widthFactor: 0.9),
                RgBar(lineHeight: 20, widthFactor: 0.45),
                SizedBox(height: RgSpace.s8),
                RgBar(lineHeight: 23),
                RgBar(lineHeight: 23, widthFactor: 0.7), // 「자세히 읽기」 버튼 자리는 없앴다(P5)
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
  const _FeaturedCard({required this.paper, required this.label});
  final PaperItem paper;
  final String label;

  @override
  Widget build(BuildContext context) {
    final bullets = paper.keyPoints.take(2); // G11
    // iOS QA P5: 「자세히 읽기」 버튼 없이 카드 전체가 S02로(목록 행과 같은 방식). 공유·북마크는 오른쪽 위에 따로.
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: () => context.push('/paper/${paper.id}'),
        child: RgCard(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: RgSpace.s8,
                children: [
                  Expanded(
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
                        HeadingTextScale(child: KeepAllText(paper.title, style: RgText.titleFeatured)),
                        const SizedBox(height: RgSpace.s6),
                        KeepAllText('${paper.authors} · ${paper.date}', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                      ],
                    ),
                  ),
                  // 누르는 영역 44는 그대로 두고 모양만 카드 모서리 쪽으로
                  Transform.translate(
                    offset: const Offset(RgSpace.s12, -RgSpace.s10),
                    child: ItemActions(id: paper.id, title: paper.title, url: paperUrl(paper.id)),
                  ),
                ],
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}

// 필터·주요 논문 선정 규칙(7.1, G6, G9, G14). 화면과 떼어 테스트한다.
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
