import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../../design/widgets/rg_states.dart';
import '../../design/widgets/rg_underline_tabs.dart';
import '../common/item_actions.dart';
import '../home/home_sections.dart';
import 'date_groups.dart';

// S04 「모델」 칸(PROPOSALS P9 A안): Hugging Face 모델. 「트렌딩 | 새로 나옴」 두 칸. 누르면 모델 상세.
// 트렌딩: HF 트렌딩 순 10개(홈 모델 카드, 큰 순위 숫자). 새로 나옴: 트렌딩 100위 안에서 최근 14일 안에 공개된 모델, 최신순 10개.
// 같은 모델의 양자화판·형제 모델은 수집기가 원래 모델 아래로 묶는다(「변형 N개」).
class TrendingModelsSection extends StatefulWidget {
  const TrendingModelsSection({super.key});

  @override
  State<TrendingModelsSection> createState() => _TrendingModelsSectionState();
}

class _TrendingModelsSectionState extends State<TrendingModelsSection> {
  final _req = Reloadable(repository.listTrendingModels);
  late var _fresh = modelsFresh.value = exploreJump.value?.fresh ?? false; // 「새로 나옴」 칸

  // 옆으로 밀기로 트렌딩 ↔ 새로 나옴(쉘의 밀기 순서가 정한다)
  void _jump() {
    final j = exploreJump.value;
    if (j != null && j.tab == 2 && mounted) setState(() => _fresh = modelsFresh.value = j.fresh);
  }

  void _pick(bool fresh) => setState(() => _fresh = modelsFresh.value = fresh);

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
      listenable: Listenable.merge([_req, readItems, modelsSeen]),
      builder: (context, _) => FutureBuilder(
        future: _req.future,
        builder: (context, snap) {
          final all = snap.data ?? const <TrendingModel>[];
          if (all.isNotEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => noteModels(all.map((m) => m.id)));
          final now = clock();
          // 새로 나옴은 최신순(트렌딩 순이면 트렌딩 칸과 거의 같았다). 같은 날이면 트렌딩 순
          final models = _fresh
              ? (all.where((m) => m.isNew(now)).toList()..sort((a, b) => b.createdAt!.compareTo(a.createdAt!))).take(10).toList()
              : all.where((m) => m.rank <= 10).toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              const SizedBox(height: RgSpace.s8),
              RgUnderlineTabs(
                labels: const ['트렌딩', '새로 나옴'],
                selected: _fresh ? 1 : 0,
                onTap: (i) => _pick(i == 1),
              ),
              RgFilterSwitch(
                switchKey: _fresh,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s16, RgSpace.gutterText, 0),
                    child: KeepAllText(
                      _fresh
                          ? '최근 2주 안에 공개된 모델을 새것부터 보여 줘요. Hugging Face 트렌딩 100위 안에 든 모델만 모았어요.'
                          : '요즘 Hugging Face에서 주목받는 모델이에요. 순서는 Hugging Face의 트렌딩 순위예요.',
                      perSentence: true, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
                    ),
                  ),
                  if (snap.hasError) ...[
                    const SizedBox(height: RgSpace.s20),
                    RgErrorCard(error: snap.error, onRetry: _req.reload),
                  ] else if (snap.connectionState != ConnectionState.done)
                    const RgSkeleton(child: Padding(padding: EdgeInsets.only(top: RgSpace.s20), child: RgSkeletonRows(count: 5)))
                  else if (models.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
                      child: KeepAllText(
                        _fresh ? '최근 2주 안에 공개된 모델이 아직 없어요' : '아직 모은 모델이 없어요',
                        style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
                      ),
                    )
                  else if (_fresh)
                    // 새로 나옴: 공개일로 묶는다(최근 7일은 하루씩, 그 앞은 주). 큰 순위 대신 「3일 전 공개」
                    DateGroups<TrendingModel>(
                      items: models,
                      at: (m) => m.createdAt!,
                      now: now,
                      builder: (context, rows) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s16, children: [
                          for (final m in rows) HomeModelCard(model: m, explore: true, ago: publishedAgo(m.createdAt!, now)),
                        ]),
                      ),
                    )
                  else ...[
                    // 트렌딩: 홈 「모델 트렌드 순위」 카드 그대로(큰 순위 숫자), 10개
                    const SizedBox(height: RgSpace.s20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: RgSpace.s16, children: [
                        for (final m in models) HomeModelCard(model: m, explore: true),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

// 「3일 전 공개」 「오늘 공개」
String publishedAgo(DateTime created, DateTime now) => switch (now.difference(created).inDays) {
  0 => '오늘 공개',
  final d => '$d일 전 공개',
};

ItemActions modelActions(TrendingModel m, {RgCircleVariant variant = RgCircleVariant.neutral, bool share = false, double? visualSize}) =>
    ItemActions(id: m.id, title: m.name, url: m.url, source: 'Hugging Face', kind: 'model', variant: variant, share: share, visualSize: visualSize);

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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        button: true,
        expanded: _open,
        label: '변형 ${vs.length}개',
        excludeSemantics: true,
        onTap: _toggle,
        child: RgPressable(
          onTap: _toggle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
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
            ]),
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
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
                  for (final v in vs)
                    KeepAllText('${v.name} · ${v.author} · ${v.quantized ? '양자화판' : '형제 모델'}', style: style),
                ]),
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
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
