// Button presses for the verification timeline ("Clicked Continue on
// capturing document"). Mirrors the web SDK's lib/click-log.ts and the RN SDK's
// src/lib/click-log.ts; keep all three in lockstep. Flutter has no document to
// listen on, so the SDK's shared UiButton reports its own presses here.
//
// PRIVACY: a press is recorded by the CATALOGUE KEY of the button's label, and
// only when the label is exactly a piece of the SDK's own copy as this workflow
// shows it. A name, an address or a company in a list is not catalogue copy, so
// it can never be recorded; such a press counts as unnamed, never described.

import '../i18n/customisable_texts.dart' show kDefaultTexts;
import '../i18n/translate.dart';
import 'step_log.dart';

const String kUnnamedControl = 'unnamed';

String _normalise(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

final Expando<Map<String, String>> _lookups = Expando<Map<String, String>>();

/// Every catalogue text as this workflow shows it, to its key. A shared text
/// ("Continue") takes the shared `common.*` key, so one button reads the same
/// on every step; otherwise the first key wins.
Map<String, String> _lookupFor(TextFn t) {
  final cached = _lookups[t];
  if (cached != null) return cached;
  final keys = kDefaultTexts.keys.toList();
  final ordered = [...keys.where((k) => k.startsWith('common.')), ...keys.where((k) => !k.startsWith('common.'))];
  final map = <String, String>{};
  for (final key in ordered) {
    final shown = _normalise(t(key));
    if (shown.isNotEmpty) map.putIfAbsent(shown, () => key);
  }
  _lookups[t] = map;
  return map;
}

/// The English default for a key, placeholders removed, for the dashboard to read.
String _englishLabel(String key) =>
    _normalise((kDefaultTexts[key] ?? '').replaceAll(RegExp(r'\{[a-zA-Z][a-zA-Z0-9]*\}'), ''));

/// A button named by its catalogue key, from its visible label then any accessible name.
({String control, String label}) controlFor(List<String?> labels, TextFn t) {
  final lookup = _lookupFor(t);
  for (final text in labels) {
    if (text == null) continue;
    final key = lookup[_normalise(text)];
    if (key != null) return (control: key, label: _englishLabel(key));
  }
  return (control: kUnnamedControl, label: '');
}

/// A press of a control the SDK names itself (the shutter, an icon with no
/// label): [control] and [label] are fixed SDK words, never applicant data.
void logControl(String control, String label) {
  try {
    StepLog.recordClick(control, label);
  } catch (_) {}
}

/// A press of a control whose words are one catalogue key ("common.retake").
void logKey(String key) => logControl(key, _englishLabel(key));

/// What kind of thing was chosen from a list, for the dashboard to say
/// "Chose an ID type". The choice itself (which ID, which country) is never
/// recorded here: it is already on the verification, and a list may hold data.
const Map<String, String> kChoiceLabels = {
  'idType': 'an ID type',
  'country': 'a country',
};

void logChoice(String kind) => logControl('choice.$kind', kChoiceLabels[kind] ?? 'an option');

/// Records one press. Never throws: a timeline line must not cost the applicant their tap.
void logPress(List<String?> labels, TextFn t) {
  try {
    final hit = controlFor(labels, t);
    StepLog.recordClick(hit.control, hit.label);
  } catch (_) {
    // Nothing to do: the press itself still goes through.
  }
}
