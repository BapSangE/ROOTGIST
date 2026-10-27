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
import 'news_detail.dart';

// S04 「모델」 칸(PROPOSALS P9 A안): Hugging Face 트렌딩 모델 순위. 누르면 모델 상세.
class TrendingModelsSection extends StatefulWidget {
  const TrendingModelsSection({super.key});

  @override
  State<TrendingModelsSection> createState() => _TrendingModelsSectionState();
}

class _TrendingModelsSectionState extends State<TrendingModelsSection> {
  final _req = Reloadable(repository.listTrendingModels);

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
          final models = snap.data ?? const <TrendingModel>[];
          return ListView(
            padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s20, RgSpace.gutterText, 0),
                child: KeepAllText(
                  '요즘 Hugging Face에서 주목받는 모델이에요. 순서는 Hugging Face의 트렌딩 순위예요.',
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
                  child: KeepAllText('아직 모은 모델이 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
                )
              else ...[
                // 1위는 다크 카드(레퍼런스 007·016), 2위부터 카드 안 목록
                const SizedBox(height: RgSpace.s20),
                TopModelCard(model: models.first),
                if (models.length > 1) ...[
                  const SizedBox(height: RgSpace.s12),
                  RgCard(
                    child: Column(children: [
                      for (final (i, m) in models.skip(1).indexed) ModelRow(model: m, last: i == models.length - 2),
                    ]),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

// 모델 한 줄(탐색 목록, 홈 하이라이트): 순위 + 이름 + 한 줄 설명 + 라이선스·반응. 오른쪽에 공유·북마크.
class ModelRow extends StatelessWidget {
  const ModelRow({super.key, required this.model, required this.last});
  final TrendingModel model;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final m = model;
    return RgListRow(
      showDivider: !last,
      onTap: () => context.push('/model/${Uri.encodeComponent(m.id)}'),
      trailing: modelActions(m),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
        // 큰 순위 숫자(피드백 3차 A안). 1위만 검정, 나머지는 회색
        // 「10」·큰 글자에서도 칸(36)을 넘지 않게 줄여 넣는다
        SizedBox(
          width: 36,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(
              '${m.rank}',
              style: RgText.rank.copyWith(height: 1.0, color: m.rank == 1 ? RgColors.textPrimary : RgColors.textTertiary),
            ),
          ),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
            Text(m.name, style: RgText.titleList),
            KeepAllText(modelLine(m), style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
            // 라이선스·반응은 태그로. 「다운로드 12 / 만」처럼 숫자와 단위가 갈라지지 않게 태그 안에서는 어절 단위
            Padding(
              padding: const EdgeInsets.only(top: RgSpace.s4),
              child: Wrap(spacing: RgSpace.s6, runSpacing: RgSpace.s6, children: [
                if (m.licenseKo case final l?) RgTag(label: l),
                RgTag(label: keepAll('좋아요 ${countKo(m.likes ?? 0)}')),
                RgTag(label: keepAll('다운로드 ${countKo(m.downloads ?? 0)}')),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

ItemActions modelActions(TrendingModel m, {RgCircleVariant variant = RgCircleVariant.neutral, bool share = false}) =>
    ItemActions(id: m.id, title: m.name, url: m.url, source: 'Hugging Face', kind: 'model', variant: variant, share: share);

// 트렌딩 1위 다크 카드: 머리말 · 이름 · 한 줄 설명 · 라이선스·좋아요·다운로드 3칸. 누르면 모델 상세.
class TopModelCard extends StatelessWidget {
  const TopModelCard({super.key, required this.model});
  final TrendingModel model;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final sub = RgText.meta.copyWith(color: RgColors.onInkSecondary);
    Widget stat(String label, String value, {bool first = false}) => Expanded(
      child: Container(
        padding: EdgeInsets.only(left: first ? 0 : RgSpace.s14),
        decoration: BoxDecoration(border: first ? null : const Border(left: BorderSide(color: RgColors.lineOnInk))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s2, children: [
          Text(label, style: sub.copyWith(fontSize: 12.5)),
          KeepAllText(value, style: RgText.titleList.copyWith(color: RgColors.onAction)),
        ]),
      ),
    );
    return Semantics(
      button: true,
      child: RgPressable(
        onTap: () => context.push('/model/${Uri.encodeComponent(m.id)}'),
        child: RgDarkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: RgSpace.s4),
                  child: Text('TRENDING #${m.rank}', semanticsLabel: '트렌딩 ${m.rank}위', style: RgText.caps.copyWith(color: RgColors.onInkSecondary)),
                ),
              ),
              Transform.translate(
                offset: const Offset(RgSpace.s10, -RgSpace.s10),
                child: modelActions(m, variant: RgCircleVariant.glass),
              ),
            ]),
            Text(m.name, style: RgText.titleFeatured.copyWith(color: RgColors.onAction)),
            const SizedBox(height: RgSpace.s4),
            KeepAllText(modelLine(m), style: sub),
            const SizedBox(height: RgSpace.s20),
            Container(
              padding: const EdgeInsets.only(top: RgSpace.s16),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: RgColors.lineOnInk))),
              child: IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  stat('라이선스', m.licenseKo ?? '정보 없음', first: true),
                  stat('좋아요', countKo(m.likes ?? 0)),
                  stat('다운로드', countKo(m.downloads ?? 0)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
