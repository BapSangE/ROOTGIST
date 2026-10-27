import 'package:flutter/material.dart';

import 'tokens.dart';

// HANDOFF 5.2. Flutter height = 행간 / 크기.
abstract class RgText {
  static const sans = 'Pretendard';
  static const sansFallback = ['Apple SD Gothic Neo', 'Noto Sans KR'];
  static const serif = 'SourceSerif4';

  static TextStyle _s(double size, double lh, FontWeight w, double ls, {bool isSerif = false}) => TextStyle(
    fontFamily: isSerif ? serif : sans,
    fontFamilyFallback: isSerif ? const ['Georgia'] : sansFallback,
    fontSize: size,
    height: lh / size,
    fontWeight: w,
    letterSpacing: ls,
    color: RgColors.textPrimary,
  );

  static final displayHome = _s(30, 39, FontWeight.w700, -0.4);
  static final titleDetail = _s(26, 35, FontWeight.w700, -0.3);
  static final titleReader = _s(22, 31, FontWeight.w700, -0.2);
  static final titleFeatured = _s(21, 29, FontWeight.w700, -0.3);
  static final titleSection = _s(18, 25, FontWeight.w700, -0.2);
  static final titleCard = _s(17, 24, FontWeight.w700, 0);
  static final titleList = _s(16, 23, FontWeight.w600, -0.2);
  static final bodyReaderKo = _s(17, 29, FontWeight.w400, -0.1);
  static final bodyDefinition = _s(16, 26, FontWeight.w400, 0);
  static final bodySummary = _s(15, 23, FontWeight.w400, 0);
  static final bodySmall = _s(14, 21, FontWeight.w400, 0);
  // 메타·캡션은 피드백(보조 글자가 너무 작다)으로 13/18 → 14/20, 12/16 → 13/18
  static final meta = _s(14, 20, FontWeight.w400, 0);
  static final caption = _s(13, 18, FontWeight.w400, 0);
  static final tabLabel = _s(13, 16, FontWeight.w500, 0); // 피드백: 11/14는 너무 작았다
  static final serifTogether = _s(14, 22, FontWeight.w400, 0, isSerif: true); // iOS QA: 15/25 → 14/22(번역이 주, 원문은 대조용)
  static final serifOnly = _s(18, 30, FontWeight.w400, 0, isSerif: true);
  static final serifTerm = _s(26, 32, FontWeight.w600, 0, isSerif: true);
  static final serifSubtitle = _s(15, 22, FontWeight.w400, 0, isSerif: true);
  static final wordmark = _s(17, 17 * 1.2, FontWeight.w700, 1.2);
}

// HANDOFF 9.3: Flutter에 keep-all이 없어 어절 안 글자 사이에 word joiner(U+2060)를 넣는다.
String keepAll(String s) => s.split(' ').map((w) => w.runes.map(String.fromCharCode).join('⁠')).join(' ');

// 문장마다 줄을 바꾼다(피드백: 「정리했어요. 글 전체를 …」처럼 문장이 이어 붙어 한 덩어리로 보였다).
// 한글·닫는 괄호 뒤 마침표 다음 공백에서만 나눠 「3.0배」 같은 수치는 건드리지 않는다.
String byLine(String s) => s.trim().split(RegExp(r'(?<=[가-힣)\]」][.!?])\s+')).join('\n');

// keepAll로 그리되 화면 읽기(TalkBack·VoiceOver)에는 숨은 문자 없는 원래 문장을 넘긴다.
// perSentence: 안내 문구·요약·공지 본문처럼 여러 문장인 글은 문장마다 줄을 바꾼다.
class KeepAllText extends StatelessWidget {
  const KeepAllText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.perSentence = false,
    this.textAlign,
  });
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool perSentence;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    keepAll(perSentence ? byLine(text) : text),
    style: style,
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
    semanticsLabel: text,
  );
}

// 높이가 고정된 화면 틀(상단 바 52, 하단 탭바 64)은 일반 최대 글자 크기(XXXL, 1.35배)에서 배율을 멈춘다.
// 본문은 끝까지 커진다. iOS 기본 내비게이션 바·탭바도 접근성 크기에서 더 커지지 않는다(iOS QA).
class ChromeTextScale extends StatelessWidget {
  const ChromeTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 1.35, child: child);
}

// 21pt 이상 큰 제목은 글자 배율을 2배에서 멈춘다. 접근성 최대(3.12배)에서 홈 헤드라인이 94pt가 돼
// 한 화면을 다 차지했다(iOS QA). 2배여도 본문(최대 약 3배)보다 커서 위계는 남는다.
class HeadingTextScale extends StatelessWidget {
  const HeadingTextScale({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(maxScaleFactor: 2, child: child);
}
