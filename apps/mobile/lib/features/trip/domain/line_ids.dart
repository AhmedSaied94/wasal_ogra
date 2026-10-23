// The glossary's LineId names the tunables' per-line keys; content_models'
// LineId names content and `TripParams`. Both list the same lines by the
// same names (research R23), so the trip converts by name.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/glossary/ids.dart' as glossary;

glossary.LineId toGlossaryLine(LineId line) =>
    glossary.LineId.values.byName(line.name);

LineId toContentLine(glossary.LineId line) => LineId.values.byName(line.name);
