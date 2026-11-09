// The drawing kit for the document specimens (document_specimen.dart). Pure:
// every function returns SVG text, so a specimen can be tested and rendered
// anywhere. The Flutter mirror of the React Native SDK's
// lib/documentSpecimenParts.ts: change a drawing in one and change it in both.

const String specimenInk = '#12141F';
const String _muted = '#6B7083';
const String _bar = '#9A9EAD';
const String _panel = '#E4E6EE';

/// Text for the drawing. flutter_svg reads real XML, so these must be escaped
/// (the React Native parser is the opposite: it decodes nothing).
String printable(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// The size that fits [text] in [maxWidth], estimated from the widest case:
/// capitals in a bold face at about 0.68 of the size, plus the tracking. It only
/// ever shrinks.
double fitSize(String text, double maxWidth, double size,
    {double tracking = 0, double min = 24}) {
  final needed = text.length * (size * 0.68 + tracking);
  if (needed <= maxWidth) return size;
  final fitted = ((size * maxWidth) / needed).floorToDouble();
  return fitted < min ? min : fitted;
}

String specimenLabel(
  String text,
  num x,
  num y,
  num size, {
  required String font,
  String color = specimenInk,
  String anchor = 'start',
  num tracking = 0,
  int weight = 700,
}) =>
    '<text x="$x" y="$y" font-family="$font" font-size="$size" '
    'font-weight="$weight" letter-spacing="$tracking" text-anchor="$anchor" '
    'fill="$color">${printable(text)}</text>';

/// A printed field: a pale caption over a darker value.
String _field(num x, num y, num caption, num value) =>
    '<rect x="$x" y="$y" width="$caption" height="9" rx="4.5" fill="$_bar" opacity="0.55"/>'
    '<rect x="$x" y="${y + 19}" width="$value" height="14" rx="7" fill="$_muted"/>';

/// Rows of fields, as a document prints them. Each pair is (caption, value).
String fieldRows(num x, num y, List<List<(num, num)>> rows,
    {num step = 66, num gap = 34}) {
  final out = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    var left = x;
    for (final (caption, value) in rows[r]) {
      out.write(_field(left, y + r * step, caption, value));
      left += (caption > value ? caption : value) + gap;
    }
  }
  return out.toString();
}

/// The holder: a drawn person, never a real face. Designed in a 200 x 240 box.
String specimenPortrait(num x, num y, num w, num h, String accent, String id) {
  final scale = w / 200 > h / 240 ? w / 200 : h / 240;
  final ox = x + (w - 200 * scale) / 2;
  final oy = y + h - 240 * scale;
  const line =
      'stroke="$specimenInk" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"';
  return '''
<clipPath id="$id"><rect x="$x" y="$y" width="$w" height="$h" rx="18"/></clipPath>
<rect x="$x" y="$y" width="$w" height="$h" rx="18" fill="$_panel"/>
<g clip-path="url(#$id)"><g transform="translate($ox $oy) scale($scale)">
<path d="M6 244C10 196 52 176 100 176C148 176 190 196 194 244Z" fill="#FFFFFF" $line/>
<path d="M80 148V176C88 194 112 194 120 176V148" fill="#FFFFFF" $line/>
<ellipse cx="51" cy="104" rx="9" ry="14" fill="#FFFFFF" $line/><ellipse cx="149" cy="104" rx="9" ry="14" fill="#FFFFFF" $line/>
<path d="M54 92C54 150 76 166 100 166C124 166 146 150 146 92C146 62 124 48 100 48C76 48 54 62 54 92Z" fill="#FFFFFF" $line/>
<path d="M50 100C42 52 72 24 108 24C138 24 160 50 150 100C146 84 138 74 126 66C106 76 84 76 70 68C60 76 54 86 50 100Z" fill="$specimenInk"/>
<circle cx="82" cy="106" r="4.5" fill="$specimenInk"/><circle cx="118" cy="106" r="4.5" fill="$specimenInk"/>
<path d="M100 114C97 122 96 126 96 128C98 130 102 130 104 129" fill="none" $line/><path d="M86 143C94 151 106 151 114 143" fill="none" $line/>
</g></g>
<rect x="$x" y="$y" width="$w" height="$h" rx="18" fill="none" stroke="$accent" stroke-width="8"/>''';
}

/// A signature, drawn so it needs no script font on the device.
String specimenSignature(num x, num y, [num scale = 1]) =>
    '<path transform="translate($x $y) scale($scale)" d="M4 44C18 8 36 0 34 18C32 36 14 62 24 62C36 62 44 34 56 34C62 34 56 52 64 52C72 52 76 34 84 34C92 34 84 52 92 52C102 52 108 30 118 32C128 34 116 54 128 52C142 50 150 28 164 30C176 32 158 56 174 52C190 48 214 34 238 36" fill="none" stroke="$specimenInk" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"/>';

/// A gold contact chip, the mark of a chipped card.
String specimenChip(num x, num y) {
  const w = 104;
  const h = 80;
  return '<rect x="$x" y="$y" width="$w" height="$h" rx="14" fill="#E9C46A" stroke="$specimenInk" stroke-width="4"/>'
      '<path d="M${x + 34} ${y}V${y + h}M${x + 70} ${y}V${y + h}M$x ${y + 27}H${x + 34}M${x + 70} ${y + 27}H${x + w}M$x ${y + 53}H${x + 34}M${x + 70} ${y + 53}H${x + w}" fill="none" stroke="$specimenInk" stroke-width="3"/>';
}

/// The e-passport mark, the symbol ICAO has every chipped passport carry: a
/// frame with a circle at its centre and a line either side.
String specimenChipMark(num cx, num cy, num height, String color) {
  final width = height * 1.5;
  final left = cx - width / 2;
  final top = cy - height / 2;
  final ring = height * 0.25;
  final line = 'fill="none" stroke="$color" stroke-width="${height * 0.1}"';
  return '<rect x="$left" y="$top" width="$width" height="$height" rx="${height * 0.14}" $line/>'
      '<circle cx="$cx" cy="$cy" r="$ring" $line/>'
      '<path d="M$left ${cy}H${cx - ring}M${cx + ring} ${cy}H${left + width}" $line/>';
}

/// A linear barcode. The widths repeat a fixed pattern, so it encodes nothing.
String specimenBarcode(num x, num y, num width, num height) {
  const pattern = [3, 1, 2, 1, 4, 2, 1, 3, 1, 1, 2, 3, 1, 2, 4, 1, 1, 3];
  final bars = StringBuffer();
  var left = x;
  for (var i = 0; left < x + width; i++) {
    final w = pattern[i % pattern.length] * 4;
    final room = x + width - left;
    if (i.isEven) {
      bars.write(
          '<rect x="$left" y="$y" width="${w < room ? w : room}" height="$height" fill="$specimenInk"/>');
    }
    left += w;
  }
  return bars.toString();
}

/// A two-dimensional barcode block, the kind on the back of a licence.
String specimenStackedBarcode(num x, num y, num width, num height) {
  const rows = 9;
  final rowH = height / rows;
  final out = StringBuffer();
  for (var r = 0; r < rows; r++) {
    var left = x;
    for (var i = 0; left < x + width; i++) {
      final w = 5 + (((i + 1) * (r + 3) * 7) % 4) * 5;
      final room = x + width - left;
      if ((i + r).isEven) {
        out.write(
            '<rect x="$left" y="${y + r * rowH}" width="${w < room ? w : room}" height="${rowH - 2}" fill="$specimenInk"/>');
      }
      left += w;
    }
  }
  return out.toString();
}

/// The machine-readable zone, filled with SPECIMEN so it reads as a sample.
///
/// Every character gets its own cell across [width], as the real zone is
/// printed, so the lines fit exactly whatever the device's monospace font
/// measures. The filler `<` is drawn rather than typed, for the same reason.
String specimenMrz(num x, num y, List<String> lines, num width, num size,
    num step, String font) {
  final longest = lines.map((l) => l.length).reduce((a, b) => a > b ? a : b);
  final cell = width / longest;
  final reach = size * 0.2;
  final rise = size * 0.26;
  final out = StringBuffer();
  for (var row = 0; row < lines.length; row++) {
    final baseline = y + row * step;
    final middle = baseline - size * 0.36;
    final filler = StringBuffer();
    for (var column = 0; column < lines[row].length; column++) {
      final character = lines[row][column];
      final centre = x + cell * (column + 0.5);
      if (character == '<') {
        filler.write(
            'M${centre + reach} ${middle - rise}L${centre - reach} ${middle}L${centre + reach} ${middle + rise}');
      } else {
        out.write(specimenLabel(character, centre, baseline, size,
            font: font, anchor: 'middle'));
      }
    }
    if (filler.isNotEmpty) {
      out.write(
          '<path d="$filler" fill="none" stroke="$specimenInk" stroke-width="${size * 0.1}" stroke-linecap="round" stroke-linejoin="round"/>');
    }
  }
  return out.toString();
}
