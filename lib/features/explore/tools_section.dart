import 'package:flutter/material.dart';

import '../../data/repository.dart';
import '../../design/widgets/rg_row_head.dart';
import 'date_groups.dart';
import 'github_rankings.dart';
import 'trending_models.dart';

// 탐색 「도구」 칸(2026-11-10 정보 구조 정리): 읽을 것(논문·소식)과 써 볼 것(모델·저장소)을 나눈다.
// 「트렌딩 모델 | 새 모델 | GitHub」. 칸 이름 줄은 목록과 함께 올라가지 않아, 아래로 내려가 있어도 바로 다른 칸으로 간다.
// 모델 ↔ GitHub는 목록이 RgFilterSwitch로 바뀐다(페이드, 「동작 줄이기」면 바로).
class ToolsSection extends StatefulWidget {
  const ToolsSection({super.key});

  @override
  State<ToolsSection> createState() => _ToolsSectionState();
}

class _ToolsSectionState extends State<ToolsSection> {
  late var _tab = toolsTab.value = exploreJump.value?.tab == 2 ? exploreJump.value!.toolsTab : toolsTab.value;

  // 홈 「더 보기」·옆으로 밀기로 들어올 때 그 칸으로
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 2 && mounted) setState(() => _tab = toolsTab.value = j.toolsTab);
  }

  @override
  void initState() {
    super.initState();
    exploreJump.addListener(_jump);
  }

  @override
  void dispose() {
    exploreJump.removeListener(_jump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExploreSectionTabs(
          labels: const ['트렌딩 모델', '새 모델', 'GitHub'],
          selected: _tab,
          onTap: (i) => setState(() => _tab = toolsTab.value = i),
        ),
        Expanded(
          child: RgFilterSwitch(
            switchKey: _tab == 2,
            child: _tab == 2 ? const GithubRankingsSection() : TrendingModelsSection(fresh: _tab == 1),
          ),
        ),
      ],
    );
  }
}
