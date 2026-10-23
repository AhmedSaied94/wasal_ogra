import 'dart:convert';
import 'dart:io';

// Reads the design's measured boxes, `docs/design/boxes/<artboard>.json`
// (specs/008.5-m21-design-refresh/contracts/design-checks.md). Layout tests
// match the app's tappables against the boxes whose role is `tap`.

/// One measured box, in logical pixels from the artboard's top-left.
final class DesignBox {
  const DesignBox({
    required this.id,
    required this.tag,
    required this.role,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.label,
    this.text,
    this.parent,
    this.bg,
    this.color,
    this.font,
    this.lineHeight,
    this.radius,
    this.shadow,
    this.border,
  });

  final int id;
  final String tag;

  /// `tap`, `box`, `text`, `icon`, …
  final String role;
  final double x;
  final double y;
  final double w;
  final double h;

  /// The element's `aria-label`, when it has one.
  final String? label;

  /// The element's own text, when it has any.
  final String? text;

  /// The id of the box it sits in; null for the artboard itself.
  final int? parent;

  // The element's computed style, as the measuring script wrote it: a
  // colour is `#RRGGBB[@alpha] <token name>`, a font `<family> <weight>
  // <size>px`. Only the samples' board renderer reads these.
  final String? bg;
  final String? color;
  final String? font;
  final String? lineHeight;
  final String? radius;
  final String? shadow;
  final String? border;

  @override
  String toString() =>
      'box $id <$tag> "${label ?? text ?? ''}" '
      '(${x.toStringAsFixed(1)}, ${y.toStringAsFixed(1)}, '
      '${w.toStringAsFixed(1)}×${h.toStringAsFixed(1)})';
}

/// One artboard's boxes.
final class DesignBoard {
  const DesignBoard({
    required this.artboard,
    required this.w,
    required this.h,
    required this.boxes,
  });

  final String artboard;
  final double w;
  final double h;
  final List<DesignBox> boxes;

  /// The boxes a player can tap.
  Iterable<DesignBox> get taps => boxes.where((b) => b.role == 'tap');

  /// The box with [id]; throws when there is none.
  DesignBox byId(int id) => boxes.singleWhere(
    (b) => b.id == id,
    orElse: () => throw StateError('$artboard has no box $id'),
  );
}

/// Reads `docs/design/boxes/<artboard>.json`, relative to `apps/mobile`
/// (where `flutter test` runs).
DesignBoard loadBoard(String artboard) => parseBoard(
  File('../../docs/design/boxes/$artboard.json').readAsStringSync(),
  artboard: artboard,
);

/// Parses a boxes file. A malformed file throws a [FormatException] naming
/// [artboard] (or the file's own artboard name).
DesignBoard parseBoard(String json, {String? artboard}) {
  final name = artboard ?? '(unnamed board)';
  try {
    final root = jsonDecode(json) as Map<String, Object?>;
    final board = (root['artboard'] as String?) ?? name;
    return DesignBoard(
      artboard: board,
      w: (root['w']! as num).toDouble(),
      h: (root['h']! as num).toDouble(),
      boxes: [
        for (final raw in (root['boxes']! as List<Object?>))
          _box(raw! as Map<String, Object?>),
      ],
    );
  } on FormatException catch (e) {
    throw FormatException('$name: malformed boxes file (${e.message})');
  } on TypeError catch (e) {
    throw FormatException('$name: malformed boxes file ($e)');
  }
}

DesignBox _box(Map<String, Object?> m) => DesignBox(
  id: m['id']! as int,
  tag: m['tag']! as String,
  role: m['role']! as String,
  x: (m['x']! as num).toDouble(),
  y: (m['y']! as num).toDouble(),
  w: (m['w']! as num).toDouble(),
  h: (m['h']! as num).toDouble(),
  label: m['label'] as String?,
  text: m['text'] as String?,
  parent: m['parent'] as int?,
  bg: m['bg'] as String?,
  color: m['color'] as String?,
  font: m['font'] as String?,
  lineHeight: m['lineHeight'] as String?,
  radius: m['radius'] as String?,
  shadow: m['shadow'] as String?,
  border: m['border'] as String?,
);
