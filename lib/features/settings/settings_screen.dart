import '../../analytics/posthog_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/guide.dart';
import '../../data/repository.dart';
import '../../data/settings.dart';
import '../../data/unread.dart';
import 'notices.dart';
import '../../design/widgets/rg_new_dot.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../reader/text_size_sheet.dart';
import 'ai_notice_sheet.dart';

// S06 설정 (HANDOFF 7.8).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget group(String label, {bool first = false}) => Padding(
          padding: EdgeInsets.fromLTRB(RgSpace.gutterText, first ? RgSpace.s24 : RgSpace.s28, RgSpace.gutterText, RgSpace.s8),
          child: Semantics(
            header: true,
            child: Text(label, style: RgText.caption.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary)),
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
                Expanded(child: Semantics(header: true, child: Text('설정', style: RgText.display))),
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
              icon: 'type',
              label: '읽기 설정',
              value: '${readerModeLabel(readerDefaultMode.value)} · ${readerScaleLabel(readerScale.value)}',
              onTap: () => context.go('/settings/reading'),
            ),
          ),
        ]),
        group('안내'),
        _SettingsCard(children: [
          _Row(icon: 'circle-help', label: '사용 방법', onTap: () => context.go('/settings/guide')),
          // 안 읽은 공지가 있으면 오른쪽에 새 글 점
          FutureBuilder(
            future: loadNotices(),
            builder: (context, snap) => ValueListenableBuilder(
              valueListenable: readItems,
              builder: (context, _, _) =>
                  _Row(icon: 'bell', label: '공지사항', dot: hasNewNotice(snap.data), onTap: () => context.go('/settings/notices')),
            ),
          ),
          _Row(icon: 'sparkles', label: 'AI 생성 안내', onTap: () => showAiNoticeSheet(context)),
          _Row(icon: 'layers', label: '데이터 출처', onTap: () => context.go('/settings/source')),
        ]),
        group('사용 분석'),
        _SettingsCard(children: [
          // 디자인 피드백 2026-10-31 7번: 스위치는 제목 줄 오른쪽에 작게, 설명은 한 줄. 나머지(보내는 것·안 보내는 것·만 14세 미만)는 시트로
          ValueListenableBuilder(
            valueListenable: analyticsCollectionEnabled,
            builder: (_, enabled, _) => Padding(
              padding: const EdgeInsets.only(top: RgSpace.s12, bottom: RgSpace.s4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('사용 분석', style: RgText.bodySummary)),
                  // 누르는 영역(44)은 두고 보이는 크기만 줄인다
                  SizedBox(
                    height: 44,
                    child: Transform.scale(
                      scale: 0.8,
                      alignment: Alignment.centerRight,
                      child: Switch.adaptive(
                        key: const ValueKey('analytics-collection'),
                        activeThumbColor: RgColors.textPrimary,
                        // 꺼짐: 칩 면 트랙 + 흐린 손잡이(기본값은 어두운 화면에서 흰 테두리가 튄다)
                        inactiveTrackColor: RgColors.fillNeutral,
                        inactiveThumbColor: RgColors.textTertiary,
                        trackOutlineColor: WidgetStatePropertyAll(RgColors.borderDefault),
                        value: enabled,
                        onChanged: (value) {
                          HapticFeedback.selectionClick();
                          analyticsCollectionEnabled.value = value;
                        },
                      ),
                    ),
                  ),
                ]),
                KeepAllText('익명 사용 기록으로 앱을 개선해요 · 기본 꺼짐', style: RgText.caption.copyWith(color: RgColors.textSecondary)),
                Semantics(
                  button: true,
                  child: RgPressable(
                    onTap: () => _analyticsDetails(context),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 36),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: Text(
                          '보내는 정보 자세히',
                          style: RgText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                            color: RgColors.textBody,
                            decoration: TextDecoration.underline,
                            decorationColor: RgColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (!analytics.configured)
            Padding(
              padding: const EdgeInsets.only(bottom: RgSpace.s12),
              child: Text('이 빌드에는 분석 연결이 설정되어 있지 않아 전송하지 않아요.', style: RgText.caption),
            ),
          _Row(icon: 'trash', label: '분석 데이터 삭제 요청', onTap: () => _requestAnalyticsDeletion(context)),
        ]),
        group('정보'),
        _SettingsCard(children: [
          _Row(icon: 'file-text', label: '개인정보 처리방침', onTap: () => context.go('/settings/privacy')),
          _Row(icon: 'scale', label: '이용 안내', onTap: () => context.go('/settings/terms')),
          _Row(icon: 'book', label: '오픈소스 라이선스', onTap: () => _licenses(context)),
          // 주소를 값으로 두면 좁은 칸에서 「gmail.c / om」처럼 갈라져, 원래처럼 셰브론만(누르면 메일 앱)
          _Row(icon: 'mail', label: '문의하기', onTap: () => _contact(context)),
          _Row(icon: 'info', label: '앱 버전', value: appVersion, chevron: false),
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

// 설정 카드: 좌우 여백 16, 행 사이 dividerCard(아이콘 칸 뒤부터).
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s16),
      child: Column(children: [
        for (final (i, c) in children.indexed) ...[
          c,
          if (i < children.length - 1) Divider(height: 1, thickness: 1, color: RgColors.dividerCard, indent: 44),
        ],
      ]),
    );
  }
}

// 설정 한 줄: 왼쪽 아이콘 칸(32, 모서리 9, fill) + 이름 + 값·새 글 점·셰브론.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.icon, this.value, this.onTap, this.chevron = true, this.dot = false});
  final String label;
  final String icon;
  final String? value;
  final VoidCallback? onTap;
  final bool chevron;
  final bool dot; // 새 글

  @override
  Widget build(BuildContext context) {
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(spacing: RgSpace.s4, children: [
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(right: RgSpace.s8),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(9)),
          child: RgIcon(icon, size: 17, color: RgColors.textPrimary),
        ),
        Expanded(child: Text(label, style: RgText.titleList.copyWith(fontSize: 16, fontWeight: FontWeight.w500))),
        if (dot) const Padding(padding: EdgeInsets.only(right: RgSpace.s4), child: RgNewDot()),
        // 큰 글자에서 값(「함께 · 기본」)이 넘치지 않게 줄을 바꾼다. Expanded: Flexible이면 값이 가운데부터 놓였다
        if (value != null)
          Expanded(
            child: KeepAllText(value!, style: RgText.bodySmall.copyWith(color: RgColors.textSecondary), textAlign: TextAlign.end),
          ),
        if (chevron) RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
      ]),
    );
    return Semantics(button: onTap != null, child: RgPressable(onTap: onTap, child: row));
  }
}

// 메일 앱이 없거나(시뮬레이터, 기본 메일 앱 삭제) 열리지 않으면 주소를 복사해 알린다.
Future<void> _contact(BuildContext context, {String? subject, String? body}) async {
  // mailto 쿼리는 공백을 +가 아니라 %20으로(iOS 메일이 +를 그대로 보인다)
  final query = [
    if (subject != null) 'subject=${Uri.encodeComponent(subject)}',
    if (body != null) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  final opened = await launchUrl(Uri.parse('mailto:$contactEmail${query.isEmpty ? '' : '?$query'}')).catchError((_) => false);
  if (opened || !context.mounted) return;
  await Clipboard.setData(ClipboardData(text: body ?? contactEmail));
  if (!context.mounted) return;
  // 탭바 위 검정 알림(S05 해제 알림과 같은 자리·모양, 테마 snackBarTheme)
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(body == null
          ? '메일 앱을 열 수 없어 주소를 복사했어요 · $contactEmail'
          : '메일 앱을 열 수 없어 요청 내용을 복사했어요. $contactEmail로 보내 주세요'),
      duration: const Duration(seconds: 4),
    ));
}

// 「보내는 정보 자세히」: 설정 줄에서 줄인 사용 분석 안내 전문
Future<void> _analyticsDetails(BuildContext context) => showRgBottomSheet<void>(
  context,
  builder: (sheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const SizedBox(height: RgSpace.s4),
    Semantics(header: true, child: Text('사용 분석으로 보내는 정보', style: RgText.titleSection)),
    const SizedBox(height: RgSpace.s10),
    KeepAllText(
      '선택 사항이고 기본은 꺼져 있어요. 켜면 화면 방문·기능 사용·활성 독서 시간과 임의의 앱 식별자를 PostHog에 보내 앱을 개선해요. 본문·번역문·이메일은 보내지 않아요. 언제든 끌 수 있어요.',
      perSentence: true,
      style: RgText.bodySummary.copyWith(color: RgColors.textBody),
    ),
    const SizedBox(height: RgSpace.s12),
    KeepAllText('만 14세 미만이라면 켜지 말아 주세요.', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
    const SizedBox(height: RgSpace.s20),
    TextButton(
      onPressed: () {
        Navigator.pop(sheet);
        context.go('/settings/privacy');
      },
      child: Text('개인정보 처리방침 보기', style: RgText.bodySmall),
    ),
  ]),
);

// 처리방침 7장: 수집을 끄고 설치 식별자를 새로 바꾼 뒤, 이전 식별자를 적은 삭제 요청 메일을 준비한다.
// 한 번도 수집을 켜지 않았으면 보낸 기록이 없다고 알리고 끝낸다. 되돌릴 수 없는 동작이라 시트에서 한 번 더 묻는다.
Future<void> _requestAnalyticsDeletion(BuildContext context) async {
  final go = await showRgBottomSheet<bool>(
    context,
    builder: (sheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: RgSpace.s4),
      Semantics(header: true, child: Text('분석 데이터 삭제 요청', style: RgText.titleSection)),
      const SizedBox(height: RgSpace.s10),
      KeepAllText(
        '사용 분석을 끄고 이 기기의 앱 식별자를 새로 바꿔요. 이전 식별자로 쌓인 기록은 이어서 열리는 메일을 보내 주시면 찾아서 지워요. 북마크와 읽기 설정은 그대로예요.',
        perSentence: true,
        style: RgText.bodySummary.copyWith(color: RgColors.textBody),
      ),
      const SizedBox(height: RgSpace.s20),
      RgPrimaryButton(label: '끄고 삭제 요청하기', onTap: () => Navigator.pop(sheet, true)),
      const SizedBox(height: RgSpace.s8),
      TextButton(onPressed: () => Navigator.pop(sheet, false), child: Text('취소', style: RgText.bodySmall)),
    ]),
  );
  if (go != true || !context.mounted) return;
  HapticFeedback.mediumImpact();
  analyticsCollectionEnabled.value = false;
  final id = await analytics.forgetInstall();
  if (!context.mounted) return;
  if (id == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('이 기기에서 보낸 분석 데이터가 없어요. 수집은 꺼져 있어요.'), duration: Duration(seconds: 4)));
    return;
  }
  await _contact(
    context,
    subject: 'ROOTGIST 분석 데이터 삭제 요청',
    body: '아래 앱 식별자로 수집된 사용 분석 데이터를 지워 주세요.\n\n앱 식별자: $id\n요청 시각: ${DateTime.now().toIso8601String()}\n',
  );
}

// 오픈소스 라이선스: Flutter 패키지 고지 + 글꼴(OFL)·아이콘(Lucide, ISC). 글꼴·아이콘 고지는 main에서 등록한다.
void _licenses(BuildContext context) => showLicensePage(
  context: context,
  applicationName: 'ROOTGIST',
  applicationVersion: appVersion,
  useRootNavigator: true,
);

// 읽기 설정(피드백 13 가안): 초록 기본 보기와 글자 크기(예시와 함께).
class ReadingSettingsScreen extends StatelessWidget {
  const ReadingSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(String title, String sub, Widget child) => RgCard(
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s20, vertical: RgSpace.s18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(title, style: RgText.titleList.copyWith(fontWeight: FontWeight.w700))),
        const SizedBox(height: RgSpace.s2),
        KeepAllText(sub, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s16),
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
            builder: (_, mode, _) => Column(children: [
              for (final (i, (m, desc)) in const [
                (ReaderMode.together, '번역 아래 원문을 맞대어 보여요'),
                (ReaderMode.translation, '한국어 번역만 보여요'),
                (ReaderMode.original, '영어 원문만 보여요'),
              ].indexed)
                _RadioRow(
                  label: readerModeLabel(m),
                  desc: desc,
                  selected: m == mode,
                  divider: i > 0,
                  onTap: () => readerDefaultMode.value = m,
                ),
            ]),
          ),
        ),
        const SizedBox(height: RgSpace.s12),
        card('글자 크기', 'AI 요약·핵심 내용과 초록 리더 본문에 적용돼요', const TextSizePicker()),
        const SizedBox(height: RgSpace.s12),
        // 화면 모드: 기본은 기기 설정을 따른다
        card(
          '화면 모드',
          '기기의 다크 모드를 따르거나 밝게·어둡게로 고정해요',
          ValueListenableBuilder(
            valueListenable: appearance,
            builder: (_, a, _) => Column(children: [
              for (final (i, (v, label, desc)) in const [
                (Appearance.system, '기기 설정', '기기의 다크 모드를 따라가요'),
                (Appearance.light, '밝게', '늘 밝은 화면'),
                (Appearance.dark, '어둡게', '늘 어두운 화면'),
              ].indexed)
                _RadioRow(
                  label: label,
                  desc: desc,
                  selected: v == a,
                  divider: i > 0,
                  trailing: _BackdropSwatch(
                    palette: switch (v) {
                      Appearance.dark => RgPalette.dark,
                      Appearance.light => RgPalette.white,
                      Appearance.system => platformDark.value ? RgPalette.dark : RgPalette.white,
                    },
                  ),
                  onTap: () => appearance.value = v,
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// 라디오 한 줄: 동그라미(고르면 검정 7pt 테두리) + 이름 + 설명. 행 전체를 누른다.
class _RadioRow extends StatelessWidget {
  const _RadioRow({
    required this.label,
    required this.desc,
    required this.selected,
    required this.divider,
    required this.onTap,
    this.trailing,
  });
  final String label, desc;
  final bool selected, divider;
  final VoidCallback onTap;
  final Widget? trailing; // 오른쪽 견본(화면 모드)

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    button: true,
    child: RgPressable(
      onTap: () {
        if (!selected) HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RgSpace.s14),
        decoration: BoxDecoration(border: divider ? Border(top: BorderSide(color: RgColors.dividerCard)) : null),
        child: Row(spacing: RgSpace.s12, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: selected
                  ? Border.all(color: RgColors.textPrimary, width: 7)
                  : Border.all(color: RgColors.textTertiary, width: 1.5),
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: RgText.titleList),
              KeepAllText(desc, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
            ]),
          ),
          ?trailing,
        ]),
      ),
    ),
  );
}

// 화면 모드 견본: 바탕 위에 카드 하나와 새 글 점(고르기 전에 차이가 보이게). 지금 모드와 상관없이 그 팔레트 색.
class _BackdropSwatch extends StatelessWidget {
  const _BackdropSwatch({required this.palette});
  final RgPalette palette;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 52,
      height: 38,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: palette.bgApp,
        borderRadius: BorderRadius.circular(RgRadius.badge),
        border: Border.all(color: palette.line),
      ),
      child: Container(
        alignment: Alignment.topRight,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: palette.surfaceCard,
          borderRadius: BorderRadius.circular(5), // 한쪽만 테두리면 모서리를 줄 수 없어 사방 테두리
          border: Border.all(color: palette.line),
        ),
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: palette.newDot, shape: BoxShape.circle)),
      ),
    ),
  );
}

// 데이터 출처 (G7, 시안 없음): 텍스트 화면.
class DataSourceScreen extends StatelessWidget {
  const DataSourceScreen({super.key});

  static const paragraphs = [
    'ROOTGIST는 Hugging Face Daily Papers에 매일 올라오는 논문을 모아요.',
    '그날 upvote가 많은 상위 10편을 골라요. 이 순서는 Hugging Face 이용자들의 반응이고, ROOTGIST가 논문을 평가한 결과가 아니에요.',
    '각 논문의 원문은 상세 화면의 Hugging Face·arXiv 링크에서 확인할 수 있어요. 논문 제목과 초록은 arXiv가 CC0으로 공개한 정보예요.',
    // 공식 소식·모델(docs/RIGHTS.md 3·4장): 출처와 「원문이 아니라 AI 정리」라는 점, 삭제 요청 창구를 밝힌다.
    '공식 소식은 OpenAI·Anthropic·Google DeepMind·Google Research·Hugging Face·Meta·NVIDIA의 공식 블로그(Hugging Face 블로그에 회사 계정이 쓴 글 포함)와 개발자 공지, Claude Code·SDK·API 릴리스 노트에서 모아요. 데이터센터·AI 인프라 소식은 Google·Microsoft·Amazon 공식 블로그에서 그 주제 글만 골라요. 제목과 요약·핵심 내용은 AI가 원문을 보고 한국어로 정리한 것이고, 글 전체는 각 원문 링크에서 읽을 수 있어요.',
    '「개발자 화제」는 Hacker News에서 개발자들이 많이 본 AI 글과 GitHub의 새 AI 저장소예요. 숫자는 Hacker News 추천(upvote) 수·GitHub 별 수이고, 요약은 원문 사이트가 허용할 때만 만들어요.',
    '모델은 Hugging Face 트렌딩 순위와 각 모델 카드에 적힌 제작사 설명을 바탕으로 해요. 점수는 제작사가 직접 측정해 밝힌 값이에요.',
    // 출처 배지의 회사 대표 색(RgBrand)과 함께 둔다(docs/RIGHTS.md 4장)
    '표시된 회사·제품 이름은 각 소유자의 상표예요. ROOTGIST는 이 회사들과 제휴하거나 후원받지 않으며, 출처 배지의 색은 출처를 구분하려고 쓴 것이에요.',
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

class TermsScreen extends DocScreen {
  const TermsScreen({super.key}) : super(asset: 'docs/terms.md', webUrl: termsUrl);
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


// 설정 › 사용 방법(시안 design-preview/src/onboarding_guide.html 3장): 기능 사용법·자주 묻는 질문·다시 보기·문의.
// 회원가입·로그인이 없어 그 문답은 두지 않고, 이 앱에 실제로 생길 질문(번역 오류, 저장, 사용 기록, 데이터 삭제)을 둔다.
// 개발 용어(캐시·토큰·API)를 쓰지 않는다. 사용법 줄을 누르면 그 화면으로 간다.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const _faq = [
    ('새 소식은 언제 올라와요?', '공식 소식과 개발자 화제는 하루 두 번, 아침 6시쯤과 오후 1시쯤 모아요. X 글(회사·소식 계정)은 30분마다 받아 바로 한국어로 옮겨요. 논문은 매일 아침 올라와요. 주말에는 arXiv와 Hugging Face에 새 논문이 거의 올라오지 않아, 일·월요일엔 가장 최근 논문을 보여 드려요. 홈 오른쪽 위에서 다음 수집 시각을 볼 수 있어요.'),
    ('어디의 소식을 모아요?', 'OpenAI·Anthropic·Google·Meta·NVIDIA 같은 곳의 공식 블로그와 Hacker News·GitHub 화제, Hugging Face 인기 모델이에요. 전체 목록은 설정 › 데이터 출처에 있어요.'),
    ('요약이나 번역이 틀린 것 같아요', '요약과 번역은 AI가 원문을 보고 만들어서 틀릴 수 있어요. 중요한 내용은 원문 링크에서 확인해 주시고, 아래 「문의하기」로 알려 주시면 고칠게요.'),
    ('회원가입이나 로그인이 필요한가요?', '아니요. 설치하면 바로 쓸 수 있고, 이름이나 이메일을 받지 않아요.'),
    ('저장한 글이 사라졌어요', '저장한 글과 읽기 설정은 이 기기에만 남아요. 앱을 지웠다 다시 설치하거나 기기를 바꾸면 옮겨지지 않아요.'),
    ('사용 기록을 보내나요?', '기본으로는 보내지 않아요. 설정 › 사용 분석을 켠 경우에만 화면 방문 같은 익명 기록을 보내고, 본문이나 이메일은 보내지 않아요.'),
    ('데이터를 지우고 싶어요', '저장한 글과 설정은 앱을 지우면 함께 지워져요. 사용 분석으로 보낸 기록은 설정 › 분석 데이터 삭제 요청으로 지울 수 있어요.'),
  ];

  @override
  Widget build(BuildContext context) {
    Widget group(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s28, RgSpace.gutterText, RgSpace.s8),
      child: Semantics(header: true, child: Text(label, style: RgText.caption.copyWith(fontWeight: FontWeight.w600, color: RgColors.textSecondary))),
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
          padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            HeadingTextScale(child: Semantics(header: true, child: Text('사용 방법', style: RgText.titleDetail))),
            const SizedBox(height: RgSpace.s6),
            KeepAllText('회원가입 없이 바로 써요. 저장한 글은 이 기기에만 남아요.', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary)),
          ]),
        ),
        group('기능 사용법'),
        _SettingsCard(children: [
          _HowRow(title: '오늘의 주요 소식 보기', steps: const ['홈', '오늘의 주요 소식'], onTap: () => context.go('/home')),
          _HowRow(title: '회사별 소식 보기', steps: const ['탐색', '소식', '회사 칩'], onTap: () => context.go('/explore')),
          _HowRow(title: '어려운 용어 뜻 보기', steps: const ['형광펜 용어', '뜻·예시'], marked: 0),
          _HowRow(title: '논문을 번역과 함께 읽기', steps: const ['탐색', '논문', '번역과 함께 읽기'], onTap: () => context.go('/explore')),
          _HowRow(title: '나중에 읽을 글 저장하기', steps: const ['저장 버튼', '보관함'], icons: const {0: 'bookmark'}, onTap: () => context.go('/library')),
          _HowRow(title: '글자 크기·어두운 화면', steps: const ['설정', '읽기 설정'], onTap: () => context.go('/settings/reading')),
        ]),
        group('자주 묻는 질문'),
        _SettingsCard(children: [for (final (q, a) in _faq) _FaqRow(question: q, answer: a)]),
        group('다시 보기'),
        _SettingsCard(children: [
          _Row(icon: 'book', label: '처음 안내 다시 보기', onTap: () => context.push('/welcome')),
          _Row(
            icon: 'sparkles',
            label: '도움말 다시 보기',
            chevron: false,
            onTap: () {
              HapticFeedback.selectionClick();
              tipsSeen.value = {};
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('읽기 화면과 소식에서 도움말이 다시 떠요'), duration: Duration(seconds: 3)));
            },
          ),
        ]),
        group('문의 · 약관'),
        _SettingsCard(children: [
          _Row(icon: 'mail', label: '문의하기', onTap: () => _contact(context)),
          _Row(icon: 'scale', label: '이용 안내', onTap: () => context.go('/settings/terms')),
          _Row(icon: 'file-text', label: '개인정보 처리방침', onTap: () => context.go('/settings/privacy')),
        ]),
      ],
    );
  }
}

// 사용법 한 줄: 제목 + 누르는 순서를 버튼 모양 조각으로(「홈 › 논문 카드 › 원문과 번역 보기」). marked는 형광펜 색 조각.
class _HowRow extends StatelessWidget {
  const _HowRow({required this.title, required this.steps, this.onTap, this.marked, this.icons = const {}});
  final String title;
  final List<String> steps; // 화면 읽기는 이 글자로 읽는다
  final VoidCallback? onTap;
  final int? marked;
  final Map<int, String> icons; // 앱에서 글자 없이 아이콘인 버튼은 그 아이콘으로(책갈피)

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: RgSpace.s16),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: RgText.titleList.copyWith(fontSize: 16)),
            const SizedBox(height: RgSpace.s10),
            Semantics(
              label: steps.join(', 다음 '),
              child: ExcludeSemantics(
                child: Wrap(spacing: RgSpace.s4, runSpacing: RgSpace.s6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  for (final (i, s) in steps.indexed) ...[
                    if (i > 0) RgIcon('chevron-right', size: 14, color: RgColors.textTertiary),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s10, vertical: RgSpace.s4),
                      decoration: BoxDecoration(
                        color: i == marked ? RgColors.highlight : RgColors.fillNeutral,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: switch (icons[i]) {
                        final icon? => RgIcon(icon, size: 16, color: RgColors.textPrimary),
                        _ => Text(s, style: RgText.caption.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary)),
                      },
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
        if (onTap != null) RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
      ]),
    );
    return Semantics(button: onTap != null, child: RgPressable(onTap: onTap, child: row));
  }
}

// 자주 묻는 질문 한 줄: 누르면 답이 펼쳐진다(높이 220ms, 화살표가 아래 → 위로 돌아감). 「동작 줄이기」면 바로.
class _FaqRow extends StatefulWidget {
  const _FaqRow({required this.question, required this.answer});
  final String question, answer;

  @override
  State<_FaqRow> createState() => _FaqRowState();
}

class _FaqRowState extends State<_FaqRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final d = RgMotion.of(context, RgMotion.base);
    return Semantics(
      button: true,
      expanded: _open,
      child: RgPressable(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _open = !_open);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: RgSpace.s16),
          child: AnimatedSize(
            duration: d,
            curve: RgMotion.curve,
            alignment: Alignment.topCenter,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(spacing: RgSpace.s8, children: [
                Expanded(child: KeepAllText(widget.question, style: RgText.titleList.copyWith(fontSize: 16))),
                AnimatedRotation(
                  turns: _open ? -0.25 : 0.25,
                  duration: d,
                  curve: RgMotion.curve,
                  child: RgIcon('chevron-right', size: 16, color: RgColors.textTertiary),
                ),
              ]),
              if (_open)
                Padding(
                  padding: const EdgeInsets.only(top: RgSpace.s8),
                  child: KeepAllText(widget.answer, perSentence: true, style: RgText.bodySmall.copyWith(color: RgColors.textBody)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
