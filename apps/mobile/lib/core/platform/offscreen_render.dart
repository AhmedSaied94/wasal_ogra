// Drawing a widget to a PNG off screen (specs/013-m08-home-result research
// R16, generalised by specs/015-m10-apartment-story research R12): the
// result's share card and a story panel's picture both go through it.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// The picture couldn't be drawn.
final class ShareRenderException implements Exception {
  const ShareRenderException(this.message);

  final String message;

  @override
  String toString() => 'ShareRenderException: $message';
}

/// The default scale: a 360-wide card becomes 1080.
const double offscreenPixelRatio = 3;

/// Frames before the capture: the first builds the picture and starts its
/// assets, which arrive, already loaded, for the second.
const int _framesBeforeCapture = 2;

/// [child] as a PNG of [logicalSize] at [pixelRatio]: built off screen over
/// [context]'s overlay for a frame or two, then captured and removed.
///
/// The caller loads what [child] draws (its SVGs) first, so the capture
/// finds it. Nothing is fetched here, so it works offline.
Future<Uint8List> renderOffscreenPng(
  BuildContext context,
  Widget child,
  Size logicalSize, {
  double pixelRatio = offscreenPixelRatio,
}) async {
  if (!context.mounted) {
    throw const ShareRenderException('the screen closed');
  }
  final boundary = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Off screen, beside it.
      left: -logicalSize.width * 2,
      top: 0,
      width: logicalSize.width,
      height: logicalSize.height,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(key: boundary, child: child),
        ),
      ),
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  try {
    final binding = WidgetsBinding.instance;
    for (var i = 0; i < _framesBeforeCapture; i++) {
      binding.scheduleFrame();
      await binding.endOfFrame;
    }
    final render = boundary.currentContext?.findRenderObject();
    if (render is! RenderRepaintBoundary) {
      throw const ShareRenderException('the picture was not laid out');
    }
    final image = await render.toImage(pixelRatio: pixelRatio);
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw const ShareRenderException('no PNG');
      return png.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    entry.remove();
  }
}
