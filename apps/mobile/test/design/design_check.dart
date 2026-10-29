import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wassal/core/l10n/digit_style.dart';

import 'boxes.dart';

// The check harness (specs/008.5-m21-design-refresh/contracts/design-checks.md
// "Matching a box", "Surfaces"): an artboard's surface, its layout test
// against the measured boxes, and its golden beside the design's PNG.

/// The design's status bar on phone artboards.
const designTopInset = 36.0;

/// A test frame of [size] logical points at device pixel ratio 1, with the
/// phone reporting [topInset] of status bar. Reset on tear-down.
void applyDesignSurface(
  WidgetTester tester,
  Size size, {
  required double topInset,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: topInset);
  tester.view.viewPadding = FakeViewPadding(top: topInset);
  addTearDown(tester.view.reset);
}

/// Checks every tap box of [artboard] against the tappable semantics nodes
/// on screen, within [tolerance] points on every side.
///
/// For each tap box: a box in [skip] is skipped (its reason printed); a box
/// in [pairings] is found by the paired label; otherwise by its `label`,
/// else by the node whose label contains its `text`. Exactly one node must
/// match. A box in [tolerances] is checked within its own tolerance, for a
/// control placed after others whose text Flutter measures a little wider
/// than the browser did. A box in [offsets] is expected moved by its offset,
/// for a listed difference where a later board moved it. Then every
/// tappable node that no box matched must have a label in [appOnly]. A
/// sheet's or dialog's [scrim], which the board draws as a box, is left
/// out: the node with that label covering the whole frame. All problems are
/// reported together, each naming the artboard.
void expectLayoutMatches(
  WidgetTester tester,
  String artboard, {
  DesignBoard? board,
  Map<int, String> skip = const {},
  Map<int, String> pairings = const {},
  Set<String> appOnly = const {},
  double tolerance = 2,
  Map<int, double> tolerances = const {},
  Map<int, Offset> offsets = const {},
  String? scrim,
}) {
  final design = board ?? loadBoard(artboard);
  final frame = Rect.fromLTWH(0, 0, design.w, design.h);
  final nodes = [
    for (final n in _tappableNodes(tester))
      if (scrim == null || n.label != _plain(scrim) || n.rect != frame) n,
  ];
  final matched = <int>{};
  final problems = <String>[];

  for (final box in design.taps) {
    final reason = skip[box.id];
    if (reason != null) {
      debugPrint('$artboard: skipping $box: $reason');
      continue;
    }
    final paired = pairings[box.id];
    final List<_Node> found;
    final String wanted;
    if (paired != null) {
      wanted = 'paired label "$paired"';
      found = nodes.where((n) => n.label == _plain(paired)).toList();
    } else if (box.label != null) {
      wanted = 'label "${box.label}"';
      found = nodes.where((n) => n.label == box.label).toList();
    } else if (box.text != null && box.text!.trim().isNotEmpty) {
      final text = box.text!.trim();
      wanted = 'a label containing "$text"';
      found = nodes.where((n) => n.label.contains(text)).toList();
    } else {
      problems.add('$artboard: $box has no label or text; pair it or skip it');
      continue;
    }
    if (found.length != 1) {
      problems.add(
        '$artboard: $box: expected one tappable with $wanted, '
        'found ${found.length}'
        '${found.isEmpty ? '' : ': ${found.map((n) => n.describe()).join('; ')}'}',
      );
      continue;
    }
    final node = found.single;
    matched.add(node.id);
    final want = Rect.fromLTWH(
      box.x,
      box.y,
      box.w,
      box.h,
    ).shift(offsets[box.id] ?? Offset.zero);
    final within = tolerances[box.id] ?? tolerance;
    if (!_within(node.rect, want, within)) {
      problems.add(
        '$artboard: box ${box.id} "${paired ?? box.label ?? box.text}": '
        'design ${_fmt(want)}, app ${_fmt(node.rect)} '
        '(tolerance ±$within pt)',
      );
    }
  }

  for (final node in nodes) {
    if (matched.contains(node.id) || appOnly.map(_plain).contains(node.label)) {
      continue;
    }
    problems.add(
      '$artboard: tappable ${node.describe()} matches no box; '
      'the design has no such control',
    );
  }

  if (problems.isNotEmpty) fail(problems.join('\n'));
}

/// Compares [finder] with `goldens/<artboard>_<digits>.png`. With
/// `--dart-define=DESIGN_COMPARE=true`, it also writes
/// `build/design_compare/<artboard>_<digits>.png`: the design's PNG and the
/// render side by side, at the render's size.
Future<void> expectDesignGolden(
  WidgetTester tester,
  Finder finder,
  String artboard,
  DigitStyle digits,
) async {
  final name = '${artboard}_${digits.name}';
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
  if (const bool.fromEnvironment('DESIGN_COMPARE')) {
    await _writeCompare(tester, finder, artboard, name);
  }
}

/// The gap between the two halves of a compare image.
const _compareGap = 16.0;

Future<void> _writeCompare(
  WidgetTester tester,
  Finder finder,
  String artboard,
  String name,
) async {
  final element = finder.evaluate().single;
  await tester.runAsync(() async {
    final render = await captureImage(element);
    final codec = await ui.instantiateImageCodec(
      File('../../docs/design/png/$artboard.png').readAsBytesSync(),
    );
    final design = (await codec.getNextFrame()).image;
    final w = render.width.toDouble();
    final h = render.height.toDouble();
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
      ..drawRect(
        Rect.fromLTWH(0, 0, w * 2 + _compareGap, h),
        Paint()..color = const Color(0xFFFFFFFF),
      )
      ..drawImageRect(
        design,
        Rect.fromLTWH(0, 0, design.width.toDouble(), design.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..drawImage(render, Offset(w + _compareGap, 0), Paint());
    final image = await recorder.endRecording().toImage(
      (w * 2 + _compareGap).round(),
      h.round(),
    );
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/design_compare/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
    image.dispose();
    design.dispose();
    render.dispose();
  });
}

/// A tappable semantics node with its rect in logical pixels from the
/// surface's top-left.
final class _Node {
  const _Node(this.id, this.label, this.rect);

  final int id;
  final String label;
  final Rect rect;

  String describe() => '"$label" ${_fmt(rect)}';
}

List<_Node> _tappableNodes(WidgetTester tester) {
  final dpr = tester.view.devicePixelRatio;
  final nodes = <_Node>[];
  // A disabled button has no tap action, but the design still draws it as
  // a control, so buttons count whether or not they're enabled.
  bool control(SemanticsNode n) {
    final data = n.getSemanticsData();
    return data.hasAction(SemanticsAction.tap) || data.flagsCollection.isButton;
  }

  for (final node in find.semantics.byPredicate(control).evaluate()) {
    final data = node.getSemanticsData();
    if (data.flagsCollection.isHidden || node.isInvisible) continue;
    nodes.add(_Node(node.id, _plain(data.label), _globalRect(node, dpr)));
  }
  return nodes;
}

/// [label] without the bidi isolates the app puts around numbers
/// (U+2066–U+2069): screen readers don't say them, and the artboards don't
/// have them.
String _plain(String label) => label.replaceAll(RegExp('[\u2066-\u2069]'), '');

Rect _globalRect(SemanticsNode node, double dpr) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    final transform = n.transform;
    if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
  }
  return Rect.fromLTRB(
    rect.left / dpr,
    rect.top / dpr,
    rect.right / dpr,
    rect.bottom / dpr,
  );
}

bool _within(Rect a, Rect b, double tolerance) =>
    (a.left - b.left).abs() <= tolerance &&
    (a.top - b.top).abs() <= tolerance &&
    (a.right - b.right).abs() <= tolerance &&
    (a.bottom - b.bottom).abs() <= tolerance;

String _fmt(Rect r) =>
    '(${r.left.toStringAsFixed(1)}, ${r.top.toStringAsFixed(1)}, '
    '${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)})';
