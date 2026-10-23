import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/containers.dart';
import 'package:wassal/core/theme/components/controls.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/dev/gallery/components_page.dart';
import 'package:wassal/features/dev/gallery/tokens_page.dart';

/// The design gallery (research R4, contracts/components.md "The
/// gallery"): every component and every token, with the digit style,
/// reduced motion and text scale switchable here, apart from the player's
/// own settings. Labels are developer English.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  var _page = 0;
  var _digits = DigitStyle.arabicIndic;
  var _reduced = false;
  var _scale = 1.0;

  static const _scales = [1.0, 1.15, 1.3];

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final numbers = NumberFormatter(_digits);
    return Scaffold(
      backgroundColor: ColorTokens.ground,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Design gallery',
            onBack: () => unawaited(Navigator.of(context).maybePop()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LayoutTokens.gutter,
              SpaceTokens.s8,
              LayoutTokens.gutter,
              SpaceTokens.s8,
            ),
            child: Column(
              spacing: SpaceTokens.s6,
              children: [
                Segmented<int>(
                  value: _page,
                  segments: const [(0, 'Components'), (1, 'Tokens')],
                  onChanged: (v) => setState(() => _page = v),
                ),
                Segmented<DigitStyle>(
                  value: _digits,
                  style: SegmentedStyle.sun,
                  segments: const [
                    (DigitStyle.arabicIndic, 'Arabic'),
                    (DigitStyle.western, 'Western'),
                  ],
                  onChanged: (v) => setState(() => _digits = v),
                ),
                Segmented<double>(
                  value: _scale,
                  style: SegmentedStyle.sun,
                  segments: [for (final s in _scales) (s, '×$s')],
                  onChanged: (v) => setState(() => _scale = v),
                ),
                AppSwitch(
                  label: 'Reduced motion',
                  value: _reduced,
                  onChanged: (v) => setState(() => _reduced = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: MediaQuery(
              data: media.copyWith(
                disableAnimations: _reduced || media.disableAnimations,
                textScaler: TextScaler.linear(_scale),
              ),
              child: _page == 0
                  ? ComponentsPage(numbers: numbers)
                  : TokensPage(numbers: numbers),
            ),
          ),
        ],
      ),
    );
  }
}
