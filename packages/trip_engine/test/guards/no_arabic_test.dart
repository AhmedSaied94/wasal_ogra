// No Arabic text in code (CLAUDE.md): the engine emits speech keys, and the
// lines live in the packs' speech pools. Comments may quote the ux-spec.
import 'package:test/test.dart';

import 'source_scan.dart';

final _arabic = RegExp(r'[؀-ۿݐ-ݿ]');

void main() {
  test('the guard catches Arabic in code and strings, not in comments', () {
    expect(_arabic.hasMatch(stripped("final s = 'أجرة';")), isTrue);
    expect(_arabic.hasMatch(stripped('// وصّل\nfinal x = 1;')), isFalse);
  });

  for (final file in libSources()) {
    test('${file.path} has no Arabic outside comments', () {
      expect(_arabic.hasMatch(stripped(file.readAsStringSync())), isFalse);
    });
  }
}
