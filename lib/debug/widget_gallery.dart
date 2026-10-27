import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../design/widgets/rg_bottom_sheet.dart';
import '../design/widgets/rg_bottom_tab_bar.dart';
import '../design/widgets/rg_buttons.dart';
import '../design/widgets/rg_card.dart';
import '../design/widgets/rg_segmented.dart';

// M1 디버그 갤러리: 공통 위젯 9개를 상태별로 모아 본다. 디버그 빌드에서 설정 탭으로 진입.
class WidgetGallery extends StatefulWidget {
  const WidgetGallery({super.key});

  @override
  State<WidgetGallery> createState() => _WidgetGalleryState();
}

class _WidgetGalleryState extends State<WidgetGallery> {
  var _tab = 0;
  var _chip = '전체';
  var _mode = 'together';
  var _saved = false;

  @override
  Widget build(BuildContext context) {
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: RgSpace.s28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(title, style: RgText.titleSection),
              ),
              child,
            ],
          ),
        );
    const pad = EdgeInsets.symmetric(horizontal: RgSpace.gutterText);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: RgSpace.bottomScrollInset),
          children: [
            SizedBox(
              height: RgSpace.topBar,
              child: Row(children: [
                const SizedBox(width: RgSpace.gutterCard),
                RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: RgSpace.s12),
                Text('위젯 갤러리', style: RgText.titleSection),
              ]),
            ),
            section(
              'RgBottomTabBar',
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: RgBottomTabBar(
                  tabs: const [RgTab('홈', 'house'), RgTab('탐색', 'compass'), RgTab('보관함', 'bookmark'), RgTab('설정', 'settings')],
                  currentIndex: _tab,
                  onTap: (i) => setState(() => _tab = i),
                ),
              ),
            ),
            section(
              'RgFilterChip',
              SizedBox(
                height: RgSpace.minTouch,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: pad,
                  itemCount: 5,
                  separatorBuilder: (_, _) => const SizedBox(width: RgSpace.s8),
                  itemBuilder: (_, i) {
                    final label = const ['전체', '언어 모델', '에이전트', '멀티모달', '모델 최적화'][i];
                    return RgFilterChip(label: label, selected: _chip == label, onTap: () => setState(() => _chip = label));
                  },
                ),
              ),
            ),
            section(
              'RgPrimaryButton (48 / 56)',
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: Column(spacing: RgSpace.s16, children: [
                  RgPrimaryButton(label: '자세히 읽기', onTap: () {}),
                  RgPrimaryButton(label: '번역과 함께 초록 읽기', floating: true, onTap: () {}),
                  RgNeutralButton(label: '닫기', onTap: () {}),
                ]),
              ),
            ),
            section(
              'RgCircleButton',
              Padding(
                padding: pad,
                child: Wrap(spacing: RgSpace.s8, runSpacing: RgSpace.s8, children: [
                  RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () {}),
                  RgCircleButton(semanticLabel: '공유', icon: 'share', onTap: () {}),
                  RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', variant: RgCircleVariant.neutral, onTap: () {}),
                  RgCircleButton(semanticLabel: '글자 크기', text: '가', variant: RgCircleVariant.neutral, onTap: () {}),
                  RgBookmarkButton(saved: _saved, onTap: () => setState(() => _saved = !_saved)),
                  RgBookmarkButton(saved: _saved, size: 48, onTap: () => setState(() => _saved = !_saved)),
                  RgBookmarkButton(saved: _saved, variant: RgCircleVariant.plain, onTap: () => setState(() => _saved = !_saved)),
                ]),
              ),
            ),
            section(
              'RgCard + RgListRow',
              RgCard(
                child: Column(children: [
                  for (var i = 0; i < 3; i++)
                    RgListRow(
                      showDivider: i < 2,
                      onTap: () {},
                      trailing: RgBookmarkButton(saved: i == 1, variant: RgCircleVariant.plain, onTap: () {}),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('언어 모델', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                        const SizedBox(height: RgSpace.s4),
                        Text('가상 논문 제목 ${i + 1}: 목록 행이 두 줄로 넘어갈 때의 모양을 확인한다', style: RgText.titleList),
                        const SizedBox(height: RgSpace.s4),
                        Text('2026.10.18 · 홍길동 외', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                      ]),
                    ),
                ]),
              ),
            ),
            section(
              'RgBadge (onCard / onBg)',
              const Padding(
                padding: pad,
                child: Row(spacing: RgSpace.s8, children: [
                  RgBadge(label: '언어 모델'),
                  RgBadge(label: '지연', onCard: false),
                ]),
              ),
            ),
            section(
              'RgSegmented',
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: RgSegmented(
                  options: const [('together', '함께'), ('translation', '번역'), ('original', '원문')],
                  value: _mode,
                  onChanged: (v) => setState(() => _mode = v),
                ),
              ),
            ),
            section(
              'RgBottomSheet',
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: RgPrimaryButton(
                  label: '시트 열기',
                  onTap: () => showRgBottomSheet<void>(
                    context,
                    builder: (context) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 22),
                        Text('용어', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                        const SizedBox(height: RgSpace.s6),
                        Text('inference-time compute', style: RgText.serifTerm),
                        const SizedBox(height: RgSpace.s24),
                        RgNeutralButton(label: '닫기', onTap: () => Navigator.of(context).pop()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
