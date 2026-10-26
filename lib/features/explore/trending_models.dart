import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models.dart';
import '../../data/repository.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_states.dart';
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
                  style: RgText.bodySmall.copyWith(color: RgColors.textSecondary),
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
                RgCard(
                  child: Column(children: [
                    for (final (i, m) in models.indexed)
                      RgListRow(
                        showDivider: i < models.length - 1,
                        onTap: () => context.go('/explore/model/${Uri.encodeComponent(m.id)}'),
                        trailing: const Padding(
                          padding: EdgeInsets.only(top: 2, right: RgSpace.s12),
                          child: RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
                          SizedBox(
                            width: RgSpace.s20,
                            child: Text('${m.rank}', style: RgText.meta.copyWith(height: 23 / 13, fontWeight: FontWeight.w600, color: RgColors.textSecondary)),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
                              Text(m.name, style: RgText.titleList),
                              KeepAllText(modelLine(m), style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
                              Text(
                                [?m.licenseKo, '좋아요 ${countKo(m.likes ?? 0)}', '다운로드 ${countKo(m.downloads ?? 0)}'].join(' · '),
                                style: RgText.meta.copyWith(color: RgColors.textSecondary),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
