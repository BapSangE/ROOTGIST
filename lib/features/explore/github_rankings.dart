import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
import '../reader/text_size_sheet.dart';

// 탐색 「도구 › GitHub」 칸(2026-11-10): 「24시간 · 7일 · 30일」 칩. 그 기간 안에 생긴 AI 저장소를 24시간은 별 많은 순으로,
// 7일·30일은 생긴 지 오래될수록 조금씩 깎아(별 ÷ √(날 수 + 3), 2026-11-13) 세운다(worker gh_rankings).
// 기간이 언제부터 언제인지, 별 수는 언제 모은 값인지를 목록 위에 그대로 적는다. 저장소를 누르면 GitHub에서 연다.
// 기간을 바꾸면 목록이 RgFilterSwitch로 바뀐다(페이드, 「동작 줄이기」면 바로).
const githubPeriods = ['day', 'week', 'month'];
const githubPeriodLabels = ['24시간', '7일', '30일']; // 「오늘」이 아니라 모은 시각부터 거꾸로 센 기간

class GithubRankingsSection extends StatefulWidget {
  const GithubRankingsSection({super.key});

  @override
  State<GithubRankingsSection> createState() => _GithubRankingsSectionState();
}

class _GithubRankingsSectionState extends State<GithubRankingsSection> {
  // 받은 값을 들고 있어 도구 칸 안에서 모델 ↔ GitHub를 오가도 빈 틀이 다시 보이지 않는다(새로 받는 동안 지난 값)
  static GithubRankings? _last;
  final _req = Reloadable(() => repository.listGithubRankings().then((v) => _last = v));
  late var _period = githubPeriod.value;

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_req, githubNewest]),
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        initialData: _last,
        builder: (context, snap) {
          final data = snap.data;
          final period = data?.periods[githubPeriods[_period]];
          // 최신순(2026-11-13): 받아 둔 순위 안에서 생긴 시각 순. 순위 번호는 순서와 안 맞아 숨긴다(카드에 「N일 전 생성」이 있다)
          final newest = githubNewest.value;
          final repos = newest ? newestFirst(period?.repos ?? const []) : [...?period?.repos];
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              const ExploreSectionNote('GitHub에서 가져온, 새로 생긴 AI 저장소예요'),
              ExploreTextFilters(
                labels: githubPeriodLabels,
                selected: _period,
                onTap: (i) => setState(() => _period = githubPeriod.value = i),
              ),
              if (repos.length > 1)
                ExploreSortRow(labels: const ['별순', '최신순'], selected: newest ? 1 : 0, onPick: (i) => githubNewest.value = i == 1),
              RgFilterSwitch(
                switchKey: (_period, newest),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snap.hasError) ...[
                      const SizedBox(height: RgSpace.s20),
                      RgErrorCard(error: snap.error, onRetry: _req.reload),
                    ] else if (!snap.hasData)
                      const RgSkeleton(
                        child: Padding(padding: EdgeInsets.only(top: RgSpace.s20), child: RgSkeletonRows(count: 5)),
                      )
                    else ...[
                      if (period != null) PeriodNote(period: period, collectedAt: data!.collectedAt, newest: newest),
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
                            children: [for (final r in repos) GithubRepoCard(repo: r, now: clock(), showRank: !newest)],
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
                                '이름·설명·주제에 llm·agent·ai·claude·mcp·gpt·codex·rag 같은 낱말이 들어간 저장소를 모았어요. 링크 모음, 거의 빈 저장소, 포크 없이 별만 많은 저장소, 광고·치트 저장소는 뺐어요. '
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

// 최신순: 생긴 시각이 늦은 것부터. 생긴 시각을 모르면 맨 뒤, 같으면 순위 순
List<GithubRepo> newestFirst(List<GithubRepo> repos) => [...repos]..sort((a, b) {
  final c = (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
  return c != 0 ? c : a.rank.compareTo(b.rank);
});

// 「11월 3일 15:17 ~ 11월 10일 15:17 사이에 생긴 저장소」 + 「별 많은 순 · 11월 10일 15:17 기준」
String periodRange(GithubPeriod p) => '${kstDateTime(p.start)} ~ ${kstDateTime(p.end)}';

class PeriodNote extends StatelessWidget {
  const PeriodNote({super.key, required this.period, this.collectedAt, this.newest = false});
  final GithubPeriod period;
  final DateTime? collectedAt;
  final bool newest; // 최신순으로 보는 중

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
                    // 7일·30일은 별 총합만 보면 기간 초반 저장소가 늘 위라, 별이 비슷하면 최근에 생긴 쪽을 위로(worker gh_rankings)
                    newest
                        ? '이 사이에 생긴 저장소 중 순위에 든 곳을 최근에 생긴 순으로 보여 줘요. 별 수는 ${kstDateTime(collectedAt ?? period.end)}에 모은 값이에요.'
                        : period.end.difference(period.start) <= const Duration(hours: 25)
                        ? '이 사이에 생긴 저장소를 별 많은 순으로 세웠어요. 별 수는 ${kstDateTime(collectedAt ?? period.end)}에 모은 값이에요.'
                        : '이 사이에 생긴 저장소를 별 수와 생긴 시기로 세웠어요. 별이 비슷하면 최근에 생긴 쪽이 위예요. 별 수는 ${kstDateTime(collectedAt ?? period.end)}에 모은 값이에요.',
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

// 카드를 누르면 앱 안 상세(README 정리·숫자)를 먼저 연다(2026-11-11). GitHub은 상세 화면의 버튼으로.
void openRepo(BuildContext context, GithubRepo r) {
  HapticFeedback.selectionClick();
  context.push('/repo/${Uri.encodeComponent(r.fullName)}');
}

// 순위 카드: 모델 칸 트렌딩 카드와 같은 틀(순위 칸 폭 고정 30/46 → 이름 시작점이 맞는다)
class GithubRepoCard extends StatelessWidget {
  const GithubRepoCard({super.key, required this.repo, required this.now, this.showRank = true});
  final GithubRepo repo;
  final DateTime now;
  final bool showRank; // 최신순이면 순위 번호를 숨긴다(번호가 뒤섞여 보인다)

  @override
  Widget build(BuildContext context) {
    final r = repo;
    return Semantics(
      button: true,
      hint: '저장소 설명 보기',
      child: HomeCard(
        radius: 20,
        padding: const EdgeInsets.all(RgSpace.s20),
        onTap: () => openRepo(context, r),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: RgSpace.s16,
          children: [
            if (showRank) SizedBox(
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
                        child: ReaderTextScale(child: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeTitle)),
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
                    ReaderTextScale(child: KeepAllText(
                      r.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: RgText.homeSummary.copyWith(color: RgColors.textBody),
                    )),
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

@visibleForTesting
void resetGithubRankings() => _GithubRankingsSectionState._last = null;
