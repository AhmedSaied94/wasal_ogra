// A panel as a thumbnail draws it (specs/015-m10-apartment-story,
// contracts/scene-viewer.md "The timeline", "The album"): the art slug and
// the speakers the fallback draws when the art has no drawing. Pure.
import 'package:content_models/content_models.dart';

final class PanelRef {
  const PanelRef({required this.art, required this.speakers});

  /// [panel]'s art and the speakers of its lines, in order.
  factory PanelRef.of(Panel panel) => PanelRef(
    art: panel.art,
    speakers: [for (final line in panel.lines) line.speaker],
  );

  final String art;
  final List<String> speakers;

  @override
  bool operator ==(Object other) =>
      other is PanelRef &&
      other.art == art &&
      other.speakers.length == speakers.length &&
      [
        for (var i = 0; i < speakers.length; i++)
          speakers[i] == other.speakers[i],
      ].every((same) => same);

  @override
  int get hashCode => Object.hash(art, Object.hashAll(speakers));

  @override
  String toString() => 'PanelRef($art, $speakers)';
}
