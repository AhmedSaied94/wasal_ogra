// The picture «شارك» hands to the share sheet (specs/015-m10-apartment-story,
// contracts/scene-viewer.md "Share"): the panel's still drawing, its bubbles,
// and a small wordmark strip, at 358×540 and drawn ×3 off screen.
import 'package:content_models/content_models.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/onboarding/presentation/scene_player.dart';
import 'package:wassal/features/story/presentation/scene_panel_view.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The speaker labels of a shared picture. The driver is the default name,
/// never the player's own: the picture leaves the phone with nothing of the
/// player's in it (contracts/scene-viewer.md "Share").
String shareSpeakerName(AppLocalizations l10n, String speaker) =>
    speaker == ScenePlayer.driver
    ? l10n.driverNameDefault
    : l10n.sceneSpeaker(speaker);

class ScenePanelShare extends StatelessWidget {
  const ScenePanelShare({
    required this.panel,
    required this.speakerName,
    super.key,
  });

  final Panel panel;
  final SpeakerName speakerName;

  static const Size size = ScenePanelView.frame;

  static const stripKey = Key('ScenePanelShare.strip');

  /// The wordmark's strip over the panel's foot.
  static const double _strip = 40;

  @override
  Widget build(BuildContext context) {
    // A picture: still (the static art, never Rive), every bubble shown, and
    // at its own size whatever the player's text scale.
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.noScaling, disableAnimations: true),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ScenePanelView(panel: panel, speakerName: speakerName),
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 0,
              height: _strip,
              child: ColoredBox(
                key: stripKey,
                color: ColorTokens.sun,
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).appName,
                    style: DesignExtras.shareWordmark.copyWith(
                      color: ColorTokens.ink,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
