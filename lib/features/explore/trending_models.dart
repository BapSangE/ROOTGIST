import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../design/widgets/rg_states.dart';
import '../../design/widgets/rg_new_dot.dart';
import '../common/item_actions.dart';
import '../home/home_sections.dart';
import 'date_groups.dart';
import 'news_detail.dart' show modelSpec;

// S04 「모델」 칸(PROPOSALS P9 A안): Hugging Face 모델. 「트렌딩 | 새로 나옴」 두 칸. 누르면 모델 상세.
// 트렌딩: HF 트렌딩 순 10개(홈 모델 카드, 큰 순위 숫자). 새로 나옴: 트렌딩 100위 안에서 최근 14일 안에 공개된 모델, 최신순 10개.
// 같은 모델의 양자화판·형제 모델은 수집기가 원래 모델 아래로 묶는다(「변형 N개」).
class TrendingModelsSection extends StatefulWidget {
  const TrendingModelsSection({super.key, required this.fresh});
  final bool fresh; // 도구 칸의 「새 모델」(ToolsSection이 정한다)

  @override
  State<TrendingModelsSection> createState() => _TrendingModelsSectionState();
}

class _TrendingModelsSectionState extends State<TrendingModelsSection> {
  // 받은 값을 들고 있어 도구 칸 안에서 모델 ↔ GitHub를 오가도 빈 틀이 다시 보이지 않는다(새로 받는 동안 지난 값)
  static List<TrendingModel>? _last;
  final _req = Reloadable(() => repository.listTrendingModels().then((v) => _last = v));
  bool get _fresh => widget.fresh;

  @override
  void dispose() {
    _req.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_req, readItems, modelsSeen]),
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        initialData: _last,
        builder: (context, snap) {
          final all = snap.data ?? const <TrendingModel>[];
          if (all.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => noteModels(all.map((m) => m.id)),
            );
          }
          final now = clock();
          // 새로 나옴은 최신순(트렌딩 순이면 트렌딩 칸과 거의 같았다). 같은 날이면 트렌딩 순
          final models = _fresh
              ? (all.where((m) => m.isNew(now)).toList()
                      ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!)))
                    .take(10)
                    .toList()
              : all.where((m) => m.rank <= 10).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              ExploreSectionNote(_fresh ? 'Hugging Face에 최근 2주 안에 공개된 모델이에요' : 'Hugging Face에서 요즘 주목받는 모델이에요'),
              RgFilterSwitch(
                switchKey: _fresh,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (snap.hasError) ...[
                      const SizedBox(height: RgSpace.s20),
                      RgErrorCard(error: snap.error, onRetry: _req.reload),
                    ] else if (!snap.hasData)
                      const RgSkeleton(
                        child: Padding(
                          padding: EdgeInsets.only(top: RgSpace.s20),
                          child: RgSkeletonRows(count: 5),
                        ),
                      )
                    else if (models.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          RgSpace.gutterText,
                          RgSpace.s24,
                          RgSpace.gutterText,
                          0,
                        ),
                        child: KeepAllText(
                          _fresh ? '최근 2주 안에 공개된 모델이 아직 없어요' : '아직 모은 모델이 없어요',
                          style: RgText.bodySmall.copyWith(
                            color: RgColors.textSecondary,
                          ),
                        ),
                      )
                    else if (_fresh) ...[
                      const SizedBox(height: RgSpace.s16),
                      // 새로 나옴: 공개일로 묶는다(최근 7일은 하루씩, 그 앞은 주). 큰 순위 대신 「3일 전 공개」
                      DateGroups<TrendingModel>(
                        items: models,
                        at: (m) => m.createdAt!,
                        tag: (m) => m.author,
                        now: now,
                        showDayHeaders: false,
                        builder: (context, rows) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: RgSpace.gutterText,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: RgSpace.s16,
                            children: [
                              for (final m in rows)
                                _ExploreModelCard(model: m, fresh: true),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      // 트렌딩: 홈 「모델 트렌드 순위」 카드 그대로(큰 순위 숫자), 10개
                      const SizedBox(height: RgSpace.s20),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: RgSpace.gutterText,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: RgSpace.s16,
                          children: [
                            for (final m in models) _ExploreModelCard(model: m),
                          ],
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RgSpace.gutterText,
                        RgSpace.s20,
                        RgSpace.gutterText,
                        0,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: RgSpace.s6,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: RgIcon(
                              'info',
                              size: 14,
                              color: RgColors.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: KeepAllText(
                              _fresh
                                  ? '최근 2주 안에 공개된 모델을 새것부터 보여 줘요. Hugging Face 트렌딩 100위 안에 든 모델만 모았어요.'
                                  : '요즘 Hugging Face에서 주목받는 모델이에요. 순서는 Hugging Face의 트렌딩 순위예요.',
                              perSentence: true,
                              style: RgText.caption.copyWith(
                                color: RgColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// 트렌딩은 순위, New는 만든 곳과 공개일을 강조하는 카드다.
class _ExploreModelCard extends StatelessWidget {
  const _ExploreModelCard({required this.model, this.fresh = false});
  final TrendingModel model;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final date = m.createdAt?.toUtc().add(const Duration(hours: 9));
    final stats = Wrap(
      alignment: WrapAlignment.end,
      spacing: RgSpace.s6,
      runSpacing: RgSpace.s6,
      children: [
        if (m.licenseKo != null)
          HomeStat(m.licenseKo!, label: '라이선스 ${m.licenseKo}'),
        HomeStat(
          countKo(m.likes ?? 0),
          icon: 'thumbs-up',
          label: '좋아요 ${countKo(m.likes ?? 0)}',
        ),
        HomeStat(
          countKo(m.downloads ?? 0),
          icon: 'download',
          label: '다운로드 ${countKo(m.downloads ?? 0)}',
        ),
      ],
    );
    return HomeCard(
      radius: 20,
      padding: const EdgeInsets.all(RgSpace.s20),
      onTap: () => context.push('/model/${Uri.encodeComponent(m.id)}'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RgSpace.s16,
        children: [
          // 시안: 순위 칸 폭 고정(한 자리 30, 두 자리 46) → 같은 자릿수끼리 이름 시작점이 맞는다.
          // 「새로 진입」 점은 따로 한 줄을 차지하지 않게 순위 숫자 바로 아래에 붙인다(나타날 때 180ms 페이드·확대).
          if (!fresh)
            SizedBox(
              width: m.rank < 10 ? 30 : 46,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    label: '${m.rank}위',
                    excludeSemantics: true,
                    child: Text(
                      '${m.rank}',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: RgText.homeRank.copyWith(
                        color: RgColors.textBody,
                      ),
                    ),
                  ),
                  ValueListenableBuilder(
                    valueListenable: modelsSeen,
                    builder: (context, _, _) => Padding(
                      padding: const EdgeInsets.only(top: RgSpace.s8, left: 2),
                      child: RgNewLabel(
                        visible: enteredModel(m.id),
                        label: '새로 진입',
                      ),
                    ),
                  ),
                ],
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: RgText.homeTitle,
                          ),
                          const SizedBox(height: RgSpace.s6),
                          Text(
                            fresh
                                ? '${m.maker} · ${modelSpec(m)}'
                                : modelSpec(m),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: RgText.homeSummary.copyWith(
                              color: RgColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    modelActions(m, visualSize: 40),
                  ],
                ),
                const SizedBox(height: RgSpace.s24),
                if (fresh && date != null)
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: RgSpace.s8,
                    runSpacing: RgSpace.s8,
                    children: [
                      // 공개일 바로 옆에 「새로 진입」 점(따로 한 줄 차지하지 않게)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: RgSpace.s6,
                        children: [
                          Text(
                            '${date.month}월 ${date.day}일',
                            style: RgText.homeMeta.copyWith(
                              color: RgColors.textSecondary,
                            ),
                          ),
                          ValueListenableBuilder(
                            valueListenable: modelsSeen,
                            builder: (context, _, _) => RgNewLabel(
                              visible: enteredModel(m.id),
                              label: '새로 진입',
                            ),
                          ),
                        ],
                      ),
                      stats,
                    ],
                  )
                else
                  stats,
                if (m.variants.isNotEmpty) ...[
                  const SizedBox(height: RgSpace.s4),
                  VariantsLine(model: m),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 「3일 전 공개」 「오늘 공개」
String publishedAgo(DateTime created, DateTime now) =>
    switch (now.difference(created).inDays) {
      0 => '오늘 공개',
      final d => '$d일 전 공개',
    };

ItemActions modelActions(
  TrendingModel m, {
  RgCircleVariant variant = RgCircleVariant.neutral,
  bool share = false,
  double? visualSize,
}) => ItemActions(
  id: m.id,
  title: m.name,
  url: m.url,
  source: 'Hugging Face',
  kind: 'model',
  variant: variant,
  share: share,
  visualSize: visualSize,
);

// 「변형 2개 · Omni-2B, VL-2B ›」: 누르면 아래로 펼쳐 변형마다 이름 · 만든 곳 · 양자화판/형제 모델(220ms 접힘,
// 보관함과 같은 SizeTransition). 행 전체 누르기(상세)와 겹치지 않게 이 줄만 따로 누른다. 선택 틱.
class VariantsLine extends StatefulWidget {
  const VariantsLine({super.key, required this.model});
  final TrendingModel model;

  @override
  State<VariantsLine> createState() => _VariantsLineState();
}

class _VariantsLineState extends State<VariantsLine> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final vs = widget.model.variants;
    final fg = RgColors.textSecondary;
    final style = RgText.meta.copyWith(color: fg);
    final d = RgMotion.of(context, RgMotion.base);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          label: '변형 ${vs.length}개',
          excludeSemantics: true,
          onTap: _toggle,
          child: RgPressable(
            onTap: _toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: RgSpace.minTouch),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '변형 ${vs.length}개 · ${vs.map((v) => _short(v.name)).join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: d,
                    curve: RgMotion.curve,
                    child: RgIcon('chevron-right', size: 14, color: fg),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: d,
          curve: RgMotion.curve,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: RgSpace.s4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: RgSpace.s4,
                    children: [
                      for (final v in vs)
                        KeepAllText(
                          '${v.name} · ${v.author} · ${v.quantized ? '양자화판' : '형제 모델'}',
                          style: style,
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _open = !_open);
  }

  // 원래 모델 이름을 뺀 꼬리(LFM3-1.7B의 LFM3-VL-2B → VL-2B). 겹치는 앞부분이 없으면 이름 그대로
  String _short(String name) {
    final base = widget.model.name;
    var i = 0;
    while (i < name.length && i < base.length && name[i] == base[i]) {
      i++;
    }
    final tail = name.substring(i).replaceFirst(RegExp(r'^[-_.]+'), '');
    return i >= 3 && tail.isNotEmpty ? tail : name;
  }
}

@visibleForTesting
void resetTrendingModels() => _TrendingModelsSectionState._last = null;
