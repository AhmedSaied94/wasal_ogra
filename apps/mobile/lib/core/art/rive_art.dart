// The owner's Rive file (specs/008.5-m21-design-refresh,
// contracts/rive-characters.md): decoded once in the boot step `art`,
// checked against the contract, and drawn wherever an artboard passed. A
// file that fails to load, or an artboard that fails its check, falls back
// to the static art; the problems show in the debug panel. It holds people,
// vehicles and UI animations, so it lives in core, beside the theme.
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'rive_art.g.dart';

const riveArtAsset = 'assets/rive/wassal.riv';

/// What the contract asks of an artboard: its size, its state machine, and
/// its default view model with these properties (none for a bare loop).
typedef ArtboardSpec = ({
  Size size,
  String machine,
  String? viewModel,
  Map<String, rive.DataType> properties,
});

ArtboardSpec _loop(Size size, String machine) =>
    (size: size, machine: machine, viewModel: null, properties: const {});

const _fx = {'play': rive.DataType.trigger};

/// contracts/rive-characters.md "The file", "People", "Vehicles" and "UI
/// animations".
final riveContract = <String, ArtboardSpec>{
  'Person': (
    size: const Size(200, 240),
    machine: 'Passenger',
    viewModel: 'Passenger',
    properties: const {
      'look': rive.DataType.number,
      'mood': rive.DataType.number,
      'talking': rive.DataType.boolean,
      'asleep': rive.DataType.boolean,
      'headphones': rive.DataType.boolean,
      'changeDue': rive.DataType.boolean,
      'claim': rive.DataType.boolean,
      'surprised': rive.DataType.boolean,
      'board': rive.DataType.trigger,
      'alight': rive.DataType.trigger,
      'call': rive.DataType.trigger,
      'happy': rive.DataType.trigger,
      'targeted': rive.DataType.trigger,
    },
  ),
  'Vehicle': (
    size: const Size(236, 150),
    machine: 'Vehicle',
    viewModel: 'Vehicle',
    properties: const {
      'look': rive.DataType.number,
      'driving': rive.DataType.boolean,
      'brake': rive.DataType.trigger,
      'honk': rive.DataType.trigger,
    },
  ),
  'CoachHand': _loop(const Size(100, 100), 'CoachHand'),
  'LoadingWheel': _loop(const Size(80, 80), 'LoadingWheel'),
  'RingShine': _loop(const Size(120, 120), 'RingShine'),
  'Stars': (
    size: const Size(240, 100),
    machine: 'Stars',
    viewModel: 'Stars',
    properties: const {'stars': rive.DataType.number},
  ),
  'CoinsBurst': (
    size: const Size(200, 200),
    machine: 'CoinsBurst',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'BonatBurst': (
    size: const Size(200, 200),
    machine: 'BonatBurst',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'Confetti': (
    size: const Size(390, 300),
    machine: 'Confetti',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'FuelGauge': (
    size: const Size(156, 110),
    machine: 'FuelGauge',
    viewModel: 'Fuel',
    properties: const {'level': rive.DataType.number},
  ),
  'GiftOpen': (
    size: const Size(160, 160),
    machine: 'GiftOpen',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'SparklePlace': (
    size: const Size(120, 120),
    machine: 'SparklePlace',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'NotifBell': (
    size: const Size(60, 60),
    machine: 'NotifBell',
    viewModel: 'Fx',
    properties: _fx,
  ),
  'Splash': (
    size: const Size(236, 150),
    machine: 'Splash',
    viewModel: 'Splash',
    properties: const {},
  ),
};

/// What boot decoded: the file, the artboards that passed the contract
/// check, and what the check found.
@immutable
final class RiveArt {
  const RiveArt({
    required this.file,
    required this.usable,
    required this.problems,
  });

  /// No file: everything is drawn with the static art.
  const RiveArt.none([this.problems = const []])
    : file = null,
      usable = const {};

  final rive.File? file;
  final Set<String> usable;
  final List<String> problems;

  /// Whether [artboard] can be drawn.
  bool has(String artboard) => file != null && usable.contains(artboard);
}

/// Artboards the export adds, which the app never draws: the file's default
/// frame and the free plan's Rive splash (contracts/rive-characters.md
/// "Export").
const riveExportArtboards = {
  'iPhone 16 - 1',
  'Watermark',
  'NuRiveBrandmark01',
  'NuRiveWordmark01',
};

/// [file] against [riveContract]: the artboards that pass, and a problem
/// for each that doesn't, or that neither the contract nor
/// [riveExportArtboards] names.
RiveArt checkRiveArt(rive.File file) {
  final usable = <String>{};
  final problems = <String>[];
  final seen = <String>{};
  for (var i = 0; ; i++) {
    final artboard = file.artboardAt(i);
    if (artboard == null) break;
    seen.add(artboard.name);
    if (!riveContract.containsKey(artboard.name) &&
        !riveExportArtboards.contains(artboard.name)) {
      problems.add('artboard ${artboard.name}: not in the contract');
    }
    artboard.dispose();
  }
  for (final MapEntry(key: name, value: spec) in riveContract.entries) {
    if (!seen.contains(name)) {
      problems.add('artboard $name: missing');
      continue;
    }
    final found = _check(file, name, spec);
    if (found.isEmpty) {
      usable.add(name);
    } else {
      problems.addAll(found);
    }
  }
  return RiveArt(file: file, usable: usable, problems: problems);
}

List<String> _check(rive.File file, String name, ArtboardSpec spec) {
  final problems = <String>[];
  final artboard = file.artboard(name)!;
  try {
    if (artboard.width != spec.size.width ||
        artboard.height != spec.size.height) {
      problems.add(
        'artboard $name: ${artboard.width}×${artboard.height}, '
        'not ${spec.size.width}×${spec.size.height}',
      );
    }
    final machine = artboard.stateMachine(spec.machine);
    if (machine == null) {
      problems.add('artboard $name: no state machine ${spec.machine}');
    }
    machine?.dispose();
    final wanted = spec.viewModel;
    if (wanted == null) return problems;
    final model = file.defaultArtboardViewModel(artboard);
    try {
      if (model?.name != wanted) {
        problems.add(
          'artboard $name: view model ${model?.name ?? 'none'}, not $wanted',
        );
        return problems;
      }
      final types = {for (final p in model!.properties) p.name: p.type};
      for (final MapEntry(key: property, value: type)
          in spec.properties.entries) {
        if (types[property] != type) {
          problems.add(
            'view model $wanted: $property is ${types[property]?.name ?? 'missing'}, '
            'not ${type.name}',
          );
        }
      }
    } finally {
      model?.dispose();
    }
  } finally {
    artboard.dispose();
  }
  return problems;
}

/// Decodes [asset] and checks it with [check]. It never throws: whatever
/// stops the file (no asset in the build, no native library, a bad file, a
/// check that fails) is a problem, and everything is drawn with the static
/// art.
Future<RiveArt> loadRiveArt({
  String asset = riveArtAsset,
  AssetBundle? bundle,
  RiveArt Function(rive.File file) check = checkRiveArt,
}) async {
  final rive.File? file;
  try {
    file = await rive.File.asset(
      asset,
      riveFactory: rive.Factory.flutter,
      bundle: bundle,
    );
  } on Object catch (error) {
    return RiveArt.none(['$asset: $error']);
  }
  if (file == null) return RiveArt.none(['$asset: not a Rive file']);
  try {
    return check(file);
  } on Object catch (error) {
    file.dispose();
    return RiveArt.none(['$asset: $error']);
  }
}

/// The art file, decoded once during startup (the boot step `art`).
@Riverpod(keepAlive: true)
Future<RiveArt> riveArt(Ref ref) async {
  final art = await loadRiveArt();
  ref.onDispose(() => art.file?.dispose());
  return art;
}

/// The decoded file for the art below it: `bootstrap/app.dart` puts it over
/// the app. Without one, as in tests and goldens, every [RiveArtView] draws
/// its fallback.
class RiveArtScope extends InheritedWidget {
  const RiveArtScope({required this.art, required super.child, super.key});

  final RiveArt? art;

  static RiveArt? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RiveArtScope>()?.art;

  @override
  bool updateShouldNotify(RiveArtScope oldWidget) =>
      !identical(oldWidget.art, art);
}

/// One artboard of the file as a widget, its state machine playing and its
/// view model set by [bind] on every build. [fallback] draws instead while
/// there is no file, when the artboard failed its check, and under reduced
/// motion (the file can't hold its effects still yet: contracts/
/// rive-characters.md "Open" 2).
class RiveArtView extends StatefulWidget {
  const RiveArtView({
    required this.artboard,
    required this.fallback,
    this.bind,
    this.fit = rive.Fit.contain,
    super.key,
  });

  final String artboard;
  final Widget fallback;
  final void Function(rive.ViewModelInstance model)? bind;
  final rive.Fit fit;

  @override
  State<RiveArtView> createState() => _RiveArtViewState();
}

class _RiveArtViewState extends State<RiveArtView> {
  rive.RiveWidgetController? _controller;
  rive.ViewModelInstance? _model;
  rive.File? _file;

  /// Opens [file]'s artboard, once per file. False when its view model has
  /// no instance to bind, so [build] draws the fallback.
  bool _open(rive.File file) {
    if (identical(file, _file)) return _controller != null;
    _close();
    _file = file;
    final spec = riveContract[widget.artboard]!;
    final controller = rive.RiveWidgetController(
      file,
      artboardSelector: rive.ArtboardSelector.byName(widget.artboard),
      stateMachineSelector: rive.StateMachineSelector.byName(spec.machine),
    );
    if (spec.viewModel != null) {
      // As the passengers do: the exported default instance, or a new one
      // (`DataBind.auto()` throws without the first).
      final model = file.defaultArtboardViewModel(controller.artboard);
      final instance =
          model?.createDefaultInstance() ?? model?.createInstance();
      model?.dispose();
      if (instance == null) {
        controller.dispose();
        return false;
      }
      _model = controller.dataBind(rive.DataBind.byInstance(instance));
    }
    _controller = controller;
    return true;
  }

  void _close() {
    _model?.dispose();
    _controller?.dispose();
    _model = null;
    _controller = null;
    _file = null;
  }

  @override
  void didUpdateWidget(RiveArtView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artboard != widget.artboard) _close();
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final art = RiveArtScope.maybeOf(context);
    final file = art?.file;
    if (art == null ||
        file == null ||
        !art.has(widget.artboard) ||
        MediaQuery.disableAnimationsOf(context)) {
      _close();
      return widget.fallback;
    }
    if (!_open(file)) return widget.fallback;
    if (_model case final model?) widget.bind?.call(model);
    return rive.RiveWidget(controller: _controller!, fit: widget.fit);
  }
}
