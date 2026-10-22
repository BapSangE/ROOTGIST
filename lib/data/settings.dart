import 'package:flutter/foundation.dart';

enum ReaderMode { together, translation, original }

// ponytail: 메모리 설정. M3에서 shared_preferences(settings.readerMode·readerScale, 9.4)로 저장한다.
final readerDefaultMode = ValueNotifier(ReaderMode.together);

// G13: 미정. 정해지면 채운다. null이면 행을 눌러도 아무것도 하지 않는다.
const String? privacyPolicyUrl = null;
const String? contactEmail = null;

// ponytail: pubspec version과 손으로 맞춘다. 출시 빌드 전에 package_info_plus로 바꿀지 결정.
const appVersion = '1.0.0';
