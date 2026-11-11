import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/guide.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../design/widgets/rg_row_head.dart';
import '../common/collect_schedule.dart';

// 첫 실행 온보딩 5장. 회원가입·권한 요청이 없어 마지막 장에서 바로 시작한다.
// 2026-11-10 개편(「설명이 빈약하고 장점이 덜 드러난다」): 장마다 장점 하나, 설명은 두 줄 이내, 핵심 낱말은 굵게(**…**).
// 모으기 → 출처 → 혜택·한도(X) → 논문 3줄·형광펜 → 수집 일정.
// 좌우로 밀거나 「이전」·「다음」으로 넘긴다. 장이 넘어갈 때마다 가벼운 진동, 점 표시가 늘어난다(220ms).
// 설정 › 사용 방법에서 다시 열면(쌓인 화면이 있으면) 끝낼 때 닫히고, 첫 실행이면 홈으로 간다.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Slide {
  const _Slide(this.title, this.body, this.art);
  final String title, body;
  final Widget art;
}

const _slides = [
  _Slide('흩어진 AI 소식,\n아침마다 한국어로', '**공식 발표·논문·X 글**을 매일 모아 핵심만 정리해요.', _GatherArt()),
  _Slide('어디서 온 소식인지\n한눈에', '글마다 **출처**가 붙어 있어, 공식 발표와 커뮤니티 글을 바로 구분해요.', _ExploreArt()),
  // 다른 앱에 없는 장점: 사용량 초기화·무료 개방은 X에 먼저 나온다(홈 맨 위 「혜택·한도 소식」)
  _Slide('무료 개방·한도 초기화,\n먼저 알려 드려요', 'X에서 **30분마다** 모아 홈 맨 위에 보여 드려요.', _PerkArt()),
  _Slide('논문은 3줄,\n어려운 말은 형광펜', '**3줄 요약**으로 훑고, 형광펜을 누르면 **뜻과 예시**가 나와요.', _PaperArt()),
  // 새 소식이 언제 오는지 몰라 자꾸 열어 보지 않게 하루 두 번의 시각과 주말에 논문이 비는 이유를 알린다(사용자 요청 2026-11-09)
  _Slide('하루 두 번,\n새로 모아요', '**아침 6시·오후 1시**에 새로 모아요. 주말엔 가장 최근 논문을 보여 드려요.', _ScheduleArt()),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pages = PageController();
  var _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  bool get _last => _page == _slides.length - 1;

  void _go(int page) {
    if (page < 0 || page >= _slides.length) return;
    final d = RgMotion.of(context, const Duration(milliseconds: 260));
    if (d == Duration.zero) {
      _pages.jumpToPage(page);
    } else {
      _pages.animateToPage(page, duration: d, curve: RgMotion.curve);
    }
  }

  void _finish() {
    HapticFeedback.lightImpact();
    onboardingDone.value = true;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: RgColors.bgApp,
      body: Padding(
        padding: EdgeInsets.only(top: padding.top, bottom: padding.bottom > 0 ? padding.bottom : RgSpace.s20),
        child: Column(children: [
          ChromeTextScale(
            child: SizedBox(
              height: RgSpace.topBar,
              child: Align(
                alignment: Alignment.centerRight,
                // 마지막 장에서는 「시작하기」가 같은 일을 해서 숨긴다(자리는 남겨 위아래가 흔들리지 않게)
                child: AnimatedOpacity(
                  opacity: _last ? 0 : 1,
                  duration: RgMotion.of(context, RgMotion.fast),
                  child: IgnorePointer(
                    ignoring: _last,
                    child: Semantics(
                      button: true,
                      child: RgPressable(
                        onTap: _finish,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText, vertical: RgSpace.s12),
                          child: Text('건너뛰기', style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w500, color: RgColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: _slides.length,
              onPageChanged: (i) {
                HapticFeedback.selectionClick();
                setState(() => _page = i);
              },
              itemBuilder: (context, i) => _SlideView(slide: _slides[i], controller: _pages, index: i),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s24, RgSpace.gutterText, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Semantics(
                label: '${_slides.length}장 중 ${_page + 1}번째',
                child: ExcludeSemantics(
                  child: Row(spacing: RgSpace.s6, children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: RgMotion.of(context, RgMotion.base),
                        curve: RgMotion.curve,
                        width: i == _page ? 22 : 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: i == _page ? RgColors.textPrimary : RgColors.grabber,
                          borderRadius: BorderRadius.circular(RgRadius.pill),
                        ),
                      ),
                  ]),
                ),
              ),
              const SizedBox(height: RgSpace.s20),
              ChromeTextScale(
                child: Row(spacing: RgSpace.s8, children: [
                  // 첫 장에는 이전이 없다. 버튼 폭이 바뀌는 대신 「이전」 원이 접혔다 펴진다
                  AnimatedSize(
                    duration: RgMotion.of(context, RgMotion.base),
                    curve: RgMotion.curve,
                    child: _page == 0
                        ? const SizedBox(height: 56)
                        : RgCircleButton(
                            semanticLabel: '이전',
                            icon: 'chevron-left',
                            size: 56,
                            variant: RgCircleVariant.neutral,
                            onTap: () => _go(_page - 1),
                          ),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: RgPrimaryButton(
                        // 「다음」이 마지막 장에서 「시작하기」로 글자만 바뀐다
                        label: _last ? '시작하기' : '다음',
                        floating: true,
                        onTap: _last ? _finish : () => _go(_page + 1),
                      ),
                    ),
                  ),
                ]),
              ),
              AnimatedOpacity(
                opacity: _last ? 1 : 0,
                duration: RgMotion.of(context, RgMotion.fast),
                child: Padding(
                  padding: const EdgeInsets.only(top: RgSpace.s12),
                  child: Text(
                    '회원가입 없이 바로 써요 · 요약과 번역은 AI가 만들어요',
                    textAlign: TextAlign.center,
                    style: RgText.caption.copyWith(color: RgColors.textSecondary),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// 한 장: 위는 그림, 아래는 제목·설명. 넘기는 동안 그림은 손가락을 따라오고 글은 조금 늦게 따라온다(시차).
class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.controller, required this.index});
  final _Slide slide;
  final PageController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions ? controller.page ?? 0 : 0.0;
        final shift = still ? 0.0 : (index - page) * 40; // 글이 그림보다 40pt 늦게
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterText),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // appear: 이 장이 화면 한가운데 올수록 1(그림 안 줄이 넘기는 손을 따라 떠오른다). 동작 줄이기면 늘 1
            Expanded(
              child: _Appear(
                value: still ? 1 : (1 - (index - page).abs()).clamp(0.0, 1.0),
                child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: slide.art)),
              ),
            ),
            Transform.translate(
              offset: Offset(shift, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                HeadingTextScale(
                  child: Semantics(
                    header: true,
                    child: Text(slide.title, style: RgText.titleDetail.copyWith(fontSize: 28, height: 37 / 28, letterSpacing: -0.7)),
                  ),
                ),
                const SizedBox(height: RgSpace.s12),
                _Body(slide.body),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

// ── 그림: 실제 화면 모양을 작게 그려 들어가면 바로 알아보게 한다(글자는 예시) ──

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 300,
    padding: const EdgeInsets.all(RgSpace.s18),
    decoration: BoxDecoration(color: RgColors.surfaceCard, borderRadius: BorderRadius.circular(22), boxShadow: RgShadow.card),
    child: child,
  );
}

// 설명: **…**는 굵게(본문색보다 한 단계 진하게). 화면 읽기에는 별표 없는 문장을 넘긴다.
class _Body extends StatelessWidget {
  const _Body(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = RgText.bodySummary.copyWith(fontSize: 16.5, color: RgColors.textBody);
    final bold = style.copyWith(fontWeight: FontWeight.w700, color: RgColors.textPrimary);
    final parts = text.split('**');
    return Text.rich(
      TextSpan(style: style, children: [
        for (var i = 0; i < parts.length; i++) TextSpan(text: keepAll(parts[i]), style: i.isOdd ? bold : null),
      ]),
      semanticsLabel: parts.join(),
    );
  }
}

// 1장: 여러 출처 칩이 바깥에서 모여 로고를 둘러싼다. 첫 장은 넘겨 들어오지 않아 처음 한 번 스스로 모인다(700ms, 칩마다 조금씩 늦게).
// 「동작 줄이기」면 처음부터 모인 모습.
class _GatherArt extends StatefulWidget {
  const _GatherArt();

  @override
  State<_GatherArt> createState() => _GatherArtState();
}

class _GatherArtState extends State<_GatherArt> with SingleTickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  // (이름, 칩 색 출처, 각도(도), 반지름 비율)
  static const _chips = [
    ('OpenAI', 'openai', -90.0, 1.0),
    ('Anthropic', 'anthropic', -38.0, 1.0),
    ('X', null, 8.0, 0.92),
    ('Hugging Face', 'huggingface', 52.0, 1.0),
    ('arXiv', null, 98.0, 0.95),
    ('Google DeepMind', 'deepmind', 140.0, 1.0),
    ('Hacker News', null, 186.0, 0.98),
    ('GitHub', null, 228.0, 0.9),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else if (_intro.isDismissed) {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appear = _Appear.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        width: 320,
        height: 300,
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) => Stack(alignment: Alignment.center, children: [
            for (var i = 0; i < _chips.length; i++)
              () {
                final (label, source, deg, r) = _chips[i];
                final start = i * 0.06;
                final t = RgMotion.curve.transform(((_intro.value - start) / (1 - 0.42)).clamp(0.0, 1.0)) * appear;
                final rad = deg * math.pi / 180;
                final dist = r * (1.55 - 0.55 * t); // 바깥(1.55배)에서 고리(1배)로
                return Align(
                  alignment: Alignment(math.cos(rad) * 0.78 * dist, math.sin(rad) * 0.8 * dist),
                  child: Opacity(opacity: t, child: RgChip(label, source: source)),
                );
              }(),
            Transform.scale(
              scale: 0.86 + 0.14 * RgMotion.curve.transform(_intro.value),
              // 책 두 쪽은 숯색(#0E0E0D)이라 어두운 바탕에서 사라진다: 글자색으로 바꿔 그린다(주황 모서리는 그대로)
              child: SvgPicture.asset('assets/branding/rootgist_symbol.svg', width: 104, height: 104,
                  colorMapper: _InkMapper(RgColors.textPrimary)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _InkMapper extends ColorMapper {
  const _InkMapper(this.ink);
  final Color ink;

  @override
  Color substitute(String? id, String elementName, String attributeName, Color color) =>
      color.toARGB32() == 0xFF0E0E0D ? ink : color;

  @override
  bool operator ==(Object other) => other is _InkMapper && other.ink == ink;

  @override
  int get hashCode => ink.hashCode;
}

// 3장: 홈 맨 위 「혜택·한도 소식」 카드(XPostCard와 같은 차례). 장이 들어오면 알림처럼 위에서 내려앉는다.
// 계정·글은 예시라 실제 회사 이름을 쓰지 않는다.
class _PerkArt extends StatelessWidget {
  const _PerkArt();

  @override
  Widget build(BuildContext context) {
    final t = RgMotion.curve.transform(((_Appear.of(context) - 0.3) / 0.7).clamp(0.0, 1.0));
    final meta = RgText.caption.copyWith(fontSize: 12.5, color: RgColors.textSecondary);
    return ExcludeSemantics(
      child: SizedBox(
        width: 300,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: RgSpace.s4, bottom: RgSpace.s10),
            child: Text('혜택·한도 소식', style: RgText.bodySmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
          Opacity(
            opacity: 0.25 + 0.75 * t,
            child: Transform.translate(
              offset: Offset(0, -14 * (1 - t)),
              child: _MiniCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(spacing: RgSpace.s6, children: [
                    const RgChip('X'),
                    Text('모델 연구소', style: meta.copyWith(fontWeight: FontWeight.w600, color: RgColors.textPrimary)),
                    Flexible(child: Text('@model_lab · 12분 전', maxLines: 1, overflow: TextOverflow.ellipsis, style: meta)),
                  ]),
                  const SizedBox(height: RgSpace.s10),
                  Text(
                    '오늘부터 일주일 동안 무료 사용자도 새 모델을 써요. 사용량 한도도 모두 초기화했어요.',
                    style: RgText.bodySmall.copyWith(fontSize: 15, height: 23 / 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: RgSpace.s6),
                  Text('Free users can try the new model all week. Usage limits are reset.',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                  const SizedBox(height: RgSpace.s2),
                  Text('AI 번역', style: meta.copyWith(fontSize: 11.5, color: RgColors.textTertiary)),
                  const SizedBox(height: RgSpace.s10),
                  Row(spacing: RgSpace.s4, children: [
                    RgIcon('heart', size: 13, color: RgColors.textSecondary),
                    Text('2.4천', style: meta),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// 4장: 3줄 요약 카드 + 형광펜 낱말을 누르면 아래에서 올라오는 뜻 풀이(실제 용어 시트처럼 짙은 바탕).
class _PaperArt extends StatelessWidget {
  const _PaperArt();

  @override
  Widget build(BuildContext context) {
    final t = RgMotion.curve.transform(((_Appear.of(context) - 0.35) / 0.65).clamp(0.0, 1.0));
    Widget point(String n, String text) => Padding(
      padding: const EdgeInsets.only(top: RgSpace.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
        SizedBox(width: 12, child: Text(n, style: RgText.bodySmall.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: RgColors.textTertiary))),
        Expanded(child: Text(text, style: RgText.bodySmall.copyWith(fontSize: 14, color: RgColors.textBody))),
      ]),
    );
    final title = RgText.titleList.copyWith(fontSize: 17, fontWeight: FontWeight.w700);
    return ExcludeSemantics(
      child: SizedBox(
        width: 300,
        height: 318,
        child: Stack(children: [
          _MiniCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(spacing: RgSpace.s6, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: RgColors.newDot, shape: BoxShape.circle)),
                Text('오늘의 논문 1 · 언어 모델', style: RgText.eyebrow.copyWith(color: RgColors.textSecondary)),
              ]),
              const SizedBox(height: RgSpace.s6),
              Text.rich(TextSpan(style: title, children: [
                const TextSpan(text: '긴 문서를 빠르게 읽는 새 '),
                TextSpan(text: '어텐션', style: TextStyle(backgroundColor: RgColors.highlight)),
                const TextSpan(text: ' 방식'),
              ])),
              point('1', '문서가 길어져도 계산량이 거의 늘지 않아요.'),
              point('2', '같은 성능에서 속도가 3배 빨라졌어요.'),
              point('3', '코드와 모델을 공개했어요.'),
            ]),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 0,
            child: Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, 24 * (1 - t)),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(color: RgColors.actionPrimary, borderRadius: BorderRadius.circular(18), boxShadow: RgShadow.card),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '어텐션', style: RgText.bodySmall.copyWith(fontSize: 15, fontWeight: FontWeight.w700, color: RgColors.onAction)),
                      TextSpan(text: '  attention', style: RgText.serifTogether.copyWith(fontSize: 12.5, color: RgColors.onInkMuted)),
                    ])),
                    const SizedBox(height: RgSpace.s4),
                    Text(
                      '문장에서 지금 중요한 단어에 더 집중하도록 가중치를 주는 방법.',
                      style: RgText.caption.copyWith(fontSize: 13.5, height: 20 / 13.5, color: RgColors.onInkMuted),
                    ),
                    const SizedBox(height: RgSpace.s6),
                    Text('예) 「그 영화」의 「그」가 무엇을 가리키는지 찾을 때', style: RgText.caption.copyWith(fontSize: 12.5, color: RgColors.onInkMuted)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ExploreArt extends StatelessWidget {
  const _ExploreArt();

  @override
  Widget build(BuildContext context) {
    // 실제 탐색과 같은 차례: 칸(논문 | 소식 | 도구) → 소식 안의 발표 | 업데이트 | 커뮤니티 → 출처 안내 한 줄 → 출처 칩이 붙은 글.
    // 장이 들어오는 동안 글 세 줄이 차례로 떠오른다(_Appear, 「동작 줄이기」면 넘김 자체가 바로라 한꺼번에 보인다).
    final appear = _Appear.of(context);
    Widget tabs(List<String> labels, int on, double size) => Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: RgColors.dividerCard))),
      child: Row(spacing: RgSpace.s16, children: [
        for (var i = 0; i < labels.length; i++)
          Container(
            padding: const EdgeInsets.only(bottom: RgSpace.s6),
            decoration: BoxDecoration(
              border: i == on ? Border(bottom: BorderSide(color: RgColors.textPrimary, width: 2)) : null,
            ),
            child: Text(labels[i], style: RgText.bodySmall.copyWith(
              fontSize: size,
              fontWeight: i == on ? FontWeight.w700 : FontWeight.w500,
              color: i == on ? RgColors.textPrimary : RgColors.textTertiary,
            )),
          ),
      ]),
    );
    Widget row(int i, String chip, String? source, String title, String meta, {bool last = false}) {
      final t = ((appear - 0.25 - i * 0.18) / 0.4).clamp(0.0, 1.0);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: RgSpace.s10),
            decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: RgColors.dividerCard))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s4, children: [
              Row(spacing: RgSpace.s6, children: [
                RgChip(chip, source: source),
                Text(meta, style: RgText.caption.copyWith(fontSize: 12, color: RgColors.textSecondary)),
              ]),
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
    }

    return ExcludeSemantics(
      child: _MiniCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tabs(const ['논문', '소식', '도구'], 1, 15),
          const SizedBox(height: RgSpace.s10),
          tabs(const ['발표', '업데이트', '커뮤니티'], 0, 13),
          const SizedBox(height: RgSpace.s8),
          Text('각 회사 공식 블로그에서 가져온 발표예요', style: RgText.caption.copyWith(fontSize: 12, color: RgColors.textSecondary)),
          const SizedBox(height: RgSpace.s4),
          row(0, 'OpenAI', 'openai', 'GPT 새 모델 공개', '3시간 전'),
          row(1, 'Anthropic', 'anthropic', '에이전트 개발 도구 업데이트', '어제'),
          row(2, 'Google DeepMind', 'deepmind', '긴 영상을 이해하는 새 모델', '어제', last: true),
        ]),
      ),
    );
  }
}

// 그림이 지금 장이 얼마나 들어왔는지(0~1) 알 수 있게 내려 준다
class _Appear extends InheritedWidget {
  const _Appear({required this.value, required super.child});
  final double value;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Appear>()?.value ?? 1;

  @override
  bool updateShouldNotify(_Appear old) => old.value != value;
}

// 수집 일정: 시각 세 줄(넘기는 동안 차례로 떠오른다) + 주말 줄
class _ScheduleArt extends StatelessWidget {
  const _ScheduleArt();

  @override
  Widget build(BuildContext context) {
    final appear = _Appear.of(context);
    final weekend = ((appear - 0.5) / 0.5).clamp(0.0, 1.0);
    return ExcludeSemantics(
      child: _MiniCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('모으는 시각', style: RgText.eyebrow.copyWith(color: RgColors.textSecondary)),
          const SizedBox(height: RgSpace.s12),
          CollectTimes(appear: appear),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RgSpace.s12),
            child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
          ),
          Opacity(
            opacity: weekend,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s12, children: [
              SizedBox(width: 78, child: Text('토 · 일요일', style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w700, color: RgColors.textSecondary))),
              Expanded(child: Text('새 논문이 거의 없어요', style: RgText.bodySmall.copyWith(color: RgColors.textSecondary))),
            ]),
          ),
        ]),
      ),
    );
  }
}
