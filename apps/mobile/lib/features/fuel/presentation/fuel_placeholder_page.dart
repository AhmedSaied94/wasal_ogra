// The fuel sheet until M12 (specs/018-m11-ads, research R17): M03's
// placeholder with the refill ad and its BONAT refill on it, so the free
// refill is there from the out-of-fuel card's «البنزين» too. A full tank
// closes the sheet.
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/routing/placeholder_screen.dart';
import 'package:wassal/core/routing/routes.dart';
import 'package:wassal/features/fuel/presentation/fuel_refill_ad_offer.dart';

class FuelPlaceholderPage extends StatelessWidget {
  const FuelPlaceholderPage({required this.destination, super.key});

  final Destination destination;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    destination: destination,
    extra: FuelRefillAdOffer(
      onFilled: () {
        if (context.canPop()) context.pop();
      },
    ),
  );
}
