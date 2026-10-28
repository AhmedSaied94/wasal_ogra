import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/content/home_arrival.dart';
import 'package:wassal/core/routing/router.dart';
import 'package:wassal/features/onboarding/onboarding_providers.dart';
import 'package:wassal/features/onboarding/presentation/name_sheet.dart';

/// Home's re-ask (specs/012-m07-onboarding/contracts/name.md "The
/// re-ask"): on an arrival at Home, at most once a launch, the Name sheet
/// for a name the server refused, or for one never given once a trip has
/// started. Home is never on screen during a trip, so it never asks there.
class NameReaskHost extends ConsumerStatefulWidget {
  const NameReaskHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<NameReaskHost> createState() => _NameReaskHostState();
}

class _NameReaskHostState extends ConsumerState<NameReaskHost> {
  late final HomeArrival _arrival;

  @override
  void initState() {
    super.initState();
    // Back from another section; and this build is an arrival too.
    _arrival = HomeArrival(ref.read(routerProvider), _arrived);
    WidgetsBinding.instance.addPostFrameCallback((_) => _arrived());
  }

  @override
  void dispose() {
    _arrival.dispose();
    super.dispose();
  }

  void _arrived() {
    if (!mounted) return;
    final router = ref.read(routerProvider);
    if (router.state.uri.path != HomeArrival.homePath) return;
    final asked = ref.read(nameAskedProvider.notifier);
    final session = ref.read(firstSessionProvider);
    if (asked.done || !session.askName) return;
    // The root navigator's: over the bottom nav, as every sheet.
    final root = router.routerDelegate.navigatorKey.currentContext;
    if (root == null) return;
    asked.done = true;
    unawaited(showNameSheet(root, refused: session.facts.nameRefused));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
