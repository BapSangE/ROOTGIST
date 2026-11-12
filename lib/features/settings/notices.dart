import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import '../../data/repository.dart';
import '../../data/unread.dart';
import '../../data/unread.dart' as unread show isNew;
import '../../design/widgets/rg_new_dot.dart';
import 'settings_screen.dart';
import '../reader/text_size_sheet.dart';

// 공지사항(실기기 QA 요청): docs/notices.md의 「## 제목」마다 공지 하나, 바로 아래 줄이 날짜.
// 목록은 제목·날짜만, 누르면 시트로 내용을 연다.
// 서버 공지(2026-11-12, supabase notices 테이블): 앱 업데이트 없이 올린다. 앱에 묶인 공지 위에 최신순으로 붙고,
// popup인 새 공지는 앱을 열 때 팝업으로 뜬다(showNoticePopupIfAny).
class Notice {
  Notice(this.title, this.date, this.body, {this.id, this.at, this.popup = false});
  final String title;
  final String date; // 2026.10.27
  final List<(MdBlock, String)> body;
  final String? id; // 서버 공지 id. 앱에 묶인 공지는 null
  final DateTime? at; // 서버 공지의 게시 시각
  final bool popup;

  factory Notice.server(Map<String, dynamic> j) {
    final at = DateTime.parse(j['published_at'] as String);
    final kst = at.toUtc().add(const Duration(hours: 9));
    String two(int v) => v.toString().padLeft(2, '0');
    return Notice(
      j['title'] as String,
      '${kst.year}.${two(kst.month)}.${two(kst.day)}',
      markdownBlocks(j['body'] as String? ?? ''),
      id: '${j['id']}',
      at: at,
      popup: j['popup'] == true,
    );
  }

  // 읽음 기록(unread.dart). 서버 공지는 id로: 제목을 고쳐도 읽음이 풀리지 않게
  String get key => id != null ? 'notice:srv:$id' : 'notice:$date $title';
  // 서버 공지는 게시 시각, 앱에 묶인 공지는 KST 그날 0시. 날짜가 없으면 아주 옛날(새 글로 치지 않는다)
  DateTime get publishedAt {
    if (at case final at?) return at;
    final p = date.split('.').map(int.tryParse).toList();
    if (p.length != 3 || p.contains(null)) return DateTime.utc(2000);
    return DateTime.utc(p[0]!, p[1]!, p[2]!).subtract(const Duration(hours: 9));
  }

  bool get isNew => unread.isNew(key, publishedAt);
}

// 설정 행·공지 화면·팝업이 같은 목록을 쓴다. 앱을 켜 있는 동안 한 번만 읽는다.
// 서버 공지를 못 받으면(오프라인·마이그레이션 전) 앱에 묶인 공지만. 받은 적 있으면 저장본(supabase_repository)이 쓰인다.
Future<List<Notice>>? _notices;
Future<List<Notice>> loadNotices() => _notices ??= Future.wait([
      repository
          .listNotices()
          .timeout(const Duration(seconds: 25))
          .then((l) => [for (final j in l) Notice.server(j)])
          .catchError((Object _) => <Notice>[]),
      rootBundle.loadString('docs/notices.md').then(parseNotices),
    ]).then((r) => [...r[0], ...r[1]]);

@visibleForTesting
void resetNotices() => _notices = null;
@visibleForTesting
void setNoticesForTest(List<Notice> notices) => _notices = Future.value(notices);

bool hasNewNotice(List<Notice>? notices) => notices?.any((n) => n.isNew) ?? false;

List<Notice> parseNotices(String md) {
  final out = <Notice>[];
  for (final (kind, text) in markdownBlocks(md)) {
    if (kind == MdBlock.heading) {
      out.add(Notice(text, '', []));
    } else if (out.isNotEmpty) {
      final n = out.last;
      if (n.date.isEmpty && n.body.isEmpty && RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(text)) {
        out[out.length - 1] = Notice(n.title, text, n.body);
      } else {
        n.body.add((kind, text));
      }
    }
  }
  return out;
}

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  late final _doc = loadNotices();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _doc,
      builder: (context, snap) {
        final notices = snap.data ?? const <Notice>[];
        return ValueListenableBuilder(
          valueListenable: readItems,
          builder: (context, _, _) => ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
            children: [
              SizedBox(
                height: RgSpace.topBar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                  child: Row(
                    children: [RgBackButton(onTap: () => context.pop())],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, RgSpace.s20),
                child: HeadingTextScale(
                  child: Semantics(header: true, child: Text('공지사항', style: RgText.titleDetail)),
                ),
              ),
              if (notices.isNotEmpty)
                RgCard(
                  child: Column(
                    children: [
                      for (final (i, n) in notices.indexed)
                        RgListRow(
                          showDivider: i < notices.length - 1,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          onTap: () => _open(context, n),
                          trailing: Padding(
                            padding: EdgeInsets.only(right: RgSpace.s12),
                            child: RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              KeepAllText(n.title, style: RgText.titleList),
                              const SizedBox(height: RgSpace.s4),
                              Row(
                                spacing: RgSpace.s6,
                                children: [
                                  Text(n.date, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                                  if (n.isNew) ...[
                                    const RgNewDot(),
                                    ExcludeSemantics(
                                      child: Text(
                                        '새 글',
                                        style: RgText.meta.copyWith(color: RgColors.newDot, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _open(BuildContext context, Notice n) {
    markRead(n.key);
    showRgBottomSheet<void>(context, builder: (sheet) => _NoticeBody(n));
  }
}

// 공지 시트 본문(공지사항 목록에서 열 때·앱 시작 팝업 같은 모양)
class _NoticeBody extends StatelessWidget {
  const _NoticeBody(this.n, {this.top = RgSpace.s4});
  final Notice n;
  final double top; // 시트는 손잡이(누르는 높이 24) 아래라 4, 가운데 팝업은 카드 위 여백이 따로 있어 0

  @override
  Widget build(BuildContext context) {
    // 공지 본문도 앱의 「글자 크기」를 따른다
    return ReaderTextScale(child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: top),
        Text(n.date, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
        const SizedBox(height: RgSpace.s6),
        Semantics(header: true, child: KeepAllText(n.title, style: RgText.titleSection)),
        const SizedBox(height: RgSpace.s16),
        ...markdownWidgets(n.body),
      ],
    ));
  }
}

// 앱 시작 팝업(2026-11-12): 앱을 열면 안 본 새 서버 공지 하나(가장 최근)를 화면 가운데 카드로 띄운다.
// · 가운데 카드(2026-11-12, 처음엔 바텀 시트): 앱의 시트는 모두 사용자가 눌러 여는 것이라, 앱이 먼저 띄우는 공지는 모양을 달리 한다.
//   설정 › 공지사항에서 여는 공지는 그대로 시트.
// · 대상: popup인 서버 공지 중 이 기기의 기준 시각(첫 실행 3일 전, unread.newSince) 뒤에 게시됐고
//   「다시 보지 않기」를 누르지 않은 것. 「확인」·바깥 탭·뒤로가기로 닫으면 다음에 앱을 열 때 또 뜬다.
// · 첫 실행(온보딩을 막 끝낸 직후)에는 띄우지 않는다: 안내가 연달아 두 장 뜨지 않게(noticePopupAllowed).
// · 앱을 켜 있는 동안 한 번만 확인한다.
bool _popupChecked = false;

@visibleForTesting
void resetNoticePopup() => _popupChecked = false;

Notice? popupNotice(List<Notice> notices) {
  for (final n in notices) {
    if (n.id != null && n.popup && n.publishedAt.isAfter(newSince) && !noticePopupDismissed.value.contains(n.key)) return n;
  }
  return null;
}

Future<void> showNoticePopupIfAny(BuildContext context) async {
  if (_popupChecked || !noticePopupAllowed) return;
  _popupChecked = true;
  final n = popupNotice(await loadNotices());
  if (n == null || !context.mounted) return;
  markRead(n.key); // 내용을 봤으니 설정 › 공지사항의 새 글 점은 뗀다
  HapticFeedback.selectionClick(); // 시트가 열릴 때와 같은 가벼운 진동
  await Navigator.of(context, rootNavigator: true).push(_NoticePopupRoute(n));
}

// 나타날 때 96%→100% 커지며 페이드(220ms), 닫힐 때는 더 빨리(160ms). 「동작 줄이기」면 바로 뜨고 바로 닫힌다.
class _NoticePopupRoute extends PopupRoute<void> {
  _NoticePopupRoute(this.n);
  final Notice n;

  bool get _still => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  @override
  Color get barrierColor => RgColors.overlayDim;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '닫기';
  @override
  Duration get transitionDuration => _still ? Duration.zero : RgMotion.base;
  @override
  Duration get reverseTransitionDuration => _still ? Duration.zero : RgMotion.release;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      _NoticePopup(n);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final a = CurvedAnimation(parent: animation, curve: RgMotion.curve, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: a,
      child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(a), child: child),
    );
  }
}

class _NoticePopup extends StatelessWidget {
  const _NoticePopup(this.n);
  final Notice n;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RgSpace.s24),
          child: ConstrainedBox(
            // 긴 공지는 본문만 스크롤된다. 버튼 줄은 늘 보인다
            constraints: BoxConstraints(maxWidth: 400, maxHeight: size.height * 0.7),
            child: Semantics(
              scopesRoute: true,
              namesRoute: true,
              explicitChildNodes: true,
              label: '공지',
              child: Material(
                color: RgColors.surfaceRaised,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(RgRadius.card))),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                        child: _NoticeBody(n, top: 0),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: Row(
                        spacing: RgSpace.s8,
                        children: [
                          Expanded(
                            child: RgNeutralButton(
                              label: '다시 보지 않기',
                              onTap: () {
                                noticePopupDismissed.value = {...noticePopupDismissed.value, n.key};
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                          Expanded(child: RgPrimaryButton(label: '확인', onTap: () => Navigator.of(context).pop())),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
