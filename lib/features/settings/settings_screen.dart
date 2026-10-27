import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../data/unread.dart';
import 'notices.dart';
import '../../design/widgets/rg_new_dot.dart';
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
        // 읽기 설정은 하위 화면으로(피드백 13 가안): 첫 화면에는 한 줄만
        group('읽기', first: true),
        _SettingsCard(children: [
          ListenableBuilder(
            listenable: Listenable.merge([readerDefaultMode, readerScale]),
            builder: (_, _) => _Row(
              label: '읽기 설정',
              value: '${readerModeLabel(readerDefaultMode.value)} · ${readerScaleLabel(readerScale.value)}',
              onTap: () => context.go('/settings/reading'),
            ),
          ),
        ]),
        group('안내'),
        _SettingsCard(children: [
          // 안 읽은 공지가 있으면 오른쪽에 새 글 점
          FutureBuilder(
            future: loadNotices(),
            builder: (context, snap) => ValueListenableBuilder(
              valueListenable: readItems,
              builder: (context, _, _) =>
                  _Row(label: '공지사항', dot: hasNewNotice(snap.data), onTap: () => context.go('/settings/notices')),
            ),
          ),
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
  const _Row({required this.label, this.value, this.onTap, this.chevron = true, this.dot = false});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  final bool dot; // 새 글

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(spacing: RgSpace.s4, children: [
        Expanded(child: Text(label, style: RgText.titleList)),
        if (dot) const Padding(padding: EdgeInsets.only(right: RgSpace.s4), child: RgNewDot()),
        // 큰 글자에서 값(「함께 · 기본」)이 넘치지 않게 줄을 바꾼다. Expanded: Flexible이면 값이 가운데부터 놓였다
        if (value != null)
          Expanded(
            child: KeepAllText(value!, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary), textAlign: TextAlign.end),
          ),
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

// 읽기 설정(피드백 13 가안): 초록 기본 보기와 글자 크기(예시와 함께).
class ReadingSettingsScreen extends StatelessWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(String title, String sub, Widget child) => RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(title, style: RgText.titleList)),
        const SizedBox(height: RgSpace.s4),
        KeepAllText(sub, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s14),
        child,
      ]),
    );
    return ListView(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
      children: [
        SizedBox(
          height: RgSpace.topBar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
            child: Row(children: [RgBackButton(onTap: () => context.pop())]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, RgSpace.s20),
          child: HeadingTextScale(child: Semantics(header: true, child: Text('읽기 설정', style: RgText.titleDetail))),
        ),
        card(
          '초록 기본 보기',
          '초록 리더를 열 때 처음 보이는 방식이에요',
          ValueListenableBuilder(
            valueListenable: readerDefaultMode,
            builder: (_, mode, _) => RgSegmented(
              options: const [(ReaderMode.together, '함께'), (ReaderMode.translation, '번역'), (ReaderMode.original, '원문')],
              value: mode,
              onChanged: (m) => readerDefaultMode.value = m,
            ),
          ),
        ),
        const SizedBox(height: RgSpace.s12),
        card('글자 크기', 'AI 요약·핵심 내용과 초록 리더 본문에 적용돼요', const TextSizePicker()),
      ],
    );
  }
}

// 데이터 출처 (G7, 시안 없음): 텍스트 화면.
class DataSourceScreen extends StatelessWidget {
  const DataSourceScreen({super.key});

  static const paragraphs = [
    'ROOTGIST는 Hugging Face Daily Papers에 매일 올라오는 논문을 모아요.',
    '그날 upvote가 많은 상위 10편을 골라요. 이 순서는 Hugging Face 이용자들의 반응이고, ROOTGIST가 논문을 평가한 결과가 아니에요.',
    '각 논문의 원문은 상세 화면의 Hugging Face·arXiv 링크에서 확인할 수 있어요. 논문 제목과 초록은 arXiv가 CC0으로 공개한 정보예요.',
    // 공식 소식·모델(docs/RIGHTS.md 3·4장): 출처와 「원문이 아니라 AI 정리」라는 점, 삭제 요청 창구를 밝힌다.
    '공식 소식은 OpenAI·Anthropic·Google DeepMind·Google Research·Hugging Face의 공식 블로그와 개발자 공지, Claude Code·SDK·API 릴리스 노트에서 모아요. 제목과 요약·핵심 내용은 AI가 원문을 보고 한국어로 정리한 것이고, 글 전체는 각 원문 링크에서 읽을 수 있어요.',
    '모델은 Hugging Face 트렌딩 순위와 각 모델 카드에 적힌 제작사 설명을 바탕으로 해요. 점수는 제작사가 직접 측정해 밝힌 값이에요.',
    '권리자가 요청하면 해당 내용을 바로 내려요. 문의하기($contactEmail)로 알려 주세요.',
    // 용어 사전 출처 표시 의무(CC BY 4.0·Apache 2.0, 연구 레포 term_collection_plan 3장).
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
              RgBackButton(onTap: () => context.pop()),
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
                for (final p in paragraphs) KeepAllText(p, perSentence: true, style: RgText.bodySummary.copyWith(color: RgColors.textBody)),
              ],
            ),
          ]),
        ),
      ],
    );
  }
}

// 개인정보 처리방침(G13): docs/privacy.md를 그대로 읽어 보여 준다. 같은 파일이 GitHub Pages 페이지다.
class PrivacyScreen extends DocScreen {
  const PrivacyScreen({super.key}) : super(asset: 'docs/privacy.md', webUrl: privacyPolicyUrl);
}

// 레포의 마크다운 문서 하나를 텍스트 화면으로(처리방침·공지사항).
class DocScreen extends StatefulWidget {
  const DocScreen({super.key, required this.asset, this.webUrl});
  final String asset;
  final String? webUrl; // 있으면 맨 아래 「웹에서 보기」

  @override
  State<DocScreen> createState() => _DocScreenState();
}

class _DocScreenState extends State<DocScreen> {
  late final _doc = rootBundle.loadString(widget.asset).then(markdownBlocks);

  @override
  Widget build(BuildContext context) {
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
                RgBackButton(onTap: () => context.pop()),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...markdownWidgets(snap.data ?? const []),
              if (widget.webUrl case final url?) ...[
                const SizedBox(height: RgSpace.s20),
                Semantics(
                  link: true,
                  child: RgPressable(
                    onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    child: Text('웹에서 보기 · $url', style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                  ),
                ),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

enum MdBlock { title, heading, bullet, paragraph }

// 문서 블록을 화면 글로(처리방침 화면, 공지 팝업).
List<Widget> markdownWidgets(List<(MdBlock, String)> blocks) {
  final body = RgText.bodySummary.copyWith(color: RgColors.textBody);
  return [
    for (final (kind, text) in blocks)
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
            Expanded(child: KeepAllText(text, perSentence: true, style: body)),
          ]),
        ),
        MdBlock.paragraph => Padding(
          padding: const EdgeInsets.only(bottom: RgSpace.s12),
          child: KeepAllText(text, perSentence: true, style: body),
        ),
      },
  ];
}

// docs/의 처리방침·공지에 쓰는 마크다운만 읽는다: 앞머리(---), #, ##, - 목록, 빈 줄로 나눈 문단.
List<(MdBlock, String)> markdownBlocks(String md) {
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
