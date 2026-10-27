import 'package:flutter/foundation.dart';

enum ReaderMode { together, translation, original }

String readerModeLabel(ReaderMode m) => switch (m) {
  ReaderMode.together => '함께',
  ReaderMode.translation => '번역',
  ReaderMode.original => '원문',
};

// 저장 키 settings.readerMode·readerScale (9.4). 저장은 storage.dart.
final readerDefaultMode = ValueNotifier(ReaderMode.together);
final readerScale = ValueNotifier(1.0);

// 7.4 글자 크기 4단계. 리더 본문에만 곱한다.
const readerScales = [(0.9, '작게'), (1.0, '기본'), (1.15, '크게'), (1.3, '아주 크게')];
String readerScaleLabel(double s) => readerScales.firstWhere((e) => e.$1 == s, orElse: () => readerScales[1]).$2;

// G13. 처리방침 원본은 docs/privacy.md 하나이고, 앱은 그 파일을 화면으로, 웹은 GitHub Pages로 보여 준다.
const privacyPolicyUrl = 'https://bapsange.github.io/ROOTGIST/privacy/';
// 문의 전용 메일. 바꾸면 docs/privacy.md 7장도 같이 고친다.
const contactEmail = 'help.rootgist@gmail.com';

// ponytail: pubspec version과 손으로 맞춘다. 출시 빌드 전에 package_info_plus로 바꿀지 결정.
const appVersion = '1.0.0';
