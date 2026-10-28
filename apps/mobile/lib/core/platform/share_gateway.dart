// The phone's share sheet, for the result's picture
// (specs/013-m08-home-result, contracts/result.md "Sharing", research R16):
// `share_plus` behind an interface, as every plugin is.
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:share_plus/share_plus.dart';

part 'share_gateway.g.dart';

abstract interface class ShareGateway {
  /// Offers [png] as [fileName], with [text] beside it where the target
  /// takes text. [origin], the control's global rect, is where an iPad
  /// anchors the sheet. Completes when the sheet closes.
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
    Rect? origin,
  });
}

final class SharePlusGateway implements ShareGateway {
  SharePlusGateway([SharePlus? plus]) : _plus = plus ?? SharePlus.instance;

  final SharePlus _plus;

  static const _mimeType = 'image/png';

  @override
  Future<void> shareImage(
    Uint8List png, {
    required String fileName,
    String? text,
    Rect? origin,
  }) async {
    await _plus.share(
      ShareParams(
        files: [XFile.fromData(png, mimeType: _mimeType, name: fileName)],
        // `XFile.fromData` keeps its name on the web only.
        fileNameOverrides: [fileName],
        text: text,
        // An iPad refuses a share without it.
        sharePositionOrigin: origin,
      ),
    );
  }
}

@Riverpod(keepAlive: true)
ShareGateway shareGateway(Ref ref) => SharePlusGateway();
