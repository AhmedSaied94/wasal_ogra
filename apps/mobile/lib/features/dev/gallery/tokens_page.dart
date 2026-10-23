import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/number_formatter.dart';
import 'package:wassal/core/theme/components/pressable.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';
import 'package:wassal/l10n/generated/app_localizations.dart';

/// The tokens page: every colour with its name and hex, the type scale on
/// Arabic sample lines, radii, lips, rings and motion (tap one to play it).
/// Not lazy, so a test finds every swatch without scrolling.
class TokensPage extends StatelessWidget {
  const TokensPage({required this.numbers, super.key});

  final NumberFormatter numbers;

  /// A colour's swatch, by its `ColorTokens` name.
  static Key swatchKey(String name) => ValueKey('gallery.swatch.$name');

  static const _typeNames = [
    'display.xl',
    'display.l',
    'button.xl',
    'display.m',
    'button.l',
    'display.s',
    'quote',
    'number.l',
    'bubble',
    'row',
    'body',
    'caption',
    'label',
  ];

  static const _radii = [
    ('xs', RadiusTokens.xs),
    ('s', RadiusTokens.s),
    ('tray', RadiusTokens.tray),
    ('m', RadiusTokens.m),
    ('bubble', RadiusTokens.bubble),
    ('l', RadiusTokens.l),
    ('card', RadiusTokens.card),
    ('xl', RadiusTokens.xl),
    ('scene', RadiusTokens.scene),
    ('sheet', RadiusTokens.sheet),
  ];

  static const _lips = [
    ('card', LipTokens.card),
    ('cardSmall', LipTokens.cardSmall),
    ('cardBig', LipTokens.cardBig),
    ('primary', LipTokens.primary),
    ('primaryM', LipTokens.primaryM),
    ('primaryS', LipTokens.primaryS),
    ('sun', LipTokens.sun),
    ('sunS', LipTokens.sunS),
    ('sunBig', LipTokens.sunBig),
    ('sunSoft', LipTokens.sunSoft),
    ('danger', LipTokens.danger),
    ('dark', LipTokens.dark),
    ('trayCell', LipTokens.trayCell),
    ('bubble', LipTokens.bubble),
    ('bubbleWarn', LipTokens.bubbleWarn),
    ('popover', LipTokens.popover),
    ('noteFare', LipTokens.noteFare),
    ('noteChange', LipTokens.noteChange),
    ('dialog', LipTokens.dialog),
    ('chip', LipTokens.chip),
  ];

  static const _rings = [
    ('locked', RingTokens.locked),
    ('empty', RingTokens.empty),
    ('selected', RingTokens.selected),
    ('hot', RingTokens.hot),
  ];

  static const _motion = [
    ('press', MotionTokens.press, MotionTokens.pressCurve),
    ('sheetIn', MotionTokens.sheetIn, MotionTokens.sheetInCurve),
    ('sheetOut', MotionTokens.sheetOut, MotionTokens.sheetOutCurve),
    ('dialogIn', MotionTokens.dialogIn, MotionTokens.dialogInCurve),
    ('toast', MotionTokens.toast, MotionTokens.toastCurve),
    ('bubblePop', MotionTokens.bubblePop, MotionTokens.bubblePopCurve),
    ('starIn', MotionTokens.starIn, MotionTokens.starInCurve),
    ('hotTagPulse', MotionTokens.hotTagPulse, Curves.easeInOut),
    ('alight', MotionTokens.alight, Curves.easeOut),
    ('screenShake', MotionTokens.screenShake, Curves.linear),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final letters = [
      l10n.tripStationLetter1,
      l10n.tripStationLetter2,
      l10n.tripStationLetter3,
      l10n.tripStationLetter4,
    ];
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        LayoutTokens.gutter,
        SpaceTokens.s8,
        LayoutTokens.gutter,
        SpaceTokens.s24 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: SpaceTokens.s12,
        children: [
          const _Heading('Colours'),
          Wrap(
            spacing: SpaceTokens.s8,
            runSpacing: SpaceTokens.s8,
            children: [
              for (final MapEntry(key: name, value: color)
                  in ColorTokens.named.entries)
                _Swatch(key: swatchKey(name), name: name, color: color),
              for (final (i, skin) in ColorTokens.characterSkin.indexed)
                _Swatch(name: 'characterSkin[$i]', color: skin),
            ],
          ),
          const _Heading('Stations'),
          Row(
            spacing: SpaceTokens.s8,
            children: [
              for (final (i, station) in StationColors.all.indexed)
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: station.bg,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    letters[i],
                    style: TypeTokens.label.copyWith(color: station.letter),
                  ),
                ),
            ],
          ),
          const _Heading('Type'),
          for (final (i, style) in TypeTokens.all.indexed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Caption(
                  '${_typeNames[i]} · ${style.fontFamily} '
                  '${style.fontWeight?.value} ${style.fontSize}',
                ),
                Text(
                  i.isEven ? l10n.appName : l10n.tripBreakButton,
                  style: style.copyWith(color: ColorTokens.ink),
                ),
              ],
            ),
          Text(
            numbers.integer(1240),
            style: TypeTokens.numberL.copyWith(color: ColorTokens.ink),
          ),
          const _Heading('Radii'),
          Wrap(
            spacing: SpaceTokens.s12,
            runSpacing: SpaceTokens.s12,
            children: [
              for (final (name, radius) in _radii)
                _Sample(
                  name: '$name $radius',
                  decoration: BoxDecoration(
                    color: ColorTokens.paper,
                    borderRadius: BorderRadius.circular(radius),
                  ),
                ),
            ],
          ),
          const _Heading('Lips'),
          Wrap(
            spacing: SpaceTokens.s12,
            runSpacing: SpaceTokens.s16,
            children: [
              for (final (name, lip) in _lips)
                _Sample(
                  name: name,
                  decoration: BoxDecoration(
                    color: ColorTokens.paper,
                    borderRadius: BorderRadius.circular(RadiusTokens.m),
                    boxShadow: [lip],
                  ),
                ),
            ],
          ),
          const _Heading('Rings'),
          Wrap(
            spacing: SpaceTokens.s12,
            runSpacing: SpaceTokens.s12,
            children: [
              for (final (name, ring) in _rings)
                _Sample(
                  name: name,
                  decoration: BoxDecoration(
                    color: ColorTokens.paper,
                    borderRadius: BorderRadius.circular(RadiusTokens.m),
                    border: Border.all(
                      color: ring.color,
                      width: ring.width,
                      strokeAlign: ring.inside
                          ? BorderSide.strokeAlignInside
                          : BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
            ],
          ),
          const _Heading('Motion (tap to play)'),
          for (final (name, duration, curve) in _motion)
            _MotionPreview(name: name, duration: duration, curve: curve),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: SpaceTokens.s12),
    child: Text(
      text,
      textDirection: TextDirection.ltr,
      style: TypeTokens.displayS.copyWith(color: ColorTokens.ink),
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    style: TypeTokens.label.copyWith(color: ColorTokens.inkMuted),
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color, super.key});

  final String name;
  final Color color;

  static const double _width = 104;
  static const double _chip = 40;

  String get _hex =>
      '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _width,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SpaceTokens.s2,
      children: [
        Container(
          height: _chip,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(RadiusTokens.s),
            border: Border.all(color: ColorTokens.outline),
          ),
        ),
        Text(
          name,
          textDirection: TextDirection.ltr,
          style: TypeTokens.label.copyWith(color: ColorTokens.ink),
        ),
        _Caption(_hex),
      ],
    ),
  );
}

class _Sample extends StatelessWidget {
  const _Sample({required this.name, required this.decoration});

  final String name;
  final BoxDecoration decoration;

  static const double _size = 64;

  @override
  Widget build(BuildContext context) => Column(
    spacing: SpaceTokens.s8,
    children: [
      Container(width: _size, height: _size, decoration: decoration),
      _Caption(name),
    ],
  );
}

/// A box that slides across its track over [duration] on [curve].
class _MotionPreview extends StatefulWidget {
  const _MotionPreview({
    required this.name,
    required this.duration,
    required this.curve,
  });

  final String name;
  final Duration duration;
  final Curve curve;

  @override
  State<_MotionPreview> createState() => _MotionPreviewState();
}

class _MotionPreviewState extends State<_MotionPreview>
    with SingleTickerProviderStateMixin {
  late final _play = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final _curve = CurvedAnimation(parent: _play, curve: widget.curve);

  static const double _dot = 24;

  @override
  void dispose() {
    _curve.dispose();
    _play.dispose();
    super.dispose();
  }

  void _run() {
    _play
      ..reset()
      ..forward().ignore();
  }

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: _run,
    semanticLabel: widget.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: SpaceTokens.s4,
      children: [
        _Caption('${widget.name} · ${widget.duration.inMilliseconds} ms'),
        Container(
          height: _dot,
          decoration: BoxDecoration(
            color: ColorTokens.track,
            borderRadius: BorderRadius.circular(RadiusTokens.pill),
          ),
          child: AnimatedBuilder(
            animation: _curve,
            builder: (context, _) => Align(
              alignment: Alignment(1 - 2 * _curve.value, 0),
              child: Container(
                width: _dot,
                height: _dot,
                decoration: const BoxDecoration(
                  color: ColorTokens.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
