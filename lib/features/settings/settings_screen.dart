import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_segmented.dart';
import '../reader/text_size_sheet.dart';
import 'ai_notice_sheet.dart';

// S06 설정 (HANDOFF 7.8).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget group(String label, {bool first = false}) => Padding(
          padding: EdgeInsets.fromLTRB(RgSpace.gutterText, first ? RgSpace.s20 : RgSpace.s28, RgSpace.gutterText, RgSpace.s8),
          child: Semantics(
            header: true,
            child: Text(label, style: RgText.meta.copyWith(fontWeight: FontWeight.w500, color: RgColors.textSecondary)),
          ),
        );

    return ListView(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
      children: [
        ChromeTextScale(
          child: SizedBox(
            height: RgSpace.topBar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
              child: Row(children: [
                Expanded(child: Semantics(header: true, child: Text('설정', style: RgText.titleDetail))),
                if (kDebugMode)
                  TextButton(onPressed: () => context.push('/gallery'), child: const Text('위젯 갤러리')),
              ]),
            ),
          ),
        ),
        group('읽기', first: true),
        _SettingsCard(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RgSpace.s16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('초록 기본 보기', style: RgText.titleList),
              const SizedBox(height: RgSpace.s12),
              ValueListenableBuilder(
                valueListenable: readerDefaultMode,
                builder: (_, mode, _) => RgSegmented(
                  options: const [
                    (ReaderMode.together, '함께'),
                    (ReaderMode.translation, '번역'),
                    (ReaderMode.original, '원문'),
                  ],
                  value: mode,
                  onChanged: (m) => readerDefaultMode.value = m,
                ),
              ),
            ]),
          ),
          ValueListenableBuilder(
            valueListenable: readerScale,
            builder: (_, s, _) => _Row(label: '글자 크기', value: readerScaleLabel(s), onTap: () => showTextSizeSheet(context)),
          ),
        ]),
        group('안내'),
        _SettingsCard(children: [
          _Row(label: 'AI 생성 안내', onTap: () => showAiNoticeSheet(context)),
          _Row(label: '데이터 출처', onTap: () => context.go('/settings/source')),
        ]),
        group('정보'),
        _SettingsCard(children: [
          _Row(label: '개인정보 처리방침', onTap: () => context.go('/settings/privacy')),
          _Row(
            label: '문의하기',
            onTap: () => _contact(context),
          ),
          _Row(label: '앱 버전', value: appVersion, chevron: false),
        ]),
        // M3 fixture 스위치: 8.1 상태를 재현한다. fixture로 띄운 디버그 빌드에만 보인다.
        if (kDebugMode && repository is FixtureRepository) ...[
          group('개발용 · fixture 상태'),
          ValueListenableBuilder(
            valueListenable: fixtureMode,
            builder: (_, mode, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
              child: Wrap(spacing: RgSpace.s8, children: [
                for (final m in FixtureMode.values)
                  RgFilterChip(label: m.name, selected: m == mode, onTap: () => fixtureMode.value = m),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

// 설정 카드: 좌우 여백 20, 행 사이 dividerCard(안쪽 폭).
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20),
      child: Column(children: [
        for (final (i, c) in children.indexed) ...[
          c,
          if (i < children.length - 1) const Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, this.value, this.onTap, this.chevron = true});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(spacing: RgSpace.s4, children: [
        Expanded(child: Text(label, style: RgText.titleList)),
        if (value != null) Text(value!, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        if (chevron) const RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
      ]),
    );
    return Semantics(button: onTap != null, child: RgPressable(onTap: onTap, child: row));
  }
}

// 메일 앱이 없거나(시뮬레이터, 기본 메일 앱 삭제) 열리지 않으면 주소를 복사해 알린다.
Future<void> _contact(BuildContext context) async {
  final opened = await launchUrl(Uri(scheme: 'mailto', path: contactEmail)).catchError((_) => false);
  if (opened || !context.mounted) return;
  await Clipboard.setData(const ClipboardData(text: contactEmail));
  if (!context.mounted) return;
  final bottom = MediaQuery.paddingOf(context).bottom;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: const Text('메일 앱을 열 수 없어 주소를 복사했어요 · $contactEmail'),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      // 떠 있는 탭바(64) 위로(S05 해제 스낵바와 같은 자리)
      margin: EdgeInsets.fromLTRB(RgSpace.gutterCard, 0, RgSpace.gutterCard, (bottom > 30 ? bottom : 30) + 64 + RgSpace.s8),
    ));
}

// 데이터 출처 (G7, 시안 없음): 텍스트 화면.
class DataSourceScreen extends StatelessWidget {
  const DataSourceScreen({super.key});

  static const paragraphs = [
    'ROOTGIST는 Hugging Face Daily Papers에 매일 올라오는 논문을 모아요.',
    '그날 upvote가 많은 상위 10편을 골라요. 이 순서는 Hugging Face 이용자들의 반응이고, ROOTGIST가 논문을 평가한 결과가 아니에요.',
    '각 논문의 원문은 상세 화면의 Hugging Face·arXiv 링크에서 확인할 수 있어요.',
    // 용어 사전 출처 표시 의무(CC BY 4.0·Apache 2.0, 연구 레포 term_collection_plan 3장). 권리 검토(A8) 때 문구 확정.
    '일부 용어의 한국어 표기는 Google 「Machine Learning Glossary」(CC BY 4.0)와 Hugging Face Transformers 문서 용어집(Apache 2.0)을 바탕으로 수정·번역했어요.',
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
      children: [
        SizedBox(
          height: RgSpace.topBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
            child: Row(children: [
              RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => context.pop()),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeadingTextScale(child: Semantics(header: true, child: Text('데이터 출처', style: RgText.titleDetail))),
            const SizedBox(height: RgSpace.s16),
            Column(
              spacing: RgSpace.s12,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in paragraphs) KeepAllText(p, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

// 개인정보 처리방침(G13): docs/privacy.md를 그대로 읽어 보여 준다. 같은 파일이 GitHub Pages 페이지다.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final _doc = rootBundle.loadString('docs/privacy.md').then(privacyBlocks);

  @override
  Widget build(BuildContext context) {
    final body = RgText.bodySummary.copyWith(color: RgColors.textBody);
    return FutureBuilder(
      future: _doc,
      builder: (context, snap) => ListView(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
        children: [
          SizedBox(
            height: RgSpace.topBar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
              child: Row(children: [
                RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => context.pop()),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (kind, text) in snap.data ?? const <(MdBlock, String)>[])
                switch (kind) {
                  MdBlock.title => Padding(
                    padding: const EdgeInsets.only(bottom: RgSpace.s16),
                    child: HeadingTextScale(child: Semantics(header: true, child: KeepAllText(text, style: RgText.titleDetail))),
                  ),
                  MdBlock.heading => Padding(
                    padding: const EdgeInsets.only(top: RgSpace.s20, bottom: RgSpace.s8),
                    child: Semantics(header: true, child: KeepAllText(text, style: RgText.titleSection)),
                  ),
                  MdBlock.bullet => Padding(
                    padding: const EdgeInsets.only(bottom: RgSpace.s6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
                      Text('·', style: body),
                      Expanded(child: KeepAllText(text, style: body)),
                    ]),
                  ),
                  MdBlock.paragraph => Padding(
                    padding: const EdgeInsets.only(bottom: RgSpace.s12),
                    child: KeepAllText(text, style: body),
                  ),
                },
              const SizedBox(height: RgSpace.s20),
              Semantics(
                link: true,
                child: RgPressable(
                  onTap: () => launchUrl(Uri.parse(privacyPolicyUrl), mode: LaunchMode.externalApplication),
                  child: Text('웹에서 보기 · $privacyPolicyUrl', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

enum MdBlock { title, heading, bullet, paragraph }

// docs/privacy.md에 쓰는 마크다운만 읽는다: 앞머리(---), #, ##, - 목록, 빈 줄로 나눈 문단.
List<(MdBlock, String)> privacyBlocks(String md) {
  var lines = md.split('\n');
  if (lines.firstOrNull?.trim() == '---') {
    final end = lines.indexWhere((l) => l.trim() == '---', 1);
    lines = lines.sublist(end + 1);
  }
  final out = <(MdBlock, String)>[];
  final para = <String>[];
  void flush() {
    if (para.isNotEmpty) out.add((MdBlock.paragraph, para.join(' ')));
    para.clear();
  }

  for (final raw in lines) {
    final l = raw.trim();
    if (l.isEmpty) {
      flush();
    } else if (l.startsWith('## ')) {
      flush();
      out.add((MdBlock.heading, l.substring(3)));
    } else if (l.startsWith('# ')) {
      flush();
      out.add((MdBlock.title, l.substring(2)));
    } else if (l.startsWith('- ')) {
      flush();
      out.add((MdBlock.bullet, l.substring(2)));
    } else {
      para.add(l);
    }
  }
  flush();
  return out;
}
