import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../design/widgets/rg_states.dart';
import '../home/home_sections.dart';
import '../common/item_actions.dart';
import 'date_groups.dart';

// 탐색 「GitHub」 칸(2026-11-10): 「일간 | 주간 | 월간」. 그 기간 안에 생긴 AI 저장소를 별 많은 순으로(worker gh_rankings).
// 기간이 언제부터 언제인지, 별 수는 언제 모은 값인지를 목록 위에 그대로 적는다. 저장소를 누르면 GitHub에서 연다.
// 기간을 바꾸면 목록이 RgFilterSwitch로 바뀐다(페이드, 「동작 줄이기」면 바로).
const githubPeriods = ['day', 'week', 'month'];
const githubPeriodLabels = ['일간', '주간', '월간'];

class GithubRankingsSection extends StatefulWidget {
  const GithubRankingsSection({super.key});

  @override
  State<GithubRankingsSection> createState() => _GithubRankingsSectionState();
}

class _GithubRankingsSectionState extends State<GithubRankingsSection> {
  final _req = Reloadable(repository.listGithubRankings);
  late var _period = githubPeriod.value = exploreJump.value?.tab == 3 ? exploreJump.value!.period : githubPeriod.value;

  // 옆으로 밀기·HOT 칸 「전체 순위」로 들어올 때 그 기간으로
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 3 && mounted) setState(() => _period = githubPeriod.value = j.period);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _req,
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final data = snap.data;
          final period = data?.periods[githubPeriods[_period]];
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              ExploreSectionTabs(
                labels: githubPeriodLabels,
                selected: _period,
                onTap: (i) => setState(() => _period = githubPeriod.value = i),
              ),
              RgFilterSwitch(
                switchKey: _period,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snap.hasError) ...[
                      const SizedBox(height: RgSpace.s20),
                      RgErrorCard(error: snap.error, onRetry: _req.reload),
                    ] else if (snap.connectionState != ConnectionState.done)
                      const RgSkeleton(
                        child: Padding(padding: EdgeInsets.only(top: RgSpace.s20), child: RgSkeletonRows(count: 5)),
                      )
                    else ...[
                      if (period != null) PeriodNote(period: period, collectedAt: data!.collectedAt),
                      if (period == null || period.repos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
                          child: KeepAllText(
                            period == null ? '아직 모은 순위가 없어요. 다음 수집 때 채워져요.' : '이 기간에 생긴 저장소 중 순위에 들 만큼 별을 모은 곳이 아직 없어요.',
                            style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s16, RgSpace.gutterText, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: RgSpace.s16,
                            children: [for (final r in period.repos) GithubRepoCard(repo: r, now: clock())],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s20, RgSpace.gutterText, 0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: RgSpace.s6,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: RgIcon('info', size: 14, color: RgColors.textSecondary),
                            ),
                            Expanded(
                              child: KeepAllText(
                                '이름·설명·주제에 llm·agent·ai·claude·mcp가 들어간 저장소를 모았어요. 링크 모음, 거의 빈 저장소, 포크 없이 별만 많은 저장소, 광고·치트 저장소는 뺐어요. '
                                '설명은 AI가 옮긴 것이고, 도구를 검증한 결과가 아니에요.',
                                perSentence: true,
                                style: RgText.caption.copyWith(color: RgColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// 「11월 3일 15:17 ~ 11월 10일 15:17 사이에 생긴 저장소」 + 「별 많은 순 · 11월 10일 15:17 기준」
String periodRange(GithubPeriod p) => '${kstDateTime(p.start)} ~ ${kstDateTime(p.end)}';

class PeriodNote extends StatelessWidget {
  const PeriodNote({super.key, required this.period, this.collectedAt});
  final GithubPeriod period;
  final DateTime? collectedAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s16, RgSpace.gutterText, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: RgSpace.s14, vertical: RgSpace.s12),
        decoration: BoxDecoration(color: RgHome.statPill, borderRadius: BorderRadius.circular(14)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RgSpace.s8,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: RgIcon('calendar', size: 16, color: RgColors.textSecondary),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  KeepAllText(
                    periodRange(period),
                    style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary),
                  ),
                  KeepAllText(
                    '이 사이에 생긴 저장소를 별 많은 순으로 세웠어요. 별 수는 ${kstDateTime(collectedAt ?? period.end)}에 모은 값이에요.',
                    style: RgText.caption.copyWith(color: RgColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 「3시간 전 생성」 「2일 전 생성」
String createdAgo(DateTime created, DateTime now) {
  final d = now.difference(created);
  if (d.inHours < 1) return '방금 생성';
  if (d.inHours < 24) return '${d.inHours}시간 전 생성';
  return '${d.inDays}일 전 생성';
}

// 저장소 카드 오른쪽 저장 버튼(모델 카드와 같은 원 40). 보관함에서 누르면 GitHub에서 연다(kind repo, id = 주소).
ItemActions repoActions(GithubRepo r) =>
    ItemActions(id: r.url, title: r.fullName, url: r.url, source: 'GitHub', kind: 'repo', visualSize: 40);

Future<void> openRepo(GithubRepo r) async {
  HapticFeedback.selectionClick();
  await launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
}

// 순위 카드: 모델 칸 트렌딩 카드와 같은 틀(순위 칸 폭 고정 30/46 → 이름 시작점이 맞는다)
class GithubRepoCard extends StatelessWidget {
  const GithubRepoCard({super.key, required this.repo, required this.now});
  final GithubRepo repo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = repo;
    return Semantics(
      button: true,
      hint: 'GitHub에서 열기',
      child: HomeCard(
        radius: 20,
        padding: const EdgeInsets.all(RgSpace.s20),
        onTap: () => openRepo(r),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RgSpace.s16,
          children: [
            SizedBox(
              width: r.rank < 10 ? 30 : 46,
              child: Semantics(
                label: '${r.rank}위',
                excludeSemantics: true,
                child: Text(
                  '${r.rank}',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: RgText.homeRank.copyWith(color: RgColors.textBody),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: RgSpace.s8,
                    children: [
                      Expanded(
                        child: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeTitle),
                      ),
                      repoActions(r),
                    ],
                  ),
                  const SizedBox(height: RgSpace.s4),
                  Text(
                    [r.owner, ?r.language, if (r.createdAt != null) createdAgo(r.createdAt!, now)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RgText.homeMeta.copyWith(color: RgColors.textSecondary),
                  ),
                  if (r.description != null) ...[
                    const SizedBox(height: RgSpace.s8),
                    KeepAllText(
                      r.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: RgText.homeSummary.copyWith(color: RgColors.textBody),
                    ),
                  ],
                  const SizedBox(height: RgSpace.s16),
                  Wrap(
                    spacing: RgSpace.s6,
                    runSpacing: RgSpace.s6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      HomeStat(countKo(r.stars), icon: 'star-filled', label: '별 ${countKo(r.stars)}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 소식 HOT 칸 맨 위: 「오늘 뜨는 저장소」 카드 줄(옆으로 넘김, 카드 폭에 맞춰 멈춘다) + 「전체 순위 ›」 → GitHub 칸 일간.
// 일간이 비면 주간으로. 둘 다 비면 그리지 않는다.
class GithubRepoStrip extends StatefulWidget {
  const GithubRepoStrip({super.key});

  @override
  State<GithubRepoStrip> createState() => _GithubRepoStripState();
}

class _GithubRepoStripState extends State<GithubRepoStrip> {
  // 받은 순위를 들고 있어 HOT 칸에 다시 들어와도 띠가 바로 보인다(늦게 끼어들며 아래 목록을 밀지 않게).
  // 처음 받을 때만 220ms 펼침(「동작 줄이기」면 바로).
  static GithubRankings? _last;
  final _req = Reloadable(() => repository.listGithubRankings().then((v) => _last = v));

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
        initialData: _last,
        builder: (context, snap) {
          final d = RgMotion.of(context, RgMotion.base);
          return AnimatedSize(
            duration: d,
            curve: RgMotion.curve,
            alignment: Alignment.topCenter,
            child: _strip(snap.data ?? _last),
          );
        },
      ),
    );
  }

  Widget _strip(GithubRankings? data) {
          final periods = data?.periods ?? const {};
          final day = periods['day'];
          final (index, p) = day != null && day.repos.isNotEmpty ? (0, day) : (1, periods['week']);
          if (p == null || p.repos.isEmpty) return const SizedBox(width: double.infinity);
          final repos = p.repos.take(5).toList();
          final now = clock();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DateHeader(
                label: index == 0 ? '오늘 뜨는 저장소' : '이번 주 뜨는 저장소',
                count: '${repos.length}곳',
                open: true,
                onMore: () {
                  HapticFeedback.selectionClick();
                  exploreJump.value = ExploreJump(3, period: index, animate: true);
                },
                moreLabel: '전체 순위',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, 0, RgSpace.gutterText, RgSpace.s4),
                child: KeepAllText(
                  '${periodRange(p)} 사이에 생긴 저장소',
                  style: RgText.caption.copyWith(color: RgColors.textSecondary),
                ),
              ),
              SizedBox(
                height: 168,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = (c.maxWidth - RgSpace.gutterText * 2) * 0.82;
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      physics: _SnapPhysics(itemExtent: w + RgSpace.s12),
                      padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText, vertical: RgSpace.s8),
                      itemCount: repos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: RgSpace.s12),
                      itemBuilder: (context, i) => SizedBox(width: w, child: _StripCard(repo: repos[i], now: now)),
                    );
                  },
                ),
              ),
              const SizedBox(height: RgSpace.s12),
            ],
          );
  }
}

@visibleForTesting
void resetGithubStrip() => _GithubRepoStripState._last = null;

class _StripCard extends StatelessWidget {
  const _StripCard({required this.repo, required this.now});
  final GithubRepo repo;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = repo;
    return Semantics(
      button: true,
      label: '${r.rank}위 ${r.name}',
      hint: 'GitHub에서 열기',
      child: HomeCard(
        radius: 20,
        padding: const EdgeInsets.all(RgSpace.s16),
        onTap: () => openRepo(r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: RgSpace.s8,
              children: [
                Text('${r.rank}', style: RgText.homeTitle.copyWith(color: RgColors.textTertiary)),
                Expanded(child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.homeTitle)),
              ],
            ),
            const SizedBox(height: RgSpace.s6),
            Expanded(
              child: Text(
                r.description ?? r.owner,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: RgText.homeSummary.copyWith(color: RgColors.textBody),
              ),
            ),
            Row(
              spacing: RgSpace.s8,
              children: [
                HomeStat(countKo(r.stars), icon: 'star-filled', label: '별 ${countKo(r.stars)}'),
                if (r.createdAt != null)
                  Flexible(
                    child: Text(createdAgo(r.createdAt!, now), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: RgText.homeMeta.copyWith(color: RgColors.textSecondary)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 카드 한 장 폭마다 멈추는 넘기기(손을 떼면 가까운 카드 앞에 붙는다). 「동작 줄이기」와 상관없이 위치만 맞춘다.
class _SnapPhysics extends ScrollPhysics {
  const _SnapPhysics({required this.itemExtent, super.parent});
  final double itemExtent;

  @override
  _SnapPhysics applyTo(ScrollPhysics? ancestor) => _SnapPhysics(itemExtent: itemExtent, parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    if ((velocity <= 0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final page = position.pixels / itemExtent + (velocity.abs() > 200 ? velocity.sign * 0.5 : 0);
    final target = (page.round() * itemExtent).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return null;
    return ScrollSpringSimulation(spring, position.pixels, target, velocity, tolerance: toleranceFor(position));
  }

  @override
  bool get allowImplicitScrolling => false;
}
