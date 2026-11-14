// What the chip step says BEFORE the read starts: what is about to happen and
// how to hold the document. Most people have never had a phone read a passport
// and do not know the chip is in the cover, so the read waits for them to say
// they are ready. The same wording lives in the web SDK (lib/nfc-intro.ts) and
// React Native (lib/nfcIntro.ts); keep the three in step.

enum NfcIntroPlatform { ios, android, other }

/// Passports keep the chip in a cover; cards keep it inside the card.
bool isPassportId(String? idKey) =>
    idKey != null && idKey.toLowerCase().contains('passport');

/// Which glyph a row shows; the view maps these to icons.
enum NfcIntroIcon { camera, passport, card, phone, hold }

class NfcIntroRow {
  const NfcIntroRow(this.icon, this.title, this.caption, {this.done = false});

  final NfcIntroIcon icon;
  final String title;
  final String caption;

  /// Already done (the photo page, read during document capture): a check.
  final bool done;
}

/// The screen, in the shape of the address-monitoring explanation (the same
/// hero, grouped rows and highlighted "before you start" card).
class NfcIntroCopy {
  const NfcIntroCopy({
    required this.title,
    required this.description,
    required this.rows,
    required this.beforeLead,
    required this.beforeTap,
  });

  final String title;
  final String description;
  final List<NfcIntroRow> rows;

  /// The highlighted card under the rows: a small lead, then the action.
  final String beforeLead;
  final String beforeTap;
}

/// Where the phone's reader is: the top edge on an iPhone, mid-back on Android.
String _restCaption(NfcIntroPlatform platform) => switch (platform) {
      NfcIntroPlatform.ios => 'Rest the top of your iPhone on it.',
      NfcIntroPlatform.android =>
        'Rest the middle of the back of your phone on it.',
      NfcIntroPlatform.other => 'Rest the back of your phone on it.',
    };

/// The intro for this document and phone. The photo page leads either way:
/// done, with a check, when document capture already read the code that
/// unlocks the chip (the usual case), or still to do when it did not
/// ([needsCode]), so the camera opening next is no surprise.
NfcIntroCopy nfcIntroCopy({
  required bool passport,
  required NfcIntroPlatform platform,
  required bool needsCode,
}) {
  final doc = passport ? 'passport' : 'card';
  return NfcIntroCopy(
    title: 'Your $doc has a chip',
    description:
        'Your phone can read it to confirm your $doc is genuine. Here is how.',
    rows: [
      if (needsCode)
        const NfcIntroRow(NfcIntroIcon.camera, 'Scan the photo page',
            'Its printed code unlocks the chip.')
      else
        const NfcIntroRow(NfcIntroIcon.camera, 'Photo page scanned',
            'Its printed code unlocks the chip.',
            done: true),
      if (passport)
        const NfcIntroRow(NfcIntroIcon.passport, 'Close your passport',
            'Lay it on a flat surface.')
      else
        const NfcIntroRow(NfcIntroIcon.card, 'Lay your card flat',
            'On a table or another flat surface.'),
      NfcIntroRow(
        NfcIntroIcon.phone,
        passport
            ? 'Place your phone on the front cover'
            : 'Place your phone on the card',
        _restCaption(platform),
      ),
      NfcIntroRow(
        NfcIntroIcon.hold,
        'Hold still for a few seconds',
        passport
            ? 'If nothing happens, try the back cover.'
            : 'Keep both still until the read finishes.',
      ),
    ],
    beforeLead: 'Before you start',
    beforeTap: 'Take off a thick phone case',
  );
}
