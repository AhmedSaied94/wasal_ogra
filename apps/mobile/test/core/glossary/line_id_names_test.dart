import 'package:content_models/content_models.dart' as content;
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/glossary/ids.dart' as glossary;
import 'package:wassal/features/trip/domain/line_ids.dart';

// The glossary's LineId (tunables' per-line keys) and content_models' LineId
// (content and TripParams) name the same lines, so the trip screen converts
// between them by name (specs/008-m02-trip-screen, research R23).
void main() {
  test('both LineId enums have the same value names, in the same order', () {
    expect(
      glossary.LineId.values.map((v) => v.name),
      content.LineId.values.map((v) => v.name),
    );
  });

  test('the conversions round-trip every value', () {
    for (final line in content.LineId.values) {
      expect(toContentLine(toGlossaryLine(line)), line);
      expect(toGlossaryLine(line).name, line.name);
    }
    for (final line in glossary.LineId.values) {
      expect(toGlossaryLine(toContentLine(line)), line);
    }
  });
}
