import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../data/guide.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_pressable.dart';

// 첫 실행 온보딩 4장(시안 design-preview/src/onboarding_guide.html). 회원가입·권한 요청이 없어 마지막 장에서 바로 시작한다.
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
  _Slide('매일 아침,\n화제의 AI 소식을\n한국어로', '공식 발표와 개발자 화제, 주목받은 논문과 모델을 한곳에서 쉽게 봐요.', _LogoArt()),
  _Slide('연구소 발표부터\n개발자 화제까지', 'OpenAI·Anthropic·Google 같은 곳의 소식을 요약과 함께 모아 드려요.', _ExploreArt()),
  _Slide('주목받은 논문도\n3줄로', '많이 본 AI 논문을 매일 아침 골라 3줄 요약으로 보여 드려요.', _HomeArt()),
  _Slide('어려운 용어는\n형광펜으로', '형광펜을 누르면 뜻과 예시가 나와요. 논문은 원문과 번역을 문장마다 나란히 봐요.', _ReaderArt()),
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
            Expanded(child: Center(child: FittedBox(fit: BoxFit.scaleDown, child: slide.art))),
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
                KeepAllText(slide.body, style: RgText.bodySummary.copyWith(fontSize: 16.5, color: RgColors.textBody)),
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

class _LogoArt extends StatelessWidget {
  const _LogoArt();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset('assets/branding/rootgist_symbol.svg', width: 132, height: 132),
  );
}

class _HomeArt extends StatelessWidget {
  const _HomeArt();

  @override
  Widget build(BuildContext context) {
    Widget point(String n, String text) => Padding(
      padding: const EdgeInsets.only(top: RgSpace.s8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s8, children: [
        SizedBox(width: 12, child: Text(n, style: RgText.bodySmall.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: RgColors.textTertiary))),
        Expanded(child: Text(text, style: RgText.bodySmall.copyWith(fontSize: 14, color: RgColors.textBody))),
      ]),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: 300,
        height: 300,
        child: Stack(children: [
          // 뒤에 겹친 카드 두 장: 날마다 쌓인다는 느낌
          for (final (top, scale, opacity) in const [(0.0, 0.9, 0.45), (26.0, 0.95, 0.75)])
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(scale: scale, child: _MiniCard(child: Text('어제의 논문', style: RgText.eyebrow.copyWith(color: RgColors.textSecondary)))),
              ),
            ),
          Positioned(
            top: 60,
            left: 0,
            right: 0,
            child: _MiniCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(spacing: RgSpace.s6, children: [
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: RgColors.newDot, shape: BoxShape.circle)),
                  Text('오늘의 논문 1 · 언어 모델', style: RgText.eyebrow.copyWith(color: RgColors.textSecondary)),
                ]),
                const SizedBox(height: RgSpace.s6),
                Text('긴 문서를 빠르게 읽는 새 어텐션 방식', style: RgText.titleList.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                point('1', '문서가 길어져도 계산량이 거의 늘지 않아요.'),
                point('2', '같은 성능에서 속도가 3배 빨라졌어요.'),
                point('3', '코드와 모델을 공개했어요.'),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ReaderArt extends StatelessWidget {
  const _ReaderArt();

  @override
  Widget build(BuildContext context) {
    final en = RgText.serifTogether.copyWith(fontSize: 13.5, height: 21 / 13.5, color: RgColors.textSecondary);
    final ko = RgText.bodySmall.copyWith(fontSize: 15.5, height: 25 / 15.5, color: RgColors.textPrimary);
    final mark = TextStyle(backgroundColor: RgColors.highlight);
    return ExcludeSemantics(
      child: _MiniCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(style: en, children: [
            const TextSpan(text: 'We propose a sparse '),
            TextSpan(text: 'attention', style: TextStyle(backgroundColor: RgColors.highlightOriginal)),
            const TextSpan(text: ' mechanism for long documents.'),
          ])),
          const SizedBox(height: RgSpace.s4),
          Text.rich(TextSpan(style: ko, children: [
            const TextSpan(text: '긴 문서를 위한 희소 '),
            TextSpan(text: '어텐션', style: mark),
            const TextSpan(text: ' 방식을 제안한다.'),
          ])),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RgSpace.s12),
            child: Divider(height: 1, thickness: 1, color: RgColors.dividerCard),
          ),
          Text('It scales linearly with sequence length.', style: en),
          const SizedBox(height: RgSpace.s4),
          Text('계산량이 입력 길이에 비례해서만 늘어난다.', style: ko),
          const SizedBox(height: RgSpace.s12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: RgColors.actionPrimary, borderRadius: BorderRadius.circular(18)),
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
            ]),
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
    Widget chip(String label, bool on) => Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: RgSpace.s12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? RgColors.actionPrimary : RgColors.fillNeutral,
        borderRadius: BorderRadius.circular(RgRadius.pill),
      ),
      child: Text(label, style: RgText.caption.copyWith(fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? RgColors.onAction : RgColors.textBody)),
    );
    Widget row(String badge, String title, String meta, {bool last = false}) => Container(
      padding: EdgeInsets.symmetric(vertical: RgSpace.s12),
      decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: RgColors.dividerCard))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: RgSpace.s10, children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: RgColors.fillNeutral, borderRadius: BorderRadius.circular(RgRadius.badge)),
          child: Text(badge, style: RgText.caption.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: RgColors.textBody)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: RgText.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            Text(meta, style: RgText.caption.copyWith(fontSize: 12.5, color: RgColors.textSecondary)),
          ]),
        ),
      ]),
    );
    return ExcludeSemantics(
      child: _MiniCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(spacing: RgSpace.s6, children: [chip('공식 소식', true), chip('화제', false), chip('모델', false)]),
          const SizedBox(height: RgSpace.s8),
          row('OA', 'GPT 새 모델 공개', 'OpenAI · 제품 · 3시간 전'),
          row('NV', 'AI 팩토리 관제 도구 공개', 'NVIDIA · 인프라 · 어제'),
          row('HN', '개발자들이 많이 본 AI 글', 'Hacker News · 화제 · 어제', last: true),
        ]),
      ),
    );
  }
}
