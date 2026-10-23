// The owner's Rive art as the app draws it (tasks.md T100,
// contracts/rive-characters.md "Tests"): one sheet per MVP look in the
// seven poses a passenger shows, at the near-row and back-row face sizes;
// the six story characters in `idle` and `talk`; the four vehicles in
// `idle`; and the UI loops. Drawn with `Factory.flutter`. Generated on
// Linux; CI's run is the reference.
@Tags(['rive'])
library;

import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:trip_engine/trip_engine.dart';
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/features/trip/domain/trip_view.dart';
import 'package:wassal/features/trip/presentation/scene/passenger_art.dart';
import 'package:wassal/features/trip/presentation/scene/rive_passenger_art.dart';

/// A passenger's view in each pose the scene shows (data-model.md
/// `CharacterPose`), by the pose's name.
final _poses = <String, PassengerView Function(Look look)>{
  'idle': (look) => _view(look),
  'talk': (look) => _view(look, talking: true),
  'impatient_2': (look) => _view(look, mood: 2),
  'sleep': (look) => _view(look, asleep: true),
  'headphones': (look) => _view(look, headphones: true),
  // Seated: getting off also fires `alight`, which ends invisible.
  'fight': (look) => _view(look, mood: 3, outcome: AlightOutcome.fight),
  'claim': (look) => _view(look, claimOpen: true),
};

PassengerView _view(
  Look look, {
  int mood = 0,
  bool talking = false,
  bool asleep = false,
  bool headphones = false,
  bool claimOpen = false,
  PresenceView presence = PresenceView.aboard,
  AlightOutcome? outcome,
}) => PassengerView(
  passengerId: 'p1',
  seatId: 'A_r',
  presence: presence,
  look: look,
  slot: 0,
  mood: mood,
  talking: talking,
  asleep: asleep,
  waking: false,
  headphones: headphones,
  attentive: false,
  nearStopPulse: false,
  dropMeHere: false,
  ledgerBadge: null,
  outcome: outcome,
  claimOpen: claimOpen,
);

/// The story characters' `look` numbers (contracts/rive-characters.md
/// "Looks").
const _characters = {
  'usta': 18,
  'salma': 19,
  'bride_father': 20,
  'bride_mother': 21,
  'moallem': 22,
  'belya': 23,
};

/// A near-row and a back-row face (HANDOFF §5.1: 84, and 84 × 0.625).
const _faces = [84.0, 52.5];

/// Long enough for every state's blend and the `alight` rise to settle the
/// same way each run.
const _settleS = 1.0;
const _frame = 1 / 60;

class _Paint extends CustomPainter {
  _Paint(this.draw);

  final void Function(Canvas canvas) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas);

  @override
  bool shouldRepaint(_Paint oldDelegate) => false;
}

void _settle(void Function(double dt) advance) {
  for (var t = 0.0; t < _settleS; t += _frame) {
    advance(_frame);
  }
}

/// [art] drawn with its head filling a [face]-wide square, in a cell as
/// big as the whole artboard at that scale.
Widget _passengerCell(PassengerArt art, double face) {
  final scale = face / (2 * personHeadRadius);
  final cell = const Size(200, 240) * scale;
  final head = Rect.fromCenter(
    center: personHead * scale,
    width: face,
    height: face,
  );
  return CustomPaint(
    size: cell,
    painter: _Paint((canvas) => art.render(canvas, head)),
  );
}

/// [name]'s artboard with its default view model, set by [bind], playing
/// for [_settleS] and drawn at its size.
Widget _artboardCell(
  rive.File file,
  String name, {
  void Function(rive.ViewModelInstance model)? bind,
}) {
  final spec = riveContract[name]!;
  final artboard = file.artboard(name)!;
  final machine = artboard.stateMachine(spec.machine)!;
  final model = file.defaultArtboardViewModel(artboard);
  final instance = model?.createDefaultInstance();
  model?.dispose();
  if (instance != null) {
    machine.bindViewModelInstance(instance);
    bind?.call(instance);
  }
  _settle(machine.advanceAndApply);
  addTearDown(() {
    instance?.dispose();
    machine.dispose();
    artboard.dispose();
  });
  return CustomPaint(
    size: spec.size,
    painter: _Paint((canvas) {
      final renderer = rive.Renderer.make(canvas);
      renderer.align(
        rive.Fit.fill,
        Alignment.topLeft,
        rive.AABB.fromValues(0, 0, spec.size.width, spec.size.height),
        artboard.bounds,
        1,
      );
      artboard.draw(renderer);
      renderer.dispose();
    }),
  );
}

Future<void> _expectSheet(
  WidgetTester tester,
  List<List<Widget>> rows,
  String name,
) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          child: ColoredBox(
            color: const Color(0xFFE8F4FB),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: row,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await expectLater(
    find.byType(RepaintBoundary).first,
    matchesGoldenFile('goldens/rive_$name.png'),
  );
}

void main() {
  late rive.File file;
  late RivePassengerArtFactory people;

  setUpAll(() async {
    await rive.RiveNative.init();
    final bytes = io.File(riveArtAsset).readAsBytesSync();
    file = (await rive.File.decode(bytes, riveFactory: rive.Factory.flutter))!;
    people = RivePassengerArtFactory.of(file);
  });

  tearDownAll(() => file.dispose());

  PassengerArt posed(Look look, PassengerView view) {
    final art = people.create(look)..update(view);
    addTearDown(art.dispose);
    _settle(art.advance);
    return art;
  }

  for (final look in looks.values) {
    testWidgets('${look.id}: each pose at both face sizes', (tester) async {
      await _expectSheet(tester, [
        for (final face in _faces)
          [
            for (final pose in _poses.values)
              _passengerCell(posed(look, pose(look)), face),
          ],
      ], 'look_${look.id}');
    });
  }

  testWidgets('the six characters in idle and talk', (tester) async {
    final looks = [
      for (final MapEntry(key: id, value: number) in _characters.entries)
        Look(id: id, labelKey: '', rive: number),
    ];
    await _expectSheet(tester, [
      for (final pose in [_poses['idle']!, _poses['talk']!])
        [
          for (final look in looks)
            _passengerCell(posed(look, pose(look)), _faces.first),
        ],
    ], 'characters');
  });

  testWidgets('the four vehicles in idle', (tester) async {
    await _expectSheet(tester, [
      [
        for (var look = 0; look < 4; look++)
          _artboardCell(
            file,
            'Vehicle',
            bind: (model) {
              model.number('look')?.value = look.toDouble();
              model.boolean('driving')?.value = false;
            },
          ),
      ],
    ], 'vehicles');
  });

  testWidgets('the UI loops', (tester) async {
    await _expectSheet(tester, [
      [
        _artboardCell(file, 'CoachHand'),
        _artboardCell(file, 'LoadingWheel'),
        _artboardCell(file, 'RingShine'),
        _artboardCell(
          file,
          'Stars',
          bind: (model) => model.number('stars')?.value = 3,
        ),
        _artboardCell(
          file,
          'FuelGauge',
          bind: (model) => model.number('level')?.value = 60,
        ),
      ],
    ], 'ui');
  });
}
