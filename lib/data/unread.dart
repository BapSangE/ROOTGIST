import 'package:flutter/foundation.dart';

// 새 글 배찌(실기기 QA 요청). 이 기기에서 열어 본 글을 기억해, 기준 시각 뒤에 올라왔고 7일이 안 됐고
// 아직 안 연 글만 「새 글」로 보인다. 시간만으로 정하면(최근 24시간) 매일 보는 사람에게도 본 글에 점이 남는다.
// 기준 시각은 첫 실행 3일 전(storage.dart): 설치하자마자 모든 글이 새 글로 뜨지 않되, 최근 며칠 것은 알려 준다.
// ponytail: 읽은 목록은 지우지 않고 쌓인다(글 하나에 키 하나, 하루 몇 개). 수천 개를 넘기면 7일 지난 키를 덜어낸다.
final readItems = ValueNotifier<Set<String>>({});
var newSince = DateTime.utc(2000);
DateTime Function() clock = DateTime.now; // 테스트에서 fixture 날짜에 맞춘다
const newFor = Duration(days: 7);

bool isNew(String key, DateTime published) =>
    !readItems.value.contains(key) && published.isAfter(newSince) && clock().difference(published) < newFor;

void markRead(String key) {
  if (!readItems.value.contains(key)) readItems.value = {...readItems.value, key};
}

// 모델 목록의 「새로 진입」: 이 기기에서 그 모델을 목록에서 처음 본 시각(UTC ISO). 처음 목록을 받았을 때 이미 있던
// 모델은 'base'(새로 진입이 아니다): 설치하자마자 모두 새로 진입으로 뜨지 않게. 열어 보면(markRead 'model:id') 뗀다.
final modelsSeen = ValueNotifier<Map<String, String>>({});

void noteModels(Iterable<String> ids) {
  final first = modelsSeen.value.isEmpty, now = clock().toUtc().toIso8601String();
  final add = {for (final id in ids) if (!modelsSeen.value.containsKey(id)) id: first ? 'base' : now};
  if (add.isNotEmpty) modelsSeen.value = {...modelsSeen.value, ...add};
}

bool enteredModel(String id) {
  final seen = DateTime.tryParse(modelsSeen.value[id] ?? '');
  return seen != null && !readItems.value.contains('model:$id') && clock().difference(seen) < newFor;
}

// 공식 소식(발표) 목록의 「지난번에 여기까지 봤어요」: 지난번 목록을 열었을 때 맨 위 글의 게시 시각(UTC ISO).
// 목록을 열면 이번 맨 위 글 시각으로 바꾼다. 처음이면 선을 그리지 않는다.
final newsSeenAt = ValueNotifier<DateTime?>(null);
