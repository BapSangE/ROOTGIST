import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../../design/widgets/rg_bottom_sheet.dart';
import '../../design/widgets/rg_buttons.dart';
import '../../design/widgets/rg_card.dart';
import '../../design/widgets/rg_pressable.dart';
import 'settings_screen.dart';

// 공지사항(실기기 QA 요청): docs/notices.md의 「## 제목」마다 공지 하나, 바로 아래 줄이 날짜.
// 목록은 제목·날짜만, 누르면 시트로 내용을 연다.
// ponytail: 앱에 묶인 고정 공지. 자주 바뀌면 PROPOSALS P6대로 서버 테이블로 옮긴다.
class Notice {
  Notice(this.title, this.date, this.body);
  final String title;
  final String date; // 2026.10.27
  final List<(MdBlock, String)> body;
}

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
  late final _doc = rootBundle.loadString('docs/notices.md').then(parseNotices);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _doc,
      builder: (context, snap) {
        final notices = snap.data ?? const <Notice>[];
        return ListView(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: RgSpace.bottomScrollInset),
          children: [
            SizedBox(
              height: RgSpace.topBar,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: RgSpace.gutterCard),
                child: Row(children: [
                  RgCircleButton(semanticLabel: '뒤로', icon: 'chevron-left', onTap: () => context.pop()),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(RgSpace.gutterText, RgSpace.s12, RgSpace.gutterText, RgSpace.s20),
              child: HeadingTextScale(child: Semantics(header: true, child: Text('공지사항', style: RgText.titleDetail))),
            ),
            if (notices.isNotEmpty)
              RgCard(
                child: Column(children: [
                  for (final (i, n) in notices.indexed)
                    RgListRow(
                      showDivider: i < notices.length - 1,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      onTap: () => _open(context, n),
                      trailing: const Padding(
                        padding: EdgeInsets.only(right: RgSpace.s12),
                        child: RgIcon('chevron-right', size: 18, color: RgColors.textTertiary),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        KeepAllText(n.title, style: RgText.titleList),
                        const SizedBox(height: RgSpace.s4),
                        Text(n.date, style: RgText.meta.copyWith(color: RgColors.textSecondary)),
                      ]),
                    ),
                ]),
              ),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, Notice n) => showRgBottomSheet<void>(
    context,
    builder: (sheet) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 22),
      Text(n.date, style: RgText.caption.copyWith(color: RgColors.textSecondary)),
      const SizedBox(height: RgSpace.s6),
      Semantics(header: true, child: KeepAllText(n.title, style: RgText.titleSection)),
      const SizedBox(height: RgSpace.s16),
      ...markdownWidgets(n.body),
      const SizedBox(height: RgSpace.s12),
      RgNeutralButton(label: '닫기', onTap: () => Navigator.of(sheet).pop()),
    ]),
  );
}
