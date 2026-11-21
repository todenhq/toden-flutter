import 'document_specimen_parts.dart';

// The sample document shown in the capture guide when the camera opens, so the
// person sees what to hold up and which way round: a passport looks like a
// passport with PASSPORT written on it, a licence like a licence. Pure: it
// returns SVG text, which the viewfinder draws and a test can read.
//
// It carries the ID's own name and the country, and SPECIMEN wherever a real
// document would print a person, so nobody could take it for a real one.
//
// The Flutter mirror of the React Native SDK's lib/documentSpecimen.ts: change a
// layout in one and change it in both.

enum SpecimenKind {
  passport,
  nationalId,
  ninSlip,
  driversLicense,

  /// Nigeria's driver's licence: a licence on the front, and a back of its own.
  driversLicenseNg,
  voterCard,

  /// Nigeria's voter card: a voter card on the front, and a back of its own.
  pvc,
  residencePermit,
  generic,
}

const Map<String, SpecimenKind> _kinds = {
  'passport': SpecimenKind.passport,
  'drivers-license': SpecimenKind.driversLicense,
  'national-id': SpecimenKind.nationalId,
  'nin': SpecimenKind.nationalId,
  'vnin': SpecimenKind.nationalId,
  'nin-slip': SpecimenKind.ninSlip,
  'ghana-card': SpecimenKind.nationalId,
  'cni': SpecimenKind.nationalId,
  'pvc': SpecimenKind.pvc,
  'voters': SpecimenKind.voterCard,
  'residence-card': SpecimenKind.residencePermit,
  'residence-permit': SpecimenKind.residencePermit,
};

/// The drawing for an ID. A few are drawn as one country's own card, measured
/// off real ones: [country] is the document's ISO-2 code, and without it (or for
/// any other country) the ID's general drawing is used.
SpecimenKind specimenKind(String? idType, [String? country]) {
  final kind = _kinds[idType] ?? SpecimenKind.generic;
  return kind == SpecimenKind.driversLicense && country?.toUpperCase() == 'NG'
      ? SpecimenKind.driversLicenseNg
      : kind;
}

/// The name written across the sample. The step's own label when it has a real
/// one; "Document" says nothing on a document, so that falls back to the ID's
/// key.
String specimenTitle(String? idType, String label) {
  if (idType == 'passport') return 'Passport';
  if (label.isNotEmpty && label != 'Document') return label;
  if (idType == null) return 'Document';
  return idType
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .trim()
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

enum SpecimenSide { front, back }

class SpecimenInput {
  final SpecimenKind kind;
  final String title;

  /// The country's name. Left off when unknown.
  final String? country;
  final SpecimenSide side;

  /// Width over height, the guide's own.
  final double aspect;
  final String accent;

  /// Font families the device has.
  final String sans;
  final String mono;

  const SpecimenInput({
    required this.kind,
    required this.title,
    required this.country,
    required this.side,
    required this.aspect,
    required this.accent,
    required this.sans,
    required this.mono,
  });
}

const int _width = 1000;
const int _inset = 44;

String _shell(int height, String body) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $_width $height">
${_card(height, body)}
</svg>''';

String _card(int height, String body) => '''
<rect x="6" y="6" width="${_width - 12}" height="${height - 12}" rx="40" fill="#FFFFFF" fill-opacity="0.8"/>
$body
<rect x="6" y="6" width="${_width - 12}" height="${height - 12}" rx="40" fill="none" stroke="$specimenInk" stroke-width="10"/>''';

/// The landscape drawing turned a quarter clockwise, for an upright guide (a
/// NIN slip on a phone held upright, config/document_turn.dart): its top edge
/// faces the RIGHT of the screen, the direction the text reader tries first.
/// The view box is the landscape one with its sides swapped, so the drawing
/// fills the upright guide exactly.
String _turnedShell(int height, String body) => '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $height $_width">
<g transform="translate($height 0) rotate(90)">
${_card(height, body)}
</g>
</svg>''';

/// The faint security pattern behind the printing.
String _guilloche(num cx, num cy, String accent) => [150, 210, 270, 330, 390]
    .map((r) =>
        '<circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="$accent" stroke-width="3" stroke-opacity="0.14"/>')
    .join();

/// A crest: the shape every issuer prints, in no country's design.
String _crest(num cx, num cy, num r, String accent) =>
    '<circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="$accent" stroke-width="5"/>'
    '<circle cx="$cx" cy="$cy" r="${r * 0.55}" fill="$accent"/>';

/// A title that fits at a readable size, without its bracket if that is what it
/// takes.
(String, double) _printedTitle(
    String title, double maxWidth, double size, double tracking) {
  final full = title.toUpperCase();
  final short = full.replaceFirst(RegExp(r'\s*\(.*\)\s*$'), '');
  final fullSize = fitSize(full, maxWidth, size, tracking: tracking);
  return fullSize >= size * 0.8 || short == full
      ? (full, fullSize)
      : (short, fitSize(short, maxWidth, size, tracking: tracking));
}

String _passport(SpecimenInput i, int height) {
  final country = (i.country ?? 'COUNTRY').toUpperCase();
  final (name, nameSize) = _printedTitle(i.title, 380, 38, 3);
  const lineChars = 44;
  final first = 'P<<<SPECIMEN<<SAMPLE'.padRight(lineChars, '<');
  final second = '000000000<0<<<0000000<0000000'.padRight(lineChars, '<');
  return [
    _guilloche(760, 300, i.accent),
    specimenLabel(country, _inset, 90, fitSize(country, 400, 48, tracking: 4),
        font: i.sans, weight: 800, tracking: 4),
    specimenChipMark(510, 74, 56, specimenInk),
    specimenLabel(name, _width - _inset, 88, nameSize,
        font: i.sans, weight: 800, tracking: 3, anchor: 'end'),
    specimenPortrait(_inset, 124, 232, 366, i.accent, 'pp'),
    fieldRows(316, 136, const [
      [(130, 330), (100, 250)],
      [(100, 390), (80, 190)],
      [(160, 300), (110, 280)],
      [(120, 370), (90, 200)],
    ], step: 68),
    specimenSignature(320, 412, 1.05),
    specimenMrz(_inset, height - 86, [first, second], _width - _inset * 2, 31,
        50, i.mono),
  ].join();
}

/// The coloured band across the top of a card, with its two names.
String _cardBand(SpecimenInput i) {
  final country = (i.country ?? 'COUNTRY').toUpperCase();
  final (name, nameSize) = _printedTitle(i.title, 520, 38, 2);
  return '<path d="M6 46A40 40 0 0 1 46 6H954A40 40 0 0 1 994 46V116H6Z" fill="${i.accent}"/>'
      '${specimenLabel(country, _inset, 78, fitSize(country, 340, 40, tracking: 3), font: i.sans, weight: 800, tracking: 3, color: '#FFFFFF')}'
      '${specimenLabel(name, _width - _inset, 76, nameSize, font: i.sans, weight: 800, tracking: 2, anchor: 'end', color: '#FFFFFF')}';
}

const List<List<(num, num)>> _tallFields = [
  [(120, 330)],
  [(100, 400)],
  [(140, 280)],
];

const List<List<(num, num)>> _wideRow = [
  [(150, 340), (120, 260), (90, 220)],
];

String _cardFront(SpecimenInput i) {
  final accent = i.accent;
  final parts = [
    _guilloche(780, 420, accent),
    _cardBand(i),
    specimenPortrait(_inset, 146, 232, 340, accent, 'cd'),
  ];
  switch (i.kind) {
    case SpecimenKind.driversLicense:
    case SpecimenKind.driversLicenseNg:
      parts.addAll([
        fieldRows(312, 158, _tallFields, step: 72),
        fieldRows(756, 158, const [
          [(80, 190)],
          [(70, 150)],
        ], step: 72),
        for (final (n, c) in const [(0, 'A'), (1, 'B'), (2, 'C')])
          '<rect x="${312 + n * 84}" y="396" width="68" height="68" rx="12" fill="none" stroke="$specimenInk" stroke-width="5"/>'
              '${specimenLabel(c, 346 + n * 84, 445, 40, font: i.sans, anchor: 'middle', weight: 800)}',
        specimenSignature(590, 400, 1.05),
        fieldRows(_inset, 520, _wideRow),
      ]);
    case SpecimenKind.voterCard:
    case SpecimenKind.pvc:
      parts.addAll([
        fieldRows(312, 158, _tallFields, step: 72),
        '<circle cx="840" cy="226" r="76" fill="#FFFFFF" fill-opacity="0.6" stroke="$accent" stroke-width="8"/>'
            '<path d="M806 226L830 254L878 198" fill="none" stroke="$accent" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>',
        specimenSignature(320, 392, 1.05),
        // A PVC's front carries no barcode: both of its barcodes are on the back.
        i.kind == SpecimenKind.pvc
            ? fieldRows(_inset, 520, _wideRow)
            : specimenBarcode(_inset, 512, _width - _inset * 2, 72),
      ]);
    case SpecimenKind.residencePermit:
      parts.addAll([
        fieldRows(312, 158, _tallFields, step: 72),
        _crest(880, 214, 56, accent),
        specimenSignature(320, 392, 1.05),
        '<rect x="$_inset" y="508" width="${_width - _inset * 2}" height="76" rx="14" fill="$accent" fill-opacity="0.12"/>',
        fieldRows(_inset + 26, 524, const [
          [(120, 240), (120, 240), (100, 200)],
        ], gap: 40),
      ]);
    default:
      parts.addAll([
        fieldRows(312, 158, _tallFields, step: 72),
        i.kind == SpecimenKind.nationalId
            ? specimenChip(826, 150)
            : _crest(880, 214, 56, accent),
        specimenSignature(320, 392, 1.05),
        fieldRows(_inset, 520, _wideRow),
      ]);
  }
  return parts.join();
}

/// The back of Nigeria's Permanent Voter's Card, laid out as the card is
/// (measured off real backs: both barcodes sat in the top half of all twelve).
/// The linear barcode comes first, the two-dimensional block directly under it,
/// both starting further in from the left edge than they stop short of the
/// right. Then the security strip across the card, and the print at the foot:
/// two centred lines, the emblem with the batch and serial numbers, the notice.
String _pvcBack(SpecimenInput i, int height) {
  final accent = i.accent;
  const codeX = 160;
  const codeWidth = _width - codeX - 76;
  const stripTop = 348;
  final stripHeight = height - 199 - stripTop < 40 ? 40 : height - 199 - stripTop;
  final strip = StringBuffer();
  for (var x = 40; x < _width - 60; x += 62) {
    strip.write(
        'M$x ${stripTop + stripHeight * 0.42}l30 -11M${x + 31} ${stripTop + stripHeight * 0.8}l30 -11');
  }
  final row = height - 96;
  return [
    _cardBand(i),
    specimenBarcode(codeX, 140, codeWidth, 84),
    specimenStackedBarcode(codeX, 240, codeWidth, 90),
    '<rect x="11" y="$stripTop" width="${_width - 22}" height="$stripHeight" fill="$accent" fill-opacity="0.1"/>',
    '<path d="$strip" fill="none" stroke="$accent" stroke-opacity="0.4" stroke-width="5" stroke-linecap="round"/>',
    '<rect x="${_inset + 20}" y="${height - 181}" width="${_width - (_inset + 20) * 2}" height="3" fill="$specimenInk" fill-opacity="0.3"/>',
    specimenPrintLine(280, height - 165, 440),
    specimenPrintLine(365, height - 135, 270, height: 12),
    _crest(_inset + 62, row + 6, 30, accent),
    specimenPrintLine(190, row + 2, 80, height: 10, pale: true),
    specimenPrintLine(284, row, 190),
    '<rect x="518" y="${row - 6}" width="4" height="26" rx="2" fill="$specimenInk" fill-opacity="0.3"/>',
    specimenPrintLine(560, row + 2, 120, height: 10, pale: true),
    specimenPrintLine(_width - _inset - 150, row, 150),
    specimenPrintLine(180, height - 52, 640, height: 10, pale: true),
  ].join();
}

/// The back of Nigeria's driver's licence (measured off real backs): a short linear barcode at the top right with its number beside it,
/// the large two-dimensional block directly under it across the card, both in
/// the top half. Below them the class of licence, then the notes at the foot
/// with the crest at their right.
String _licenceBack(SpecimenInput i, int height) {
  final notes = height - 123;
  final classes = height - 229;
  return [
    _cardBand(i),
    specimenPrintLine(190, 152, 190, height: 10, pale: true),
    specimenBarcode(470, 136, _width - _inset - 470, 44),
    specimenStackedBarcode(
        _inset, 188, _width - _inset * 2, height - 281 - 188),
    specimenPrintLine(_inset, classes, 800, height: 12),
    specimenPrintLine(_inset, classes + 26, 690, height: 12),
    specimenPrintLine(_inset, classes + 52, 330, height: 12),
    for (final (n, width) in const [(0, 720), (1, 640), (2, 700), (3, 660)])
      specimenPrintLine(_inset, notes + n * 24, width, height: 10, pale: true),
    _crest(_width - _inset - 60, height - 88, 46, i.accent),
  ].join();
}

String _cardBack(SpecimenInput i, int height) {
  if (i.kind == SpecimenKind.pvc) return _pvcBack(i, height);
  if (i.kind == SpecimenKind.driversLicenseNg) return _licenceBack(i, height);
  final band = _cardBand(i);
  const twoRows = <List<(num, num)>>[
    [(130, 400), (100, 300)],
    [(110, 330), (130, 370)],
  ];
  // Any other country's licence: its fields, then one large barcode block. Not
  // measured off a real card, so it claims no one country's layout.
  if (i.kind == SpecimenKind.driversLicense) {
    return band +
        fieldRows(_inset, 148, twoRows, step: 70) +
        specimenStackedBarcode(
            _inset, 300, _width - _inset * 2, height - 346);
  }
  if (i.kind == SpecimenKind.voterCard || i.kind == SpecimenKind.generic) {
    return band +
        fieldRows(_inset, 152, const [
          [(130, 420), (90, 280)],
          [(100, 340), (120, 360)],
          [(150, 300), (90, 300)],
        ], step: 72) +
        specimenBarcode(_inset, height - 216, _width - _inset * 2, 170);
  }
  const lines = [
    'I<<<000000000<0<<<<<<<<<<<<<<<',
    '0000000<0000000<<<<<<<<<<<<<<0',
    'SPECIMEN<<SAMPLE<<<<<<<<<<<<<<',
  ];
  return [
    band,
    fieldRows(_inset, 150, twoRows, step: 70),
    '<rect x="24" y="${height - 298}" width="952" height="274" rx="20" fill="$specimenInk" fill-opacity="0.05"/>',
    specimenMrz(
        _inset, height - 216, lines, _width - _inset * 2, 48, 80, i.mono),
  ].join();
}

/// The long NIN slip (2.07 to 1, measured off real slips): two headings across
/// the top, the name fields down the left, the address and the NIN on the
/// right. No photo and no chip, as on the paper slip. One side only.
String _ninSlip(SpecimenInput i, int height) {
  final country = (i.country ?? 'COUNTRY').toUpperCase();
  final (name, nameSize) = _printedTitle(i.title, 600, 36, 2);
  return [
    _guilloche(500, height / 2 + 40, i.accent),
    _crest(_inset + 46, 92, 38, i.accent),
    _crest(_width - _inset - 46, 92, 38, i.accent),
    specimenLabel(country, _width / 2, 82, fitSize(country, 600, 30, tracking: 3),
        font: i.sans, weight: 800, tracking: 3, anchor: 'middle'),
    specimenLabel(name, _width / 2, 126, nameSize,
        font: i.sans, weight: 800, tracking: 2, anchor: 'middle', color: i.accent),
    '<rect x="$_inset" y="152" width="${_width - _inset * 2}" height="4" rx="2" fill="$specimenInk" fill-opacity="0.18"/>',
    fieldRows(_inset, 186, const [
      [(120, 300)],
      [(100, 260)],
      [(130, 300)],
      [(110, 240)],
    ], step: 64),
    fieldRows(540, 186, const [
      [(110, 400)],
      [(0, 320)],
    ], step: 40),
    '<rect x="530" y="${height - 150}" width="${_width - _inset - 530}" height="100" rx="18" fill="${i.accent}" fill-opacity="0.1"/>',
    specimenLabel('NIN', 556, height - 112, 26,
        font: i.sans, weight: 800, tracking: 2, color: i.accent),
    specimenLabel('00000000000', 556, height - 68, 46,
        font: i.mono, weight: 700, tracking: 4),
  ].join();
}

/// Viewbox height for the guide's aspect, so the sample fills it exactly.
int specimenHeight(double aspect) => (_width / aspect).round();

String documentSpecimen(SpecimenInput input) {
  // An upright guide (width under height) shows the document turned: it is
  // drawn landscape at the document's own shape, then turned to fit.
  final turned = input.aspect < 1;
  final height = specimenHeight(turned ? 1 / input.aspect : input.aspect);
  final body = input.kind == SpecimenKind.passport
      ? _passport(input, height)
      : input.kind == SpecimenKind.ninSlip
      ? _ninSlip(input, height)
      : input.side == SpecimenSide.back
          ? _cardBack(input, height)
          : _cardFront(input);
  return turned ? _turnedShell(height, body) : _shell(height, body);
}
