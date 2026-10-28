// Home's street (specs/013-m08-home-result, research R13, HANDOFF `C-Home`
// block 2, `HomeStates` block 3): a painted street, the next trip's vehicle
// idling, the roof sign on the microbus, the caller and his bubble, and two
// riders. Built from parts so the sign and the call come from content and
// stay Flutter text. Not tappable in the MVP (the garage is phase 2).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:content_models/content_models.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:rive/rive.dart' as rive;
import 'package:wassal/core/art/rive_art.dart';
import 'package:wassal/core/theme/components/avatars.dart';
import 'package:wassal/core/theme/components/bubble_pop.dart';
import 'package:wassal/core/theme/components/characters.dart';
import 'package:wassal/core/theme/components/vehicle_sprite.dart';
import 'package:wassal/core/theme/tokens/design_extras.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/features/trip/domain/looks.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The scene as `C-Home_02.svg` draws it: 358×332. Everything but the sun
/// and the cloud is anchored to the bottom, so a taller card shows more sky.
const _art = Size(358, 332);

/// Where each vehicle's 236×150 frame stands, in the drawing's units
/// (bottom-anchored): the `Vehicle` artboard and the static art share it.
/// Sized as the boards draw them: the microbus's body from 38 to 322 with
/// its roof at 136 (`C-Home`), the tuktuk's shadow from 66 to 274 with its
/// canopy at 116 (`HomeStates`, 50 lower on the shorter card).
const _bus = Rect.fromLTWH(-10, 93, 381, 242);
const _tuktuk = Rect.fromLTWH(-30, 66, 399, 254);

/// The roof sign over the microbus's roof.
const _sign = Rect.fromLTWH(114, 110, 96, 26);

/// A caller: the centre of his head, and his scale against the rig.
typedef _Caller = ({String svg, int person, Offset head, double scale});

/// The barker (التبّاع) at the microbus's door, a `regular` look.
final _barker = (
  svg: looks['regular']!.svg,
  person: looks['regular']!.rive,
  head: const Offset(284, 186),
  scale: 0.45,
);

/// بلية beside the master's tuktuk.
final _belya = (
  svg: CharacterAvatar.path('belya'),
  person: CharacterAvatar.looks['belya']!,
  head: const Offset(304, 206),
  scale: 0.5,
);

/// The riders' heads in the windows: `regular` and `hagga`.
const _riderLooks = ['regular', 'hagga'];
const _busRiders = [Offset(149, 186), Offset(209, 186)];
const _tuktukRiders = [Offset(190, 178), Offset(234, 188)];

/// The gap between the bubble's tail and the caller's head.
const double _bubbleGap = 4;

/// The bubble's least distance from the card's sides (`C-Home` box 17).
const double _bubbleMargin = SpaceTokens.s8;

/// The rig's head radius, in its own units (the avatars' crop).
const double _headRadius = 42;

/// The passenger and character SVGs' view box, and `Person`'s, both around
/// the head's centre.
const _svgBox = Rect.fromLTWH(-70, -66, 140, 156);
const _personBox = Rect.fromLTWH(-100, -100, 200, 240);

class StreetScene extends StatelessWidget {
  const StreetScene({
    required this.vehicle,
    required this.sign,
    required this.station,
    this.clearTop = 0,
    super.key,
  });

  final VehicleId vehicle;

  /// The roof sign; null on the tuktuk, which has none.
  final String? sign;

  /// The line's last station, which the caller calls; null calls nothing.
  final String? station;

  /// The band at the card's top that the caller's bubble stays below: the
  /// daily row's.
  final double clearTop;

  /// The caller's bubble, for tests.
  static const bubbleKey = Key('StreetScene.bubble');
  static const signKey = Key('StreetScene.sign');

  bool get _tuk => vehicle == VehicleId.tuktuk;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      // The drawing's origin: centred across, anchored to the bottom.
      final dx = (size.width - _art.width) / 2;
      final dy = size.height - _art.height;
      Rect place(Rect r) => r.shift(Offset(dx, dy));
      Offset at(Offset o) => o.translate(dx, dy);
      final caller = _tuk ? _belya : _barker;
      final riders = _tuk ? _tuktukRiders : _busRiders;
      final call = switch (station) {
        final station? => AppLocalizations.of(context).homeBarkerCall(station),
        null => null,
      };
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StreetPainter(dx: dx, dy: dy),
            ),
          ),
          Positioned.fromRect(
            rect: place(_tuk ? _tuktuk : _bus),
            child: ExcludeSemantics(
              child: VehicleSprite(
                vehicle: vehicle,
                fallback: _VehicleArt(vehicle),
              ),
            ),
          ),
          for (final (i, rider) in riders.indexed)
            Positioned(
              left: at(rider).dx - PassengerAvatarSize.mistake.side / 2,
              top: at(rider).dy - PassengerAvatarSize.mistake.side / 2,
              child: PassengerAvatar(
                lookId: _riderLooks[i],
                person: looks[_riderLooks[i]]!.rive,
                size: PassengerAvatarSize.mistake,
              ),
            ),
          if (!_tuk && sign != null)
            Positioned.fromRect(rect: place(_sign), child: _RoofSign(sign!)),
          _figure(caller, at(caller.head)),
          if (call != null)
            Positioned.fill(
              child: _Barker(
                call: call,
                clearTop: clearTop,
                tip: at(caller.head)
                    .translate(0, -(_headRadius * caller.scale + _bubbleGap)),
              ),
            ),
        ],
      );
    },
  );

  /// [caller] with his head's centre at [head].
  Widget _figure(_Caller caller, Offset head) {
    final s = caller.scale;
    final person = Rect.fromLTWH(
      head.dx + _personBox.left * s,
      head.dy + _personBox.top * s,
      _personBox.width * s,
      _personBox.height * s,
    );
    final svg = Rect.fromLTWH(
      (_svgBox.left - _personBox.left) * s,
      (_svgBox.top - _personBox.top) * s,
      _svgBox.width * s,
      _svgBox.height * s,
    );
    return Positioned.fromRect(
      rect: person,
      child: ExcludeSemantics(
        child: RiveArtView(
          artboard: 'Person',
          fit: rive.Fit.fill,
          bind: (model) =>
              model.number('look')?.value = caller.person.toDouble(),
          fallback: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: svg,
                child: SvgPicture.asset(
                  caller.svg,
                  fit: BoxFit.fill,
                  excludeFromSemantics: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The caller's bubble: pops on entering and every
/// [DesignExtras.barkerRepop]; under reduced motion it just shows. Its tail
/// points at [tip]; its body stays inside the card, so a long station
/// name moves it aside, and below [clearTop], as both boards draw it under
/// the daily row.
class _Barker extends StatefulWidget {
  const _Barker({
    required this.call,
    required this.tip,
    required this.clearTop,
  });

  final String call;
  final Offset tip;
  final double clearTop;

  @override
  State<_Barker> createState() => _BarkerState();
}

class _BarkerState extends State<_Barker> {
  Timer? _timer;
  int _pops = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(DesignExtras.barkerRepop, (_) {
        if (mounted) setState(() => _pops++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _OverHead(widget.tip, widget.clearTop),
    children: [
      LayoutId(
        id: _Part.body,
        // A new key builds the bubble anew, and its own pop plays again.
        child: KeyedSubtree(
          key: ValueKey(_pops),
          child: SpeechBubble(
            key: StreetScene.bubbleKey,
            text: widget.call,
            variant: SpeechBubbleVariant.character,
            tail: false,
          ),
        ),
      ),
      LayoutId(
        id: _Part.tail,
        child: KeyedSubtree(
          key: ValueKey(_pops),
          child: const BubblePop(
            child: SpeechBubbleTail(variant: SpeechBubbleVariant.character),
          ),
        ),
      ),
    ],
  );
}

enum _Part { body, tail }

/// The body centred over the tail's [tip], clamped inside the margins, as
/// the trip's bubbles are, and below [clearTop]; the tail stays under the
/// body.
class _OverHead extends MultiChildLayoutDelegate {
  _OverHead(this.tip, this.clearTop);

  final Offset tip;
  final double clearTop;

  @override
  void performLayout(Size size) {
    final body = layoutChild(
      _Part.body,
      BoxConstraints.loose(
        Size(max(0, size.width - 2 * _bubbleMargin), size.height),
      ),
    );
    final top = max(
      clearTop,
      tip.dy - bubbleTailHalfDiagonal + bubbleTailInset - body.height,
    );
    final tailCentre = top + body.height - bubbleTailInset;
    positionChild(
      _Part.body,
      Offset(
        (tip.dx - body.width / 2).clamp(
          _bubbleMargin,
          max(_bubbleMargin, size.width - _bubbleMargin - body.width),
        ),
        top,
      ),
    );
    layoutChild(
      _Part.tail,
      BoxConstraints.tight(const Size.square(DesignExtras.bubbleTail)),
    );
    positionChild(
      _Part.tail,
      Offset(
        tip.dx - DesignExtras.bubbleTail / 2,
        tailCentre - DesignExtras.bubbleTail / 2,
      ),
    );
  }

  @override
  bool shouldRelayout(_OverHead oldDelegate) =>
      oldDelegate.tip != tip || oldDelegate.clearTop != clearTop;
}

/// The microbus's roof sign: the line's last station on `sun`.
class _RoofSign extends StatelessWidget {
  const _RoofSign(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: DecoratedBox(
      key: StreetScene.signKey,
      decoration: BoxDecoration(
        color: ColorTokens.sun,
        borderRadius: BorderRadius.circular(RadiusTokens.pill),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpaceTokens.s8),
            child: Text(
              text,
              maxLines: 1,
              style: DesignExtras.loadingSign.copyWith(color: ColorTokens.ink),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The vehicle's static art without its card's sky, kerb and sun, for the
/// street to show through.
class _VehicleArt extends StatelessWidget {
  const _VehicleArt(this.vehicle);

  final VehicleId vehicle;

  @override
  Widget build(BuildContext context) => SvgPicture(
    _NoBackdropLoader(switch (vehicle) {
      VehicleId.tuktuk => 'assets/illustrations/vehicles/tuktuk.svg',
      _ => 'assets/illustrations/vehicles/microbus_old.svg',
    }),
    fit: BoxFit.fill,
    excludeFromSemantics: true,
  );
}

/// A vehicle SVG without the shapes before its group: the card's sky,
/// kerb and sun.
class _NoBackdropLoader extends SvgAssetLoader {
  const _NoBackdropLoader(super.assetName);

  static final _backdrop = RegExp(r'^(<svg[^>]*>).*?(<g[ >])');

  @override
  String provideSvg(ByteData? message) => utf8
      .decode(Uint8List.sublistView(message!), allowMalformed: true)
      .replaceFirstMapped(_backdrop, (m) => '${m[1]}${m[2]}');

  @override
  SvgCacheKey cacheKey(BuildContext? context) => SvgCacheKey(
    theme: getTheme(context),
    colorMapper: colorMapper,
    keyData: ('street', assetName),
  );
}

/// The sky's sun and cloud at the top; the buildings, kerb and road at the
/// bottom, `C-Home_02.svg`'s shapes.
class _StreetPainter extends CustomPainter {
  const _StreetPainter({required this.dx, required this.dy});

  final double dx;
  final double dy;

  static const _sun = Offset(40, 44);
  static const double _sunRadius = 20;
  static const _bigBump = Radius.circular(_bigBumpRadius);
  static const _smallBump = Radius.circular(_smallBumpRadius);
  static const double _bigBumpRadius = 14;
  static const double _smallBumpRadius = 12;
  static const _buildings = [
    Rect.fromLTWH(-6, 108, 66, 140),
    Rect.fromLTWH(58, 82, 62, 166),
    Rect.fromLTWH(118, 120, 78, 128),
    Rect.fromLTWH(194, 94, 66, 154),
    Rect.fromLTWH(258, 114, 106, 134),
  ];
  static const _windows = [
    Rect.fromLTWH(10, 122, 16, 20),
    Rect.fromLTWH(34, 122, 16, 20),
    Rect.fromLTWH(70, 96, 15, 18),
    Rect.fromLTWH(93, 96, 15, 18),
    Rect.fromLTWH(206, 108, 16, 20),
    Rect.fromLTWH(232, 108, 16, 20),
    Rect.fromLTWH(272, 128, 18, 20),
    Rect.fromLTWH(300, 128, 18, 20),
    Rect.fromLTWH(328, 128, 18, 20),
  ];
  static const double _buildingRadius = 10;
  static const double _windowRadius = 4;
  static const double _kerbTop = 244;
  static const double _roadTop = 262;
  static const double _lane = 312;
  static const double _laneWidth = 5;
  static const double _dash = 34;
  static const double _dashGap = 40;
  static const double _firstDash = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    canvas.drawCircle(
      _sun.translate(dx, 0),
      _sunRadius,
      fill..color = ColorTokens.sunGlow,
    );
    // The cloud: three bumps on a flat base.
    final cloud = Path()
      ..moveTo(70 + dx, 90)
      ..arcToPoint(Offset(96 + dx, 84), radius: _bigBump)
      ..arcToPoint(Offset(116 + dx, 92), radius: _smallBump)
      ..relativeLineTo(-46, 0)
      ..close();
    canvas.drawPath(cloud, fill..color = ColorTokens.paper);

    final shift = Offset(dx, dy);
    for (final (i, b) in _buildings.indexed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          b.shift(shift),
          const Radius.circular(_buildingRadius),
        ),
        fill..color = DesignExtras.homeBuildings[i],
      );
    }
    for (final w in _windows) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          w.shift(shift),
          const Radius.circular(_windowRadius),
        ),
        fill..color = DesignExtras.homeWindow,
      );
    }
    canvas
      ..drawRect(
        Rect.fromLTRB(0, _kerbTop + dy, size.width, _roadTop + dy),
        fill..color = ColorTokens.sceneKerb,
      )
      ..drawRect(
        Rect.fromLTRB(0, _roadTop + dy, size.width, size.height),
        fill..color = ColorTokens.sceneRoad,
      );
    final lane = Paint()
      ..color = DesignExtras.homeLane
      ..strokeWidth = _laneWidth
      ..strokeCap = StrokeCap.round;
    // The dashes repeat from the drawing's first one, across the width.
    const period = _dash + _dashGap;
    var x = _firstDash + dx;
    while (x > 0) {
      x -= period;
    }
    for (; x < size.width; x += period) {
      canvas.drawLine(
        Offset(x, _lane + dy),
        Offset(x + _dash, _lane + dy),
        lane,
      );
    }
  }

  @override
  bool shouldRepaint(_StreetPainter old) => old.dx != dx || old.dy != dy;
}
