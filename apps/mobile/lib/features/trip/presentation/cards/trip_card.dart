// A card over the darkened trip (contracts/scene-layout.md layer 9): the
// pause, the failure, a dispute, a purchase, the empty tank, a retry.
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/theme/app_theme.dart';
import 'package:wassal/core/theme/components/sticker_card.dart';
import 'package:wassal/core/theme/tokens/space.dart';
import 'package:wassal/core/theme/tokens/typography.dart';

class TripCard extends StatelessWidget {
  const TripCard({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // Modal: the controls under the card are gone for the screen reader
    // too, as they are for the finger.
    return BlockSemantics(
      child: ColoredBox(
        color: tokens.hibr.withValues(alpha: 0.6),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(SpaceTokens.l),
              child: StickerCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TypeTokens.headline.copyWith(color: tokens.hibr),
                      ),
                    ),
                    const SizedBox(height: SpaceTokens.l),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of body text in a card.
class CardText extends StatelessWidget {
  const CardText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: SpaceTokens.m),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TypeTokens.body.copyWith(color: context.tokens.hibr),
    ),
  );
}

/// A small line under a button, clear of its hard shadow.
class CardNote extends StatelessWidget {
  const CardNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: SpaceTokens.m),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TypeTokens.caption.copyWith(color: context.tokens.hibr),
    ),
  );
}
