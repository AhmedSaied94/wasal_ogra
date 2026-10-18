// Tunables for the Application layer only (constitution VIII). The trip
// engine never reads ConfigSource: it receives tunables as explicit params.
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/bootstrap/flavor.dart';
import 'package:wassal/core/config/bundled_config_source.dart';
import 'package:wassal/core/config/config_source.dart';
import 'package:wassal/core/config/override_config_source.dart';

part 'config_providers.g.dart';

const bundledTunablesAsset = 'assets/config/tunables.json';

/// Bundled only in the dev variant (research R12).
const devTunablesAsset = 'assets/config/tunables.dev.json';

/// Reads a bundled text asset, or null when this variant does not bundle it.
typedef AssetReader = Future<String?> Function(String path);

@Riverpod(keepAlive: true)
AssetReader assetReader(Ref ref) => _readBundledAsset;

Future<String?> _readBundledAsset(String path) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  if (!manifest.listAssets().contains(path)) return null;
  return rootBundle.loadString(path);
}

/// The raw layers, loaded once during startup.
@immutable
class TunableLayers {
  const TunableLayers({required this.defaults, required this.overrides});

  final Map<String, Object?> defaults;
  final Map<String, Object?> overrides;
}

@Riverpod(keepAlive: true)
Future<TunableLayers> tunableLayers(Ref ref) async {
  final read = ref.watch(assetReaderProvider);
  final defaults = await read(bundledTunablesAsset);
  if (defaults == null) {
    throw StateError('$bundledTunablesAsset is missing from the bundle.');
  }
  final dev = ref.watch(flavorProvider) == Flavor.dev
      ? await read(devTunablesAsset)
      : null;
  return TunableLayers(
    defaults: _decode(defaults),
    overrides: dev == null ? const {} : _decode(dev),
  );
}

Map<String, Object?> _decode(String json) =>
    (jsonDecode(json) as Map<String, dynamic>).cast<String, Object?>();

/// The tunables, readable synchronously once startup has completed.
@Riverpod(keepAlive: true)
ConfigSource configSource(Ref ref) {
  final layers = ref.watch(tunableLayersProvider).requireValue;
  final bundled = BundledConfigSource(layers.defaults);
  return layers.overrides.isEmpty
      ? bundled
      : OverrideConfigSource(layers.overrides, fallback: bundled);
}
