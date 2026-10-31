import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_new_dot.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../common/item_actions.dart';
import '../common/term_text.dart';
import '../explore/news_detail.dart' show modelSpec;
import '../explore/official_news.dart' show newsKey;
import 'briefing.dart';

// 홈 칸들(디자이너 시안 home_re 2026-10-31, design-preview는 ~/Downloads/home_re 원본).
// 회청 바탕(RgHome.bg) 위에 칸마다 [제목 28 · 더보기 ›] + 부제, 그 아래 흰 카드(둥글기 28). 좌우 여백 24.
// 누르면 카드·행이 살짝 눌리고(RgPressable), 더보기·북마크는 가벼운 진동.

const homeGutter = 24.0;

// 칸 하나: 위아래 20 + 머리(위아래 12) + 내용(위아래 10, 좌우 24)
class HomeSection extends StatelessWidget {
  const HomeSection({super.key, required this.title, this.subtitle, this.onMore, required this.child});
  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: RgSpace.s20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(homeGutter, RgSpace.s12, homeGutter - 8, RgSpace.s12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s4, children: [
          Row(children: [
            Expanded(child: Semantics(header: true, child: HeadingTextScale(child: KeepAllText(title, style: RgText.homeSection.copyWith(color: RgColors.textPrimary))))),
            if (onMore != null) _More(onTap: onMore!),
          ]),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: KeepAllText(subtitle!, style: RgText.homeSub.copyWith(color: RgColors.textBody)),
            ),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: homeGutter, vertical: RgSpace.s10), child: child),
    ]),
  );
}

// 「더보기 ›」: 보이는 글자는 작게, 누르는 영역은 44
class _More extends StatelessWidget {
  const _More({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '더보기',
    excludeSemantics: true,
    child: RgPressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: RgSpace.minTouch, minWidth: RgSpace.minTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('더보기', style: RgText.homeMore.copyWith(color: RgColors.textSecondary)),
            RgIcon('chevron-right', size: 14, color: RgColors.textSecondary),
          ]),
        ),
      ),
    ),
  );
}

// 흰 카드(둥글기 28, 옅은 그림자). color로 면을 바꾼다(주요 논문 회색·바뀐 도구 회사 색)
class HomeCard extends StatelessWidget {
  const HomeCard({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 28, 20, 16), this.color, this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? RgHome.card, borderRadius: BorderRadius.circular(28), boxShadow: RgHome.cardShadow),
      child: child,
    );
    return onTap == null ? card : Semantics(button: true, child: RgPressable(onTap: onTap, child: card));
  }
}

// 알약 칩(높이 28, 좌우 12): 출처(회사 색)·키워드·주제
class HomeChip extends StatelessWidget {
  const HomeChip(this.label, {super.key, this.background, this.foreground});
  final String label;
  final Color? background, foreground;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 28),
    padding: const EdgeInsets.symmetric(horizontal: RgSpace.s12, vertical: 6),
    decoration: BoxDecoration(color: background ?? RgHome.chip, borderRadius: BorderRadius.circular(RgRadius.pill)),
    child: Text(
      label,
      textHeightBehavior: const TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even),
      style: RgText.homeChip.copyWith(color: foreground ?? RgColors.textBody, leadingDistribution: TextLeadingDistribution.even),
    ),
  );
}

// 회색 알약 숫자(추천·댓글·좋아요·다운로드). 화면 읽기에는 「추천 203」처럼
class HomeStat extends StatelessWidget {
  const HomeStat(this.text, {super.key, this.icon, required this.label});
  final String text;
  final String? icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s12, vertical: 6),
      decoration: BoxDecoration(color: RgHome.statPill, borderRadius: BorderRadius.circular(RgRadius.pill)),
      // 아이콘을 글자 안에 넣어 큰 글자에서도 넘치지 않고 줄을 바꾼다
      child: Text.rich(
        TextSpan(children: [
          if (icon != null)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(padding: const EdgeInsets.only(right: RgSpace.s4), child: RgIcon(icon!, size: 14, color: RgHome.statText)),
            ),
          TextSpan(text: text),
        ]),
        style: RgText.homeChip.copyWith(color: RgHome.statText),
      ),
    ),
  );
}

// 「6시간 전」 + 새 글 점(읽으면 사라진다)
class _NewsTime extends StatelessWidget {
  const _NewsTime(this.news, this.now, {this.style});
  final OfficialNews news;
  final DateTime now;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: readItems,
    builder: (context, _, _) => Row(spacing: RgSpace.s4, children: [
      Text(relativeKo(news.publishedAt, now), style: style ?? RgText.homeDate.copyWith(color: RgColors.textBody)),
      RgNewLabel(visible: isNew(newsKey(news), news.publishedAt)),
    ]),
  );
}

void _openNews(BuildContext context, OfficialNews n) => context.push('/news/${Uri.encodeComponent(n.id)}');

// 키워드 칩: 제목·요약에 나오는 사전 용어(한국어 표기) 앞에서 2개. 사전을 못 받았거나 없으면 칩 없이
List<String> newsKeywords(OfficialNews n, List<GlossaryTerm> terms, {int max = 2}) {
  final text = [n.titleKo ?? n.titleEn, ?n.summaryKo].join(' ');
  final out = <String>[];
  for (final h in findHighlights(text, terms)) {
    if (!out.contains(h.$3) && h.$3 != n.sourceLabel) out.add(h.$3);
    if (out.length == max) break;
  }
  return out;
}

// 오늘의 주요 소식 카드: 한 카드 안에 행들(가는 선으로 나눔, 행 사이 32)
// 행 = 시각·새 글 점 → 제목 두 줄 → 요약 한 줄 → 출처 칩(회사 색) + 키워드 칩
class HomeStoriesCard extends StatelessWidget {
  const HomeStoriesCard({super.key, required this.stories, required this.now});
  final List<OfficialNews> stories;
  final DateTime now;

  @override
  Widget build(BuildContext context) => HomeCard(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
    child: FutureBuilder(
      future: dictionary(),
      initialData: dictionaryValue,
      builder: (context, snap) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 32, children: [
        for (final (i, n) in stories.indexed) HomeStoryRow(news: n, now: now, last: i == stories.length - 1, keywords: newsKeywords(n, snap.data ?? const [])),
      ]),
    ),
  );
}

class HomeStoryRow extends StatelessWidget {
  const HomeStoryRow({super.key, required this.news, required this.now, required this.last, required this.keywords});
  final OfficialNews news;
  final DateTime now;
  final bool last;
  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    final n = news;
    final one = n.summaryKo ?? n.keyPoints.firstOrNull?.text;
    final tone = brandToneOf(n.source);
    return Semantics(
      button: true,
      child: RgPressable(
        row: true,
        onTap: () => _openNews(context, n),
        child: Container(
          padding: EdgeInsets.only(bottom: last ? 0 : RgSpace.s20),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: RgHome.divider))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NewsTime(n, now),
            const SizedBox(height: RgSpace.s6),
            KeepAllText(n.titleKo ?? n.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeTitle.copyWith(color: RgColors.textPrimary)),
            if (one != null) ...[
              const SizedBox(height: RgSpace.s8),
              Text(one, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.homeSummary.copyWith(color: RgColors.textSecondary)),
            ],
            const SizedBox(height: RgSpace.s20),
            Wrap(spacing: RgSpace.s8, runSpacing: RgSpace.s8, children: [
              HomeChip(n.sourceLabel, background: tone?.background, foreground: tone?.foreground),
              for (final k in keywords) HomeChip(k),
            ]),
          ]),
        ),
      ),
    );
  }
}

// 개발자 화제 카드(글마다 한 장): 시각 → 제목 → 사이트 · 추천 · 댓글
class HomeTalkCard extends StatelessWidget {
  const HomeTalkCard({super.key, required this.news, required this.now});
  final OfficialNews news;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final n = news;
    return HomeCard(
      onTap: () => _openNews(context, n),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _NewsTime(n, now),
        const SizedBox(height: RgSpace.s12),
        KeepAllText(n.titleKo ?? n.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeTitle.copyWith(color: RgColors.textPrimary)),
        const SizedBox(height: 25),
        // 사이트는 왼쪽, 숫자(Hacker News 추천·댓글, GitHub는 별)는 오른쪽. 큰 글자로 한 줄에 안 들어가면 숫자가 다음 줄로
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: [
          Text(n.sourceLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.homeMeta.copyWith(color: RgColors.textSecondary)),
          Wrap(spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: [
            if (n.isGithub && n.points != null) HomeStat(countKo(n.points!), icon: 'star-filled', label: '별 ${countKo(n.points!)}')
            else if (n.points != null) HomeStat(countKo(n.points!), icon: 'like-filled', label: '추천 ${countKo(n.points!)}'),
            if (!n.isGithub && n.comments != null) HomeStat(countKo(n.comments!), icon: 'comment-filled', label: '댓글 ${countKo(n.comments!)}'),
          ]),
        ]),
      ]),
    );
  }
}

String _paperDay(PaperItem p) {
  final d = DateTime.tryParse(p.publishedAt);
  return d == null ? p.date : '${d.month}월 ${d.day}일';
}

String _paperAuthors(PaperItem p) => p.authorCount > 1 ? '${p.firstAuthor} 외 ${p.authorCount - 1}명' : p.firstAuthor;

// 오늘의 주요 논문: 회색 카드, 흰 글자. 머리말 → 제목 24 → 요약 두 줄, 오른쪽 위 북마크, 아래 주제 칩
class HomeFeaturedPaper extends StatelessWidget {
  const HomeFeaturedPaper({super.key, required this.paper, required this.label});
  final PaperItem paper;
  final String label;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    final white = Colors.white;
    return HomeCard(
      color: RgHome.paperCard,
      onTap: () => context.push('/paper/${p.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: RgText.homeLabel.copyWith(color: white.withValues(alpha: 0.8))),
              const SizedBox(height: RgSpace.s12),
              HeadingTextScale(child: KeepAllText(p.title, style: RgText.homeFeatured.copyWith(color: white))),
              if (p.keyPoints.isNotEmpty) ...[
                const SizedBox(height: RgSpace.s8),
                KeepAllText(p.keyPoints.first, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeSummary.copyWith(color: white.withValues(alpha: 0.7))),
              ],
            ]),
          ),
          Transform.translate(
            offset: const Offset(4, -6),
            child: ItemActions(id: p.id, title: p.title, url: paperUrl(p.id), visualSize: 44, circleColor: RgHome.paperRing, iconColor: white),
          ),
        ]),
        if (p.topicLabel != null) ...[
          const SizedBox(height: RgSpace.s20),
          HomeChip(p.topicLabel!, background: const Color(0x29000000), foreground: white.withValues(alpha: 0.8)),
        ],
      ]),
    );
  }
}

// 바탕 위 논문 행: 날짜 → 제목, 오른쪽 북마크 → 주제 칩 · 저자(오른쪽). 행 사이 가는 선
class HomePaperRow extends StatelessWidget {
  const HomePaperRow({super.key, required this.paper, required this.last});
  final PaperItem paper;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final p = paper;
    return Semantics(
      button: true,
      child: RgPressable(
        row: true,
        onTap: () => context.push('/paper/${p.id}'),
        child: Container(
          padding: const EdgeInsets.only(bottom: RgSpace.s20),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: RgHome.dividerOnBg))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s6, children: [
                  Text(_paperDay(p), style: RgText.homeDate.copyWith(color: RgColors.textBody)),
                  KeepAllText(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeTitle.copyWith(color: RgColors.textPrimary)),
                ]),
              ),
              Transform.translate(
                offset: const Offset(6, -4),
                child: ItemActions(id: p.id, title: p.title, url: paperUrl(p.id), visualSize: 34, circleColor: RgHome.ring),
              ),
            ]),
            const SizedBox(height: RgSpace.s12),
            Row(spacing: RgSpace.s8, children: [
              if (p.topicLabel != null) HomeChip(p.topicLabel!),
              Expanded(
                child: Text(_paperAuthors(p), textAlign: TextAlign.end, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.homeMeta.copyWith(color: RgColors.textSecondary)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// 바뀐 도구 카드: 회사 색 면. 시각 → 도구 이름 20 → 「업데이트 4건 (v…~v…)」, 오른쪽 위 북마크(같은 색 계열 원)
class HomeUpdateCard extends StatelessWidget {
  const HomeUpdateCard({super.key, required this.news, required this.now});
  final OfficialNews news;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final n = news;
    final tone = brandToneOf(n.source);
    return HomeCard(
      color: tone?.card ?? RgHome.card,
      onTap: () => _openNews(context, n),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _NewsTime(n, now, style: RgText.homeLabel.copyWith(color: RgColors.textBody)),
            const SizedBox(height: RgSpace.s12),
            KeepAllText(n.sourceLabel, style: RgText.homeUpdate.copyWith(color: RgColors.textPrimary)),
            const SizedBox(height: RgSpace.s12),
            KeepAllText(n.titleKo ?? n.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: RgText.homeSummary.copyWith(color: RgColors.textBody)),
          ]),
        ),
        Transform.translate(
          offset: const Offset(4, -6),
          child: ItemActions(
            id: n.id, title: n.titleKo ?? n.titleEn, url: n.url, source: n.sourceLabel, kind: 'news',
            visualSize: 40, circleColor: tone?.ring ?? RgHome.ring,
          ),
        ),
      ]),
    );
  }
}

// 모델 카드: 큰 순위 숫자 → 이름 · 한 줄 설명 → 오른쪽 아래 라이선스 · 좋아요 · 다운로드
class HomeModelCard extends StatelessWidget {
  const HomeModelCard({super.key, required this.model});
  final TrendingModel model;

  @override
  Widget build(BuildContext context) {
    final m = model;
    return HomeCard(
      padding: const EdgeInsets.all(RgSpace.s20),
      onTap: () => context.push('/model/${Uri.encodeComponent(m.id)}'),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s16, children: [
        Semantics(label: '${m.rank}위', excludeSemantics: true, child: Text('${m.rank}', style: RgText.homeRank.copyWith(color: RgColors.textBody))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(m.name, style: RgText.homeTitle.copyWith(color: RgColors.textPrimary)),
            const SizedBox(height: RgSpace.s6),
            Text(modelSpec(m), maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.homeSummary.copyWith(color: RgColors.textSecondary)),
            const SizedBox(height: 25),
            Wrap(alignment: WrapAlignment.end, spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: [
              if (m.licenseKo != null) HomeStat(m.licenseKo!, label: '라이선스 ${m.licenseKo}'),
              HomeStat(countKo(m.likes ?? 0), icon: 'like-filled', label: '좋아요 ${countKo(m.likes ?? 0)}'),
              HomeStat(countKo(m.downloads ?? 0), icon: 'download-filled', label: '다운로드 ${countKo(m.downloads ?? 0)}'),
            ]),
          ]),
        ),
      ]),
    );
  }
}
