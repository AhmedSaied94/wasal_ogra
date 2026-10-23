import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/features/trip/domain/skin_looks.dart';

/// The color token of [shirt].
Color shirtColor(WassalTokens tokens, Shirt shirt) => switch (shirt) {
  Shirt.effendi => tokens.shirts.effendi,
  Shirt.student => tokens.shirts.student,
  Shirt.worker => tokens.shirts.worker,
  Shirt.hajja => tokens.shirts.hajja,
  Shirt.young => tokens.shirts.young,
  Shirt.plain => tokens.shirts.plain,
};
