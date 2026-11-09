// WHEN each gesture prompt appeared and when it passed, measured from the start
// of the liveness recording.
//
// A prompt on its own only proves a gesture HAPPENED. A clip that smiles and
// blinks on repeat meets any of those prompts within seconds. The server reads
// these times against the recording to check the gesture came AFTER it was
// asked for, which a prepared video cannot do on purpose.
//
// They are a claim like the rest of the integrity block: they tell the server
// where to look, and prove nothing by themselves. The flash has its own times
// and a passive hold has no gesture, so neither is listed.
//
// Mirrors the web SDK (liveness/prompt-timeline.ts) and the React Native SDK
// (liveness/promptTimeline.ts). Change all three together.

const _gestures = {'turn', 'nod', 'blink', 'smile'};

class _Entry {
  _Entry(this.prompt, this.shownAt);
  final String prompt;
  final int shownAt;
  int? passedAt;
}

class PromptTimeline {
  final List<_Entry> _entries = [];

  /// A prompt appeared. Showing it again (a timer restarted) keeps the first time.
  void shown(String prompt, int at) {
    if (!_gestures.contains(prompt)) return;
    final last = _entries.isEmpty ? null : _entries.last;
    if (last != null && last.passedAt == null && last.prompt == prompt) return;
    _entries.add(_Entry(prompt, at));
  }

  /// The prompt on screen passed.
  void passed(int at) {
    if (_entries.isEmpty) return;
    _entries.last.passedAt ??= at;
  }

  /// A retry starts again: an earlier attempt's times say nothing about this recording.
  void reset() => _entries.clear();

  /// The passed prompts against the recording's start, or null when there is no
  /// recording to measure from or nothing passed. A prompt shown before the
  /// recorder went live counts from its first frame.
  List<Map<String, Object>>? report(int? startedAt) {
    if (startedAt == null) return null;
    final done = [for (final e in _entries) if (e.passedAt != null) e];
    if (done.isEmpty) return null;
    return [
      for (final e in done)
        {
          'prompt': e.prompt,
          'shownAt': (e.shownAt - startedAt) < 0 ? 0 : e.shownAt - startedAt,
          'passedAt': (e.passedAt! - startedAt) < 0 ? 0 : e.passedAt! - startedAt,
        },
    ];
  }
}
