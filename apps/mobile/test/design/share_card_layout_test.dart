import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/features/result/presentation/share_card.dart';

import 'boxes.dart';
import 'samples/share_card.dart';

// `ShareCard` against its measured boxes (specs/013-m08-home-result,
// research R16, R20). The picture has nothing to tap, so its blocks are
// checked where the board puts them: the stars, the quote card and its
// face, the title and the two ends of the bottom row, within 2 pt.

const _tolerance = 2.0;

void _expectAt(Rect rect, DesignBox box) {
  for (final (name, app, design) in [
    ('left', rect.left, box.x),
    ('top', rect.top, box.y),
    ('width', rect.width, box.w),
    ('height', rect.height, box.h),
  ]) {
    expect(app, closeTo(design, _tolerance), reason: '$box $name');
  }
}

void main() {
  testWidgets('ShareCard: the boxes', (tester) async {
    await pumpShareCard(tester);
    final board = loadBoard('ShareCard');
    final card = tester.getTopLeft(find.byType(ShareCard));
    Rect at(Finder finder) => tester.getRect(finder).shift(-card);

    _expectAt(at(find.byKey(ShareCard.starsKey)), board.byId(4));
    _expectAt(at(find.byKey(ShareCard.quoteKey)), board.byId(8));
    _expectAt(at(find.byType(PassengerAvatar)), board.byId(9));
    _expectAt(at(find.text('وصلنا الجامعة!')), board.byId(3));
    _expectAt(at(find.text('وصّل الأجرة')), board.byId(13));
  });
}
