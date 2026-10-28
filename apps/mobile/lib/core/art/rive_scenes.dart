// The scenes' Rive file (specs/012.5-m22-animated-scenes,
// contracts/rive-scenes.md): the first session's comic panels, decoded beside
// the characters' file in the boot step `art` and checked against
// [sceneContract]. A panel whose artboard passed animates; any other panel,
// or every panel without the file, shows its drawing.
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:wassal/core/art/rive_art.dart';

part 'rive_scenes.g.dart';

const riveScenesAsset = 'assets/rive/wassal_scenes.riv';

/// `Intro` box 3: a panel on the reference frame.
const scenePanelSize = Size(358, 540);

/// Each panel's state machine and default view model.
const scenePanelMachine = 'Panel';
const scenePanelViewModel = 'Panel';

/// The panel view model's Booleans, one per character: true makes that
/// character talk where the panel draws them.
const sceneTalkers = ['moallem', 'usta', 'belya', 'salma'];

/// The panels, one per drawing (contracts/rive-scenes.md "The panels").
const scenePanelSlugs = [
  'opening_key',
  'opening_stand',
  'opening_go',
  'stand_morning',
  'salma_waiting',
  'usta_decides',
];

/// The building blocks the panels nest, never opened on their own.
const sceneBuildingBlocks = {
  'Character_usta',
  'Character_moallem',
  'Character_belya',
  'Character_salma',
  'Prop_tin',
  'Prop_key',
  'Prop_drawer',
  'Prop_busstop',
  'Prop_books',
  'Prop_bag',
  'Tuktuk',
};

/// The export's own artboards: the file's default and Rive's splash.
const sceneExportArtboards = {
  'Artboard 1',
  'Watermark',
  'NuRiveBrandmark01',
  'NuRiveWordmark01',
};

/// contracts/rive-scenes.md "The contract".
final sceneContract = RiveContract(
  asset: riveScenesAsset,
  artboards: {
    for (final slug in scenePanelSlugs)
      slug: (
        size: scenePanelSize,
        machine: scenePanelMachine,
        viewModel: scenePanelViewModel,
        properties: {
          for (final talker in sceneTalkers) talker: rive.DataType.boolean,
        },
      ),
  },
  known: {...sceneBuildingBlocks, ...sceneExportArtboards},
);

/// The scenes' file, decoded once during startup (the boot step `art`).
@Riverpod(keepAlive: true)
Future<RiveArt> riveScenes(Ref ref) async {
  final art = await loadRiveArt(contract: sceneContract);
  ref.onDispose(() => art.file?.dispose());
  return art;
}

/// Which panels can animate: those whose artboard passed, once the file has
/// loaded. Before that, or without it, none.
@immutable
final class ScenePanels {
  const ScenePanels(this._animated);

  const ScenePanels.none() : _animated = const {};

  ScenePanels.of(RiveArt? art)
    : _animated = art?.file == null ? const {} : art!.usable;

  final Set<String> _animated;

  /// Whether the panel drawn as [artSlug] (`PanelArt.artFor`) animates.
  bool animates(String artSlug) => _animated.contains(artSlug);
}

/// The panels that animate, from [riveScenesProvider]. Tests override it.
@riverpod
ScenePanels scenePanels(Ref ref) =>
    ScenePanels.of(ref.watch(riveScenesProvider).value);
