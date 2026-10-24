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
  static final meta = _s(13, 18, FontWeight.w400, 0);
  static final caption = _s(12, 16, FontWeight.w400, 0);
  static final tabLabel = _s(11, 14, FontWeight.w500, 0);
  static final serifTogether = _s(15, 25, FontWeight.w400, 0, isSerif: true);
  static final serifOnly = _s(18, 30, FontWeight.w400, 0, isSerif: true);
  static final serifTerm = _s(26, 32, FontWeight.w600, 0, isSerif: true);
  static final serifSubtitle = _s(15, 22, FontWeight.w400, 0, isSerif: true);
  static final wordmark = _s(17, 17 * 1.2, FontWeight.w700, 1.2);
}

// HANDOFF 9.3: Flutter에 keep-all이 없어 어절 안 글자 사이에 word joiner(U+2060)를 넣는다.
String keepAll(String s) => s.split(' ').map((w) => w.runes.map(String.fromCharCode).join('⁠')).join(' ');

// keepAll로 그리되 화면 읽기(TalkBack·VoiceOver)에는 숨은 문자 없는 원래 문장을 넘긴다.
class KeepAllText extends StatelessWidget {
  const KeepAllText(this.text, {super.key, this.style, this.maxLines, this.overflow});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) =>
      Text(keepAll(text), style: style, maxLines: maxLines, overflow: overflow, semanticsLabel: text);
}
