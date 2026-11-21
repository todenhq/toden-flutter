// Session step log — records each SDK step the user reaches, with a
// timestamp, so the server can reconstruct the journey on the verification
// timeline ("consent opened → ID type chosen → document captured → …").
// Rides the verify submission as metadata.device.stepLog — the same free-form
// channel the Device Intelligence fingerprint uses: no extra network calls,
// no new endpoint, and old SDKs simply never send it. `sentAt` is stamped at
// snapshot time so the server can correct client-clock skew against its own
// receipt time. Step names only — never PII. Mirrors the web SDK's
// lib/step-log.ts and the RN SDK's src/lib/step-log.ts; keep all three in
// lockstep, including the kebab-case wire names below.

import '../providers/verification_state.dart' show VerificationStep;

/// Canonical wire names shared with the web/RN SDKs — the server's timeline
/// titles key off these, so Flutter must not leak its camelCase enum names.
///
/// Public because the resubmission filter (`step_resubmit.dart`) matches a
/// reviewer's chosen steps against exactly these names. Two maps would be two
/// chances to disagree about what `document-capture` is called.
const Map<VerificationStep, String> kStepWireNames = {
  VerificationStep.consent: 'consent',
  VerificationStep.contactEmail: 'email-verification',
  VerificationStep.contactPhone: 'phone-verification',
  VerificationStep.countrySelect: 'country-select',
  VerificationStep.idType: 'id-type',
  VerificationStep.documentCapture: 'document-capture',
  VerificationStep.idInput: 'id-input',
  VerificationStep.nfc: 'nfc',
  VerificationStep.liveness: 'liveness',
  VerificationStep.proofOfAddress: 'proof-of-address',
  VerificationStep.supportingDocuments: 'supporting-documents',
  VerificationStep.addressBook: 'address-book',
  VerificationStep.addressSearch: 'address-search',
  VerificationStep.addressCollection: 'address-collection',
  VerificationStep.addressEntrance: 'address-entrance',
  VerificationStep.addressReview: 'address-review',
  VerificationStep.questionnaire: 'questionnaire',
  VerificationStep.businessDetails: 'business-details',
  VerificationStep.businessKeyPeople: 'business-key-people',
  VerificationStep.businessDocuments: 'business-documents',
  VerificationStep.applicantRole: 'applicant-role',
  VerificationStep.submitted: 'submitted',
};

/// What got in the way, by closed code (drop-off insights, user 2026-11-20).
/// Add-only, and the same codes the web and React Native SDKs send; Core reads
/// them to say why an applicant likely stopped. Each code's allowed details are
/// closed too; anything else is sent as `other`.
const Map<String, Set<String>> kJourneyEventDetails = {
  'camera_denied': {},
  'camera_unavailable': {'in_use', 'not_found', 'other'},
  'microphone_denied': {},
  'upload_failed': {'document', 'selfie', 'video', 'supporting_document', 'proof_of_address', 'other'},
  'network_error': {'offline', 'timeout', 'other'},
  'liveness_failed': {'no_face', 'too_dark', 'multiple_faces', 'turn_not_seen', 'timeout', 'face_changed', 'other'},
  'capture_rejected': {'blur', 'glare', 'cut_off', 'no_document', 'too_dark', 'wrong_side', 'other'},
  'nfc_failed': {'not_supported', 'read_error', 'timeout', 'access_denied', 'other'},
  'code_resent': {'email', 'phone'},
  'code_invalid': {'email', 'phone'},
  'app_backgrounded': {},
  'app_foregrounded': {},
  'flow_closed': {},
  // The SDK's own error code, checked by shape rather than listed.
  'error_shown': {},
};

/// Codes after which the progress is saved at once, so the journey reaches the
/// server even when the applicant never comes back.
const Set<String> _kSaveAtOnce = {
  'camera_denied',
  'camera_unavailable',
  'upload_failed',
  'network_error',
  'flow_closed',
  'app_backgrounded',
};

/// Codes saved at once from their second occurrence: one failed attempt is
/// ordinary, two is someone struggling.
const Set<String> _kSaveFromSecond = {'liveness_failed', 'capture_rejected', 'nfc_failed'};

final RegExp _errorCodeShape = RegExp(r'^[a-z_]{1,32}$');

class StepLog {
  StepLog._();

  static const int _maxEntries = 40;
  static const int _maxClicks = 60;
  static const int _maxEvents = 60;
  /// A second press of the same button inside this window is a double tap, not a new press.
  static const Duration _repeat = Duration(milliseconds: 500);
  /// The same event (code, detail, step) inside this window is one event.
  static const Duration _sameEvent = Duration(seconds: 2);
  /// A trip to the background shorter than this is a system sheet (iOS's
  /// permission prompt), not the applicant leaving: the pair is dropped.
  static const Duration _briefAway = Duration(seconds: 1);
  /// At most one immediate save in this window.
  static const Duration _saveGap = Duration(seconds: 3);
  static final List<Map<String, dynamic>> _entries = [];
  static final List<Map<String, dynamic>> _clicks = [];
  static final List<Map<String, dynamic>> _events = [];
  static final Map<String, int> _eventCounts = {};
  static Map<String, dynamic>? _client;
  static DateTime? _lastSaveAsked;

  /// Saves the progress now (verification_provider.dart registers it while a
  /// flow is open). Best-effort: anything it throws is swallowed here.
  static void Function()? onSaveNeeded;

  /// Fresh slate per session (flow open / provider reset). The device does not
  /// change, so [client] stays.
  static void reset() {
    _entries.clear();
    _clicks.clear();
    _events.clear();
    _eventCounts.clear();
    _lastSaveAsked = null;
  }

  /// The SDK and device facts the journey carries: no identifiers.
  static void setClient(Map<String, dynamic> client) {
    _client = Map<String, dynamic>.from(client);
  }

  static Map<String, dynamic>? get client => _client;

  /// The step the applicant is on, as the log names it.
  static String get currentStep => _entries.isEmpty ? 'unknown' : _entries.last['step'] as String;

  /// Records something that got in the way: [code] from [kJourneyEventDetails],
  /// [detail] one of that code's details (anything else becomes `other`, or is
  /// dropped where the code takes none). Never applicant data. Saves the
  /// progress at once where the code calls for it.
  static void recordEvent(String code, {String? detail, DateTime? now}) {
    final details = kJourneyEventDetails[code];
    if (details == null) return;
    final at = (now ?? DateTime.now()).toUtc();
    final step = currentStep;
    String? d;
    if (code == 'error_shown') {
      d = detail != null && _errorCodeShape.hasMatch(detail) ? detail : 'other';
    } else if (details.isNotEmpty) {
      d = detail != null && details.contains(detail) ? detail : (details.contains('other') ? 'other' : null);
    }
    if (_events.isNotEmpty) {
      final last = _events.last;
      final lastAt = DateTime.parse(last['at'] as String);
      final within = at.difference(lastAt);
      if (last['code'] == code && last['detail'] == d && last['step'] == step && within < _sameEvent) return;
      // Back within a second: a system sheet, not the applicant leaving.
      if (code == 'app_foregrounded' && last['code'] == 'app_backgrounded' && within < _briefAway) {
        _events.removeLast();
        return;
      }
    }
    if (_events.length >= _maxEvents) _events.removeAt(0);
    _events.add({'code': code, 'step': step, 'at': at.toIso8601String(), if (d != null) 'detail': d});
    final count = (_eventCounts[code] ?? 0) + 1;
    _eventCounts[code] = count;
    if (_kSaveAtOnce.contains(code) || (_kSaveFromSecond.contains(code) && count >= 2)) _askToSave(at);
  }

  static void _askToSave(DateTime at) {
    final last = _lastSaveAsked;
    if (last != null && at.difference(last) < _saveGap) return;
    _lastSaveAsked = at;
    try {
      onSaveNeeded?.call();
    } catch (_) {}
  }

  /// Whether the log holds anything the applicant did beyond coming and going.
  static bool get hasActivity => _events.any((e) => e['code'] != 'app_backgrounded' && e['code'] != 'app_foregrounded');

  /// Records a press of a named SDK button on the step the applicant is on.
  /// [control] is the text-catalogue key of its label (utils/click_log.dart),
  /// [label] its English default: never what the applicant typed or their data.
  static void recordClick(String control, String label, {DateTime? now}) {
    if (_clicks.length >= _maxClicks) return;
    final at = (now ?? DateTime.now()).toUtc();
    final step = _entries.isEmpty ? 'unknown' : _entries.last['step'] as String;
    if (_clicks.isNotEmpty) {
      final last = _clicks.last;
      final lastAt = DateTime.parse(last['at'] as String);
      if (last['control'] == control && last['step'] == step && at.difference(lastAt) < _repeat) return;
    }
    _clicks.add({'control': control, 'label': label, 'step': step, 'at': at.toIso8601String()});
  }

  /// Records a step visit. Consecutive duplicates are collapsed; back-and-forth
  /// navigation is kept — repeat visits are honest journey data.
  /// [slot] is the 1-based multi-ID check the applicant was on, emitted only
  /// once one has been COMMITTED (on an ordinary run it would be a constant 1
  /// on every entry, which is noise).
  ///
  /// It is carried because the SERVER cannot tell a slot advance from a
  /// back-press: a multi-ID run legitimately returns to the ID picker for its
  /// next ID, and by step name alone that is identical to pressing Back. Only
  /// the client knows a check was committed, so only the client can say.
  /// [idType] is the ID selected AT THAT MOMENT. A check's final pick is not
  /// what the applicant was doing earlier in it: pick one ID, go back, settle
  /// on another, and labelling the earlier step from the committed check names
  /// an ID they had not chosen yet.
  static void record(VerificationStep step, {int? slot, String? idType}) {
    if (_entries.length >= _maxEntries) return;
    final name = kStepWireNames[step] ?? step.name;
    // A revisit on a NEW check, or on a DIFFERENT ID, is a different visit.
    if (_entries.isNotEmpty &&
        _entries.last['step'] == name &&
        _entries.last['slot'] == slot &&
        _entries.last['idType'] == idType) {
      return;
    }
    _entries.add({
      'step': name,
      'at': DateTime.now().toUtc().toIso8601String(),
      if (slot != null) 'slot': slot,
      if (idType != null) 'idType': idType,
    });
  }

  /// Snapshot attached to the verify submission. Null when nothing was
  /// recorded so the field is simply absent.
  static Map<String, dynamic>? snapshot() {
    if (_entries.isEmpty && _clicks.isEmpty && _events.isEmpty) return null;
    return {
      if (_clicks.isNotEmpty) 'clicks': _clicks.map(Map<String, dynamic>.from).toList(growable: false),
      if (_events.isNotEmpty) 'events': _events.map(Map<String, dynamic>.from).toList(growable: false),
      if (_client != null) 'client': Map<String, dynamic>.from(_client!),
      // NOT `List<Map<String, String>>.from(...)`. Entries carry an int `slot`,
      // so the literal above infers `Map<String, Object>` — and that cast threw
      // a TypeError on every recorded step. Because `_collectDeviceMetadata`
      // wraps its whole body in a catch that returns null, the throw discarded
      // the ENTIRE device block: no fingerprint, no SDK identity, no step log.
      // Device Intelligence read empty, the device showed as "Unknown device /
      // Unknown SDK", and the timeline had no step events — three symptoms, one
      // cast, and nothing anywhere reported an error.
      'steps': _entries.map(Map<String, dynamic>.from).toList(growable: false),
      'sentAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
