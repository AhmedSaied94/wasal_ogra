import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'flavor.g.dart';

/// Build variants (mobile §21). Android flavors live in
/// `android/app/build.gradle.kts`; iOS schemes arrive in phase 3.
enum Flavor {
  dev,
  staging,
  prod;

  /// Fails loudly on a missing or unknown flavor: every build must pass
  /// `--flavor dev|staging|prod`.
  static Flavor fromName(String? name) => switch (name) {
    'dev' => dev,
    'staging' => staging,
    'prod' => prod,
    _ => throw StateError(
      'Unknown or missing build flavor "$name". '
      'Build with --flavor dev, staging or prod.',
    ),
  };
}

/// The running build's flavor. Tests override it.
@Riverpod(keepAlive: true)
Flavor flavor(Ref ref) => Flavor.fromName(appFlavor);
