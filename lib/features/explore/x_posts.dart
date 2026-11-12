import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../design/widgets/rg_states.dart';
import '../../data/unread.dart';
import '../home/home_sections.dart';
import '../reader/text_size_sheet.dart';

// X 글 화면 조각(2026-11-10). X 표시 규정에 맞춰 늘 작성자 이름·@핸들·시각·원문을 함께 보인다.
// 번역이 있으면 위에 한국어(「AI 번역」), 아래에 원문을 작게.
// 2026-11-11: 카드를 누르면 바로 X로 나가지 않고 앱 안 시트에서 번역 전문·원문을 먼저 읽는다. X는 시트의 「X에서 보기」로.

Future<List<XPost>> loadXPosts() => repository.listXPosts().catchError((Object _) => <XPost>[]);

Future<void> openXPostExternal(XPost p) async {
  HapticFeedback.selectionClick();
  await launchUrl(Uri.parse(p.url), mode: LaunchMode.externalApplication);
}

// 카드·반응 줄을 누르면 여는 X 글 시트: 작성자 → 번역 전문 → 원문 전문 → 반응 → 「X에서 보기」.
Future<void> showXPostSheet(BuildContext context, XPost p) {
  final ko = p.textKo;
  final meta = RgText.homeMeta.copyWith(color: RgColors.textSecondary);
  return showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: RgSpace.s4),
        Row(spacing: RgSpace.s8, children: [
          const RgChip('X'),
          Flexible(
            child: Text(p.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: RgText.homeMeta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary)),
          ),
          Flexible(child: Text('@${p.handle} · ${xAgo(p.postedAt, DateTime.now())}', maxLines: 1, overflow: TextOverflow.ellipsis, style: meta)),
        ]),
        const SizedBox(height: RgSpace.s16),
        // 번역·원문 본문은 앱의 「글자 크기」를 따른다(카드도 같게)
        ReaderTextScale(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            KeepAllText(ko ?? p.text, style: RgText.bodyDefinition),
            if (ko != null) ...[
              const SizedBox(height: RgSpace.s6),
              Text('AI 번역', style: RgText.caption.copyWith(color: RgColors.textTertiary)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: RgSpace.s16),
                child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
              ),
              // 원문은 접지 않는다(X 표시 규정: 번역과 함께 원문을 보인다)
              Text('원문', style: RgText.meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary)),
              const SizedBox(height: RgSpace.s6),
              Text(p.text, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
            ],
          ]),
        ),
        const SizedBox(height: RgSpace.s16),
        Wrap(spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: _stats(p)),
        const SizedBox(height: RgSpace.s24),
        RgPrimaryButton(label: 'X에서 보기', icon: 'arrow-up-right', onTap: () => openXPostExternal(p)),
      ],
    ),
  );
}

List<Widget> _stats(XPost p) => [
  HomeStat(countKo(p.likes), icon: 'heart', label: 'X 좋아요 ${countKo(p.likes)}'),
  if (p.reposts > 0) HomeStat('재게시 ${countKo(p.reposts)}', label: '재게시 ${countKo(p.reposts)}'),
  if (p.replies > 0) HomeStat(countKo(p.replies), icon: 'message-circle', label: '답글 ${countKo(p.replies)}'),
];

// 카드 본문: 정한 줄 수를 넘으면 끝에 흐린 「더 보기」를 붙여 시트에서 다 읽을 수 있다는 걸 알린다.
class _ClampedText extends StatelessWidget {
  const _ClampedText(this.text, {required this.maxLines, required this.style});
  final String text;
  final int maxLines;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
    // 카드는 몇 줄만 보여서 문단 사이 빈 줄이 한 줄을 차지하면 첫 문단 뒤가 빈 줄로 잘린다(2026-11-12). 빈 줄은 줄바꿈 하나로
    final shown = keepAll(text.trim().replaceAll(RegExp(r'\n\s*\n'), '\n'));
    final painter = TextPainter(
      text: TextSpan(text: shown, style: style),
      maxLines: maxLines,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: c.maxWidth);
    final cut = painter.didExceedMaxLines;
    painter.dispose();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(shown, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style, semanticsLabel: text),
      if (cut) ...[
        const SizedBox(height: RgSpace.s4),
        ExcludeSemantics(child: Text('더 보기', style: RgText.caption.copyWith(fontWeight: FontWeight.w600, color: RgColors.textTertiary))),
      ],
    ]);
  });
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
// 「적당히 새로운」 화제 순(2026-11-11): 커뮤니티 「전체」 칩이 쓴다(「X」 칩은 최신 순, 홈 혜택 카드는 좋아요 순).
// · 계정마다 평소보다 얼마나 떴나: 좋아요 ÷ 그 계정의 평소 좋아요(최근 3일 글의 중간값). OpenAI는 평범해도 1만,
//   소식 정리 계정은 300이면 크게 뜬 것이라 좋아요 그대로 세우면 큰 계정이 늘 위를 차지했다.
// · 시간 감쇠는 약하게: ÷ (지난 시간 + 2)^0.8. 좋아요는 수집 때와 4~30시간 뒤에만 다시 받아 막 들어온 글은 0에 가깝다.
//   세게 깎으면(HN의 1.8) 오래된 글이 너무 빨리 빠지고, 약하게 두면 새 글이 며칠 묵은 화제 글에 밀리지 않을 만큼만 올라온다.
// 글이 2개 미만인 계정은 평소 값을 알 수 없어 전체 글의 중간값을 쓴다.
List<XPost> rankXBuzz(Iterable<XPost> posts, {required Iterable<XPost> baseline, required DateTime now}) {
  double median(List<int> v) {
    if (v.isEmpty) return 0;
    v.sort();
    final m = v.length ~/ 2;
    return v.length.isOdd ? v[m].toDouble() : (v[m - 1] + v[m]) / 2;
  }

  final byHandle = <String, List<int>>{};
  for (final p in baseline) {
    (byHandle[p.handle.toLowerCase()] ??= []).add(p.likes);
  }
  final overall = median([for (final p in baseline) p.likes]);
  double usual(XPost p) {
    final v = byHandle[p.handle.toLowerCase()];
    return v == null || v.length < 2 ? overall : median([...v]);
  }

  double score(XPost p) {
    final hours = math.max(0, now.difference(p.postedAt).inMinutes / 60);
    return (p.likes + 1) / (usual(p) + 1) / math.pow(hours + 2, 0.8);
  }

  final scored = {for (final p in posts) p: score(p)};
  return scored.keys.toList()..sort((a, b) => scored[b]!.compareTo(scored[a]!));
}

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
      hint: '번역 전문 보기',
      child: HomeCard(
        radius: 20,
        padding: const EdgeInsets.all(RgSpace.s20),
        onTap: () => showXPostSheet(context, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              spacing: RgSpace.s8,
              children: [
                const RgChip('X'), // 다른 소식 카드와 같은 출처 칩
                Flexible(
                  child: Text(p.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RgText.homeMeta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary)),
                ),
                Flexible(
                  child: Text('@${p.handle} · ${xAgo(p.postedAt, now)}', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: RgText.homeMeta.copyWith(color: RgColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: RgSpace.s12),
            ReaderTextScale(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _ClampedText(
                  ko ?? p.text,
                  maxLines: compact ? 3 : 5,
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
              ]),
            ),
            const SizedBox(height: RgSpace.s16),
            Wrap(spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: _stats(p)),
          ],
        ),
      ),
    );
  }
}

// 발표 행 아래 「X 좋아요 5,200 · @ExampleLab」: 누르면 그 X 글 시트(행 전체 누르기와 겹치지 않게 이 줄만).
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
        onTap: () => showXPostSheet(context, post),
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
    _load();
    pullRefreshers.add(_load); // 당겨서 새로고침 때 X 글도 다시(30분마다 새로 모은다)
  }

  Future<void> _load() => loadXPosts().then((v) {
    _last = v;
    if (mounted) setState(() => _posts = v);
  });

  @override
  void dispose() {
    pullRefreshers.remove(_load);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = clock();
    // 혜택 카드는 좋아요 순 그대로(48시간 창이 이미 신선도를 거른다). 화제 순(rankXBuzz)을 써 보니 실데이터(11-11)에서
    // 2칸뿐인 카드에서 실제 리셋 발표(bcherny 1.3만)가 빠지고 「리셋 해 볼까?」 같은 암시 글이 올라왔다.
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
                subtitle: '사용량 초기화·무료 개방 같은 소식이에요. X에서 30분마다 모아요',
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
