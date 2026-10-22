import 'package:flutter/foundation.dart';

enum ReaderMode { together, translation, original }

// 저장 키 settings.readerMode·readerScale (9.4). 저장은 storage.dart.
final readerDefaultMode = ValueNotifier(ReaderMode.together);
final readerScale = ValueNotifier(1.0);

// 7.4 글자 크기 4단계. 리더 본문에만 곱한다.
const readerScales = [(0.9, '작게'), (1.0, '기본'), (1.15, '크게'), (1.3, '아주 크게')];
String readerScaleLabel(double s) => readerScales.firstWhere((e) => e.$1 == s, orElse: () => readerScales[1]).$2;

// G13: 미정. 정해지면 채운다. null이면 행을 눌러도 아무것도 하지 않는다.
const String? privacyPolicyUrl = null;
const String? contactEmail = null;

// ponytail: pubspec version과 손으로 맞춘다. 출시 빌드 전에 package_info_plus로 바꿀지 결정.
const appVersion = '1.0.0';
