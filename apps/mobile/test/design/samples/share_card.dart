import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/digit_style_provider.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/result/domain/summary.dart';
import 'package:wassal/features/result/presentation/share_card.dart';
import 'package:wassal/features/trip/domain/looks.dart';

import '../../helpers/design_component.dart';

// `ShareCard` as the board draws it: trip 12 of خط الجامعة at two stars,
// الحاجة's thanks, and 85 paid. On its own 360×360 surface: the picture
// is the card.

/// The board's frame.
const shareBoardSize = Size(ShareCard.side, ShareCard.side);

ShareSpec boardShareSpec() => ShareSpec(
  heading: const ResultHeading(
    tripId: 'line_gamaa.12',
    tripIndex: 12,
    lineName: 'خط الجامعة',
    lastStop: 'الجامعة',
    isStory: false,
  ),
  stars: 2,
  payJenehat: 85,
  quote: (
    look: looks['hagga']!,
    line: 'ربنا يكرمك يا ابني.. الباقي وصل',
    labelKey: looks['hagga']!.labelKey,
  ),
);

Future<void> pumpShareCard(
  WidgetTester tester, {
  DigitStyle digits = DigitStyle.arabicIndic,
}) => pumpDesignComponent(
  tester,
  ShareCard(spec: boardShareSpec()),
  size: shareBoardSize,
  background: ColorTokens.sun,
  overrides: [
    numberFormatterProvider.overrideWithValue(NumberFormatter(digits)),
  ],
);
