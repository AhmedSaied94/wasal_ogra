// The piece sheet's model (specs/015-m10-apartment-story, data-model
// "Apartment", T052): the style it shows, سلمى's line, the family's marks,
// the price and the balance.
import 'package:content_models/content_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/features/apartment/domain/piece_sheet_model.dart';

import '../../../helpers/progress.dart';

const _nish = (SkuKind.item, 'salon.nish');

PieceSheetModel? _sheet({
  String itemId = 'salon.nish',
  Set<(SkuKind, String)> owned = const {},
  Map<String, String> styles = const {},
  Map<String, String> memory = const {},
  int jenehat = 0,
  Set<String> claimed = const {},
}) => pieceSheetModel(
  artboardSalonContent(),
  player(hayDone, {microOld, shabka, ...owned}),
  itemId,
  jenehat: jenehat,
  variantOf: (id) => styles[id],
  requestsClaimed: claimed,
  styleMemory: memory,
);

void main() {
  test('the remembered style, else the first', () {
    expect(_sheet()!.selected, 'classic');
    expect(_sheet(styles: {'salon.nish': 'crystal'})!.selected, 'crystal');
    expect(_sheet(memory: {'salon.nish': 'modern'})!.selected, 'modern');
    // A style the pack dropped falls back to the first.
    expect(_sheet(memory: {'salon.nish': 'gone'})!.selected, 'classic');
  });

  test('سلمى\'s line: the style\'s, else the piece\'s, else none', () {
    expect(
      _sheet(styles: {'salon.nish': 'crystal'})!.salmaLine,
      contains('الكريستال'),
    );
    expect(_sheet()!.salmaLine, contains('الكلاسيك'));
    // A style's comment wins over the piece's (the sample's ستاير style has
    // its own line).
    expect(_sheet(itemId: 'salon.sitara')!.salmaLine, contains('السادة'));
    // A piece with no comments at all: none.
    final bare = _sheet(
      itemId: 'salon.antreeh',
      styles: {'salon.antreeh': 'shaabi'},
    );
    expect(bare!.salmaLine, contains('الشعبي'));
  });

  test('request marks are the open requests of this piece', () {
    final marks = _sheet()!.requestMarks;
    expect(marks, {'crystal': 'bride_mother'});
    // A claimed request leaves the marks.
    expect(_sheet(claimed: {'req_nish_crystal'})!.requestMarks, isEmpty);
    // Another piece has its own.
    expect(_sheet(itemId: 'salon.sitara')!.requestMarks, {
      'red': 'bride_mother',
    });
  });

  test('another style would miss the request', () {
    expect(_sheet()!.askerToMiss, 'bride_mother');
    expect(_sheet(styles: {'salon.nish': 'crystal'})!.askerToMiss, isNull);
    expect(_sheet(claimed: {'req_nish_crystal'})!.askerToMiss, isNull);
  });

  test('the price and the balance', () {
    final sheet = _sheet(jenehat: 2000)!;
    expect((sheet.price, sheet.jenehat), (400, 2000));
    expect(sheet.affordable, isTrue);
    expect(sheet.shortfall, 0);
    final short = _sheet(jenehat: 150)!;
    expect((short.affordable, short.shortfall), (false, 250));
  });

  test('a locked chapter, an owned piece or an unknown id: no sheet', () {
    final content = artboardSalonContent();
    expect(
      pieceSheetModel(
        content,
        player(),
        'salon.nish',
        jenehat: 0,
        variantOf: (_) => null,
        requestsClaimed: const {},
      ),
      isNull,
    );
    expect(_sheet(owned: {_nish})!.owned, isTrue);
    expect(_sheet(itemId: 'salon.nope'), isNull);
  });
}
