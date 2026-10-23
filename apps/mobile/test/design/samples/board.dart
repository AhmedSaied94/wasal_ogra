import 'package:material_ui/material_ui.dart';
import 'package:wassal/core/l10n/digit_style.dart';
import 'package:wassal/core/theme/tokens/design_tokens.dart';

import '../boxes.dart';

// Draws measured boxes as plain shapes and text, for the parts of a design
// board that are documentation rather than components: headings, notes,
// section grounds, and the Tokens board's swatches. Every colour named
// after a token is the app's token, so a golden shows the app's palette in
// the board's places.

/// The board's text in [digits]: the design writes Arabic-Indic digits.
String inDigits(String text, DigitStyle digits) {
  if (digits == DigitStyle.arabicIndic) return text;
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune == 0x066B) {
      out.write('.');
    } else if (rune == 0x066C) {
      out.write(',');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Western digits written as the design writes them, for samples whose
/// numbers are in the source: `ar('1,240')` is «١٬٢٤٠».
String ar(String western, DigitStyle digits) {
  if (digits == DigitStyle.western) return western;
  final out = StringBuffer();
  for (final rune in western.runes) {
    if (rune >= 0x30 && rune <= 0x39) {
      out.writeCharCode(0x0660 + rune - 0x30);
    } else if (rune == 0x2C) {
      out.writeCharCode(0x066C);
    } else if (rune == 0x2E) {
      out.writeCharCode(0x066B);
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// A box's colour: the token it names when the app has one, else its hex.
Color boxColor(String spec) {
  final space = spec.indexOf(' ');
  final hex = space < 0 ? spec : spec.substring(0, space);
  final name = space < 0 ? null : spec.substring(space + 1).trim();
  final token = name == null ? null : _token(name);
  if (token != null) return token;
  return _hex(hex);
}

Color? _token(String name) {
  final station = RegExp(r'^station\[(\d)\]$').firstMatch(name);
  if (station != null) return StationColors.all[int.parse(station[1]!)].bg;
  final skin = RegExp(r'^character\.skin\[(\d)\]$').firstMatch(name);
  if (skin != null) return ColorTokens.characterSkin[int.parse(skin[1]!)];
  final note = RegExp(r'^money_note\.(\w+)\.(bg|lip|text)$').firstMatch(name);
  if (note != null) {
    final part = note[2] == 'bg' ? '' : _cap(note[2]!);
    return ColorTokens.named['note${_cap(note[1]!)}$part'];
  }
  final denomination = RegExp(r'^denomination\.(\d+)$').firstMatch(name);
  if (denomination != null) {
    return ColorTokens.named['denom${denomination[1]}'];
  }
  final parts = name.split('.');
  return ColorTokens.named[parts.first + parts.skip(1).map(_cap).join()];
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

Color _hex(String spec) {
  final at = spec.indexOf('@');
  final hex = (at < 0 ? spec : spec.substring(0, at)).replaceFirst('#', '');
  final color = Color(0xFF000000 | int.parse(hex, radix: 16));
  if (at < 0) return color;
  return color.withValues(alpha: double.parse(spec.substring(at + 1)));
}

/// A colour inside a shadow or border: `#RRGGBB[@alpha]`, the app's token
/// when one has that value.
Color _valueColor(String spec) {
  final at = spec.indexOf('@');
  final opaque = _hex(at < 0 ? spec : spec.substring(0, at));
  final token = ColorTokens.named.values.where((c) => c == opaque).firstOrNull;
  final base = token ?? opaque;
  if (at < 0) return base;
  return base.withValues(alpha: double.parse(spec.substring(at + 1)));
}

BorderRadius? _radius(DesignBox b) {
  final spec = b.radius;
  if (spec == null) return null;
  final values = [
    for (final v in spec.split(' '))
      v.endsWith('%')
          ? b.w * double.parse(v.replaceAll('%', '')) / 100
          : double.parse(v.replaceAll('px', '')),
  ];
  if (values.length == 1) return BorderRadius.circular(values.single);
  return BorderRadius.only(
    topLeft: Radius.circular(values[0]),
    topRight: Radius.circular(values[1]),
    bottomRight: Radius.circular(values[2]),
    bottomLeft: Radius.circular(values[3]),
  );
}

({List<BoxShadow> lips, Border? ring}) _shadow(String? spec) {
  if (spec == null) return (lips: const [], ring: null);
  final lips = <BoxShadow>[];
  Border? ring;
  for (final part in spec.split(',').map((p) => p.trim())) {
    final inset = part.startsWith('inset ');
    final v = (inset ? part.substring(6) : part).split(' ');
    final color = _valueColor(v[4]);
    if (inset) {
      ring = Border.all(
        color: color,
        width: double.parse(v[3]),
        strokeAlign: BorderSide.strokeAlignInside,
      );
    } else {
      lips.add(
        BoxShadow(
          offset: Offset(double.parse(v[0]), double.parse(v[1])),
          blurRadius: double.parse(v[2]),
          color: color,
        ),
      );
    }
  }
  return (lips: lips, ring: ring);
}

Border? _border(String? spec) {
  if (spec == null) return null;
  final v = spec.split(' ');
  return Border.all(
    color: _valueColor(v[2]),
    width: double.parse(v[0].replaceAll('px', '')),
  );
}

/// A box's own text style, from its measured font and colour.
TextStyle boxTextStyle(DesignBox b) {
  final font = RegExp(r'^(.+) (\d+) ([\d.]+)px$')
      .firstMatch(b.font ?? 'Readex Pro 400 12px')!;
  final family = font[1] == 'Marhey' ? TypeTokens.marhey : TypeTokens.readexPro;
  final weight = int.parse(font[2]!);
  final size = double.parse(font[3]!);
  final line = b.lineHeight;
  return TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
    height: line == null || line == 'normal'
        ? null
        : double.parse(line.replaceAll('px', '')) / size,
    leadingDistribution: TextLeadingDistribution.even,
    color: b.color == null ? ColorTokens.ink : boxColor(b.color!),
    decoration: TextDecoration.none,
  );
}

/// [b] drawn where the board puts it: its fill, corners, lip and ring, and
/// its text in [style] (its own measured style by default).
Widget boardBox(DesignBox b, DigitStyle digits, {TextStyle? style}) {
  final (:lips, :ring) = _shadow(b.shadow);
  final text = b.text;
  final rtl = text != null && RegExp('[\u0600-\u06FF]').hasMatch(text);
  final textStyle = style ?? boxTextStyle(b);
  final singleLine = b.h < (textStyle.fontSize ?? 12) * 2;
  return Positioned(
    left: b.x,
    top: b.y,
    width: b.w,
    height: b.h,
    child: Container(
      alignment: b.bg != null
          ? Alignment.center
          : rtl
          ? Alignment.centerRight
          : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: b.bg == null ? null : boxColor(b.bg!),
        borderRadius: _radius(b),
        boxShadow: lips,
        border: ring ?? _border(b.border),
      ),
      child: text == null || b.role != 'text'
          ? null
          : Text(
              inDigits(text, digits),
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              softWrap: !singleLine,
              overflow: TextOverflow.visible,
              style: textStyle,
            ),
    ),
  );
}
