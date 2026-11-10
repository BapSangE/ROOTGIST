import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../data/unread.dart';
import '../home/home_sections.dart';

// X 글 화면 조각(2026-11-10). X 표시 규정에 맞춰 늘 작성자 이름·@핸들·시각·원문을 함께 보이고, 누르면 X에서 연다.
// 번역이 있으면 위에 한국어(「AI 번역」), 아래에 원문을 작게.

Future<List<XPost>> loadXPosts() => repository.listXPosts().catchError((Object _) => <XPost>[]);

Future<void> openXPost(XPost p) async {
  HapticFeedback.selectionClick();
  await launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
}

// 「3시간 전」 「어제」 「10월 17일」
String xAgo(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)}분 전';
  if (d.inHours < 24) return '${d.inHours}시간 전';
  final k = at.toUtc().add(const Duration(hours: 9));
  return '${k.month}월 ${k.day}일';
}

// 소식 링크 → 그 소식을 단 X 글(좋아요가 가장 많은 것). 발표 카드의 「X 반응」에 쓴다.
Map<String, XPost> xByLink(List<XPost> posts) {
  final out = <String, XPost>{};
  for (final p in posts) {
    for (final l in p.links) {
      final k = normUrl(l);
      if ((out[k]?.likes ?? -1) < p.likes) out[k] = p;
    }
  }
  return out;
}

class XPostCard extends StatelessWidget {
  const XPostCard({super.key, required this.post, required this.now, this.compact = false});
  final XPost post;
  final DateTime now;
  final bool compact; // 홈 혜택 카드: 원문은 한 줄만

  @override
  Widget build(BuildContext context) {
    final p = post;
    final ko = p.textKo;
    return Semantics(
      button: true,
      hint: 'X에서 열기',
      child: HomeCard(
        radius: 20,
        padding: const EdgeInsets.all(RgSpace.s20),
        onTap: () => openXPost(p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: RgSpace.s8,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: RgColors.textPrimary, borderRadius: BorderRadius.circular(6)),
                  child: Text('X', style: RgText.caption.copyWith(color: RgColors.bgApp, fontWeight: FontWeight.w700, height: 1)),
                ),
                Flexible(
                  child: Text(p.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RgText.homeMeta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary)),
                ),
                Flexible(
                  child: Text('@${p.handle} · ${xAgo(p.postedAt, now)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RgText.homeMeta.copyWith(color: RgColors.textSecondary)),
                ),
                const Spacer(),
                RgIcon('arrow-up-right', size: 16, color: RgColors.textTertiary),
              ],
            ),
            const SizedBox(height: RgSpace.s12),
            KeepAllText(
              ko ?? p.text,
              maxLines: compact ? 3 : 5,
              overflow: TextOverflow.ellipsis,
              style: RgText.titleList.copyWith(fontSize: 16, height: 25 / 16, fontWeight: FontWeight.w500),
            ),
            if (ko != null) ...[
              const SizedBox(height: RgSpace.s6),
              Text(
                p.text,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: RgText.caption.copyWith(color: RgColors.textSecondary),
              ),
              const SizedBox(height: RgSpace.s4),
              Text('AI 번역', style: RgText.caption.copyWith(color: RgColors.textTertiary)),
            ],
            const SizedBox(height: RgSpace.s16),
            Wrap(
              spacing: RgSpace.s6,
              runSpacing: RgSpace.s6,
              children: [
                HomeStat(countKo(p.likes), icon: 'heart', label: 'X 좋아요 ${countKo(p.likes)}'),
                if (p.reposts > 0) HomeStat('재게시 ${countKo(p.reposts)}', label: '재게시 ${countKo(p.reposts)}'),
                if (p.replies > 0) HomeStat(countKo(p.replies), icon: 'message-circle', label: '답글 ${countKo(p.replies)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 발표 행 아래 「X 좋아요 5,200 · @ExampleLab」: 누르면 그 X 글을 연다(행 전체 누르기와 겹치지 않게 이 줄만).
class XReactionLine extends StatelessWidget {
  const XReactionLine({super.key, required this.post});
  final XPost post;

  @override
  Widget build(BuildContext context) {
    final fg = RgColors.textSecondary;
    return Semantics(
      button: true,
      label: 'X 반응: 좋아요 ${countKo(post.likes)}, @${post.handle} 글 열기',
      excludeSemantics: true,
      child: RgPressable(
        onTap: () => openXPost(post),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: RgSpace.s4,
            children: [
              RgIcon('heart', size: 13, color: fg),
              Flexible(
                child: Text('X 좋아요 ${countKo(post.likes)} · @${post.handle}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: RgText.homeMeta.copyWith(color: fg)),
              ),
              RgIcon('chevron-right', size: 12, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

// 홈 맨 위 「혜택·한도 소식」(최근 48시간에 혜택·한도 낱말이 있는 X 글, 좋아요 순 최대 2개). 없으면 그리지 않는다.
// 받은 값을 들고 있어 홈을 다시 그려도 높이가 튀지 않는다. 나타날 때 220ms 페이드·크기 펼침(「동작 줄이기」면 바로).
class XPerkSection extends StatefulWidget {
  const XPerkSection({super.key});

  @override
  State<XPerkSection> createState() => _XPerkSectionState();
}

class _XPerkSectionState extends State<XPerkSection> {
  static List<XPost>? _last;
  List<XPost>? _posts = _last;

  @override
  void initState() {
    super.initState();
    loadXPosts().then((v) {
      _last = v;
      if (mounted) setState(() => _posts = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = clock();
    final perks = [
      for (final p in _posts ?? const <XPost>[])
        if (p.perk && now.difference(p.postedAt) < const Duration(hours: 48)) p,
    ]..sort((a, b) => b.likes.compareTo(a.likes));
    final d = RgMotion.of(context, RgMotion.base);
    return AnimatedSize(
      duration: d,
      curve: RgMotion.curve,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: d,
        child: perks.isEmpty
            ? const SizedBox(width: double.infinity)
            : HomeSection(
                key: const ValueKey('perks'),
                title: '혜택·한도 소식',
                subtitle: '사용량 초기화·무료 개방 같은 소식을 X에서 먼저 모았어요',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: RgSpace.s16,
                  children: [for (final p in perks.take(2)) XPostCard(post: p, now: now, compact: true)],
                ),
              ),
      ),
    );
  }
}

// 테스트에서 지난 값을 비운다
@visibleForTesting
void resetXPerks() => _XPerkSectionState._last = null;
