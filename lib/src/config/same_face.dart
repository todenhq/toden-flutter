// Is the camera still looking at the side it just photographed?
//
// The back of a card carries little branding and the gate relaxes for it, so
// auto-capture cannot tell the two faces apart by what an ID should say. It can
// compare: the faces say different things, so a "back" whose words are mostly the
// front's is the front, still held up. Mirrors sameFace.ts in the React Native
// SDK; keep the two identical.

/// Below this a front has too little text to recognise again.
const int _minFrontWords = 6;

/// Share of the front's words seen again before it counts as the same face.
const double _sameFaceShare = 0.55;

Set<String> wordsOf(List<String> lines) {
  final words = <String>{};
  for (final line in lines) {
    for (final word in line.toUpperCase().split(RegExp('[^A-Z0-9]+'))) {
      if (word.length >= 3) words.add(word);
    }
  }
  return words;
}

bool stillSameFace(Set<String>? front, List<String> lines) {
  if (front == null || front.length < _minFrontWords) return false;
  final seen = wordsOf(lines);
  final shared = front.where(seen.contains).length;
  return shared / front.length >= _sameFaceShare;
}
