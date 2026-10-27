import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
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
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s16, RgSpace.gutterText, 0),
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
                const SizedBox(height: RgSpace.s16),
                RgCard(child: Column(children: [for (final (i, m) in models.indexed) ModelRow(model: m, last: i == models.length - 1)])),
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
        SizedBox(
          width: RgSpace.s20,
          child: Text('${m.rank}', style: RgText.meta.copyWith(height: 23 / 13, fontWeight: FontWeight.w600, color: RgColors.textSecondary)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
            Text(m.name, style: RgText.titleList),
            KeepAllText(modelLine(m), style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
            // 「다운로드 12 / 만」처럼 숫자와 단위가 갈라지지 않게 어절 단위로 줄을 바꾼다
            KeepAllText(
              [?m.licenseKo, '좋아요 ${countKo(m.likes ?? 0)}', '다운로드 ${countKo(m.downloads ?? 0)}'].join(' · '),
              style: RgText.meta.copyWith(color: RgColors.textSecondary),
            ),
          ]),
        ),
      ]),
    );
  }
}

ItemActions modelActions(TrendingModel m, {RgCircleVariant variant = RgCircleVariant.plain}) =>
    ItemActions(id: m.id, title: m.name, url: m.url, source: 'Hugging Face', kind: 'model', variant: variant);
