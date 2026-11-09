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
  voterCard,
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
  'pvc': SpecimenKind.voterCard,
  'voters': SpecimenKind.voterCard,
  'residence-card': SpecimenKind.residencePermit,
  'residence-permit': SpecimenKind.residencePermit,
};

SpecimenKind specimenKind(String? idType) =>
    _kinds[idType] ?? SpecimenKind.generic;

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
      parts.addAll([
        fieldRows(312, 158, _tallFields, step: 72),
        '<circle cx="840" cy="226" r="76" fill="#FFFFFF" fill-opacity="0.6" stroke="$accent" stroke-width="8"/>'
            '<path d="M806 226L830 254L878 198" fill="none" stroke="$accent" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>',
        specimenSignature(320, 392, 1.05),
        specimenBarcode(_inset, 512, _width - _inset * 2, 72),
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

String _cardBack(SpecimenInput i, int height) {
  final band = _cardBand(i);
  const twoRows = <List<(num, num)>>[
    [(130, 400), (100, 300)],
    [(110, 330), (130, 370)],
  ];
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
