import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import 'home_screen.dart' show openExplore;
import 'home_sections.dart';
import 'briefing.dart';

// 홈 맨 위 소식 두 칸(디자이너 시안 home_re 2026-10-31): 「오늘의 주요 소식」 한 카드 → 「개발자 화제」 글마다 카드.
// 고르는 규칙은 briefing.dart(최근 24시간 → 적으면 3일 → 없으면 최근 소식). 각 칸의 「더보기」는 탐색의 그 칸으로.
// 시안에 날짜·「새 소식 N건」 헤드라인과 요약 배지는 없어 뺐다(2026-10-31).
class BriefingSection extends StatelessWidget {
  const BriefingSection({super.key, required this.news});
  final List<OfficialNews>? news; // null = 아직 불러오는 중

  @override
  Widget build(BuildContext context) {
    final news = this.news;
    if (news == null) return const SizedBox.shrink();
    final now = clock();
    final b = Briefing(news, now, top: 3); // 5개는 길어 보여 3개로(실기기 2026-10-31)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (b.stories.isNotEmpty)
        HomeSection(
          title: b.stale ? '최근 소식' : b.wide ? '최근 주요 소식' : '오늘의 주요 소식',
          // 「중요한 순」 대신 고른 기준(importance)을 밝힌다(피드백 3번)
          subtitle: b.stale ? '최근에 올라온 소식이에요' : '공식 발표·새 모델·여러 곳에서 다룬 소식을 먼저 골랐어요',
          onMore: () => openExplore(context, const ExploreJump(1)),
          child: HomeStoriesCard(stories: b.stories, now: now),
        ),
      // 개발자 화제: 주요 소식에 오르지 않은 Hacker News 글 점수 순 2개 + 이번 주 GitHub 새 저장소 별 순 1개
      if (b.talk.isNotEmpty || b.repos.isNotEmpty)
        HomeSection(
          title: '개발자 화제',
          subtitle: 'Hacker News 추천·GitHub 별이 많은 글이에요',
          onMore: () => openExplore(context, const ExploreJump(1, hot: true)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            for (final n in [...b.talk.take(2), ...b.repos.take(1)]) HomeTalkCard(news: n, now: now),
          ]),
        ),
    ]);
  }
}
