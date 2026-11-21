import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'toon_face.dart';

// ─── The cartoon person's colours ─────────────────────────────────────────────
//
// Every colour of the cartoon person (liveness/toon_face.dart) is a shade of
// the workflow's own colour: skin, hair and clothes alike, so the person has
// no skin colour and stands for anyone. The mixes are the web SDK's
// (liveness/toon-shades.ts, CSS `color-mix(in srgb, …)`), worked out here
// because flutter_svg cannot resolve the CSS variables the drawing names.

/// `color-mix(in srgb, [primary] [share], [other])`.
Color _mix(Color primary, double share, Color other) =>
    Color.lerp(other, primary, share)!;

const Color _white = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000);

/// The colour each `--toon-*` variable stands for, from the brand primary.
Map<String, Color> toonShades(Color primary) => {
      'skin': _mix(primary, 0.22, _white),
      'hair': _mix(primary, 0.4, _black),
      'clothes': primary,
      'light': _white,
      'ink': _mix(primary, 0.40, _black),
      'mouth': _mix(primary, 0.45, _black),
      'tongue': _mix(primary, 0.50, _white),
      'line': _mix(primary, 0.30, _black),
    };

/// The room behind a picture of the camera: a soft dusk, leaning to the
/// workflow's colour so the picture sits with it. The web's CAMERA_ROOM, a
/// `linear-gradient(160deg, …)`.
LinearGradient cameraRoom(Color primary) {
  const angle = 160 * math.pi / 180;
  final dx = math.sin(angle);
  final dy = -math.cos(angle);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: [
      _mix(primary, 0.28, const Color(0xFF66708A)),
      _mix(primary, 0.22, const Color(0xFF3B4257)),
    ],
  );
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

final RegExp _variable = RegExp(r'var\(--toon-([a-z]+)\)');
final RegExp _style = RegExp(r'style="([^"]*)"');

// The smiling mouth is cut to its own outline by an ALPHA mask filled with an
// opaque colour, which is a clip in all but name. flutter_svg reads masks by
// luminance, where that dark fill would hide most of the mouth, so the mask is
// written as the clip it is.
final RegExp _mask = RegExp(
  r'<mask id="([^"]+)"[^>]*>(.*?)</mask><g mask="url\(#\1\)">',
);

/// One part of the drawing as a whole SVG document for [SvgPicture.string],
/// in [shades]. Each `style="…"` becomes plain attributes, since flutter_svg
/// does not take every declaration from a style.
String toonPartSvg(String part, Map<String, Color> shades) {
  var markup = kToonParts[part]!;
  markup = markup.replaceAllMapped(
    _mask,
    (m) => '<clipPath id="${m[1]}">${m[2]}</clipPath>'
        '<g clip-path="url(#${m[1]})">',
  );
  markup = markup.replaceAllMapped(_style, (m) {
    final attributes = <String>[];
    for (final declaration in m[1]!.split(';')) {
      final colon = declaration.indexOf(':');
      if (colon < 0) continue;
      final name = declaration.substring(0, colon).trim();
      final value = declaration.substring(colon + 1).trim();
      if (name == 'mask-type') continue;
      attributes.add('$name="$value"');
    }
    return attributes.join(' ');
  });
  markup = markup.replaceAllMapped(_variable, (m) {
    final colour = shades[m[1]];
    if (colour == null) {
      throw ArgumentError('No shade for --toon-${m[1]}');
    }
    return _hex(colour);
  });
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="$kToonViewBox">'
      '$markup</svg>';
}
