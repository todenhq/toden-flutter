import '../providers/verification_state.dart' show VerificationStep;
import 'scope.dart';

// ─── The Toden address book in the flow ──────────────────────────────────────
//
// SAVING the confirmed address to the person's own book (a sheet after they
// confirm it; saving is their choice), and REUSING one they saved before (a
// sheet over the first address step, shown when the flow's email is recognised:
// a code, then a pick). Both are offered only when the server says the
// platform and this organisation have them on,
// never on a business premises (a person's book is not a company's address)
// and never in a builder preview, which calls no Toden account endpoints. The
// server already narrows `reuse` by the workflow, so the SDK only reads it.
//
// Mirrors the web SDK's lib/address-book.ts and the React Native SDK's
// lib/address-book.ts. Change the three together.

final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The email the saved address offer asks about: the one the integrator passed
/// when starting the flow, else one the person proved with a code in this flow.
/// The offer never asks anybody to type one: no email, no offer.
String? addressBookEmail(String? passed, String? emailAddress, String? emailToken) {
  final given = passed?.trim() ?? '';
  if (_email.hasMatch(given)) return given;
  final proved = emailToken == null ? '' : (emailAddress?.trim() ?? '');
  return _email.hasMatch(proved) ? proved : null;
}

/// The organisation's address book switches, as /config, the workflow
/// resolution and the hosted bootstrap serve them.
class AddressBookSwitches {
  /// Ask whether to save the confirmed address to the person's own book.
  final bool save;

  /// Offer an address they saved before, when their email is recognised.
  final bool reuse;

  const AddressBookSwitches({this.save = false, this.reuse = false});

  /// Null when the server sent no `addressBook` block (an older server): both
  /// off, which is what [addressBookOffer] reads a null as.
  static AddressBookSwitches? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return AddressBookSwitches(save: raw['save'] == true, reuse: raw['reuse'] == true);
  }
}

/// What this mount offers of the address book.
class AddressBookOffer {
  final bool save;
  final bool reuse;
  const AddressBookOffer({required this.save, required this.reuse});

  static const AddressBookOffer none = AddressBookOffer(save: false, reuse: false);
}

AddressBookOffer addressBookOffer(
  AddressBookSwitches? switches, {
  String? subjectType,
  String? scope,
  bool previewMode = false,
}) {
  if (switches == null || previewMode) return AddressBookOffer.none;
  // A book is a person's: no business subject, KYB or scoped, is offered one.
  if (isBusinessSubject(subjectType) ||
      isBusinessApplication(subjectType, scope) ||
      isScopedBusiness(subjectType, scope)) {
    return AddressBookOffer.none;
  }
  return AddressBookOffer(save: switches.save, reuse: switches.reuse);
}

/// The address capture steps a picked saved address replaces.
const Set<VerificationStep> _captureSteps = {
  VerificationStep.addressSearch,
  VerificationStep.addressCollection,
  VerificationStep.addressEntrance,
  VerificationStep.addressReview,
};

/// With a saved address picked, the capture steps have nothing to do: a step
/// that would land on one (Back from the step after the address, a refusal's
/// Go back) lands on the address book step instead, where the person can keep
/// their pick or enter an address after all.
VerificationStep reusedAddressStep(VerificationStep step, bool reused) =>
    reused && _captureSteps.contains(step) ? VerificationStep.addressBook : step;

/// What the person chose to save with the address. Unticked by default.
class AddressBookSaveChoice {
  final bool save;
  final bool photo;
  final bool directions;

  const AddressBookSaveChoice({this.save = false, this.photo = false, this.directions = false});

  AddressBookSaveChoice copyWith({bool? save, bool? photo, bool? directions}) =>
      AddressBookSaveChoice(
        save: save ?? this.save,
        photo: photo ?? this.photo,
        directions: directions ?? this.directions,
      );

  Map<String, dynamic> toJson() => {'save': save, 'photo': photo, 'directions': directions};

  /// The choice as session progress stored it. Only a literal true counts.
  static AddressBookSaveChoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return AddressBookSaveChoice(
      save: raw['save'] == true,
      photo: raw['photo'] == true,
      directions: raw['directions'] == true,
    );
  }
}

const AddressBookSaveChoice kNoSave = AddressBookSaveChoice();

/// The `address.book` block of the submission, or nothing when not saving.
Map<String, dynamic> addressBookSaveBlock(
  AddressBookSaveChoice? choice, {
  required bool hasPhoto,
  required bool hasDirections,
}) {
  if (choice == null || !choice.save) return const {};
  return {
    'book': {
      'save': true,
      'photo': choice.photo && hasPhoto,
      'directions': choice.directions && hasDirections,
    },
  };
}

/// One saved address as the address book step lists it (street and area only).
class SavedAddress {
  final String entryId;
  final String? label;
  final String? area;
  final String? countryCode;
  final String? tier;
  final String? presenceStatus;
  final String? presenceDecidedAt;

  const SavedAddress({
    required this.entryId,
    this.label,
    this.area,
    this.countryCode,
    this.tier,
    this.presenceStatus,
    this.presenceDecidedAt,
  });

  /// Null for a row without an entry id: nothing could be picked from it.
  static SavedAddress? fromJson(Map<String, dynamic> json) {
    final id = json['entryId'];
    if (id is! String || id.isEmpty) return null;
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return SavedAddress(
      entryId: id,
      label: s('label'),
      area: s('area'),
      countryCode: s('countryCode'),
      tier: s('tier'),
      presenceStatus: s('presenceStatus'),
      presenceDecidedAt: s('presenceDecidedAt'),
    );
  }
}

/// The picked saved address, carried to the submission. Never saved to session
/// progress: the grant behind it is a short-lived credential.
class AddressBookReuse {
  final String grant;
  final String entryId;
  final String? label;
  final String? area;

  const AddressBookReuse({required this.grant, required this.entryId, this.label, this.area});

  /// The submission's `addressBookReuse` block, sent INSTEAD of `address`.
  Map<String, dynamic> toWire() => {'grant': grant, 'entryId': entryId};
}

/// How a saved address reads in a list: its street, else its area.
String savedAddressLine({String? label, String? area}) => [label, area]
    .whereType<String>()
    .where((v) => v.trim().isNotEmpty)
    .join(', ');

/// How long a saved "verified" presence verdict stands in for a fresh presence
/// check. Mirrors kyc-core lib/address-book/reuse/coverage.ts; the server is
/// authoritative and refuses a stale pick with `address_book_reuse_stale`.
const int kPresenceReuseWindowDays = 180;

/// Whether a saved address can stand in for this flow's presence check.
bool presenceVerdictIsRecent(SavedAddress a, {DateTime? now}) {
  final at = a.presenceDecidedAt;
  if (a.presenceStatus != 'verified' || at == null) return false;
  final decided = DateTime.tryParse(at);
  if (decided == null) return false;
  final elapsed = (now ?? DateTime.now()).difference(decided);
  return elapsed <= const Duration(days: kPresenceReuseWindowDays);
}

/// The saved addresses this flow can take. A flow that runs a presence check
/// needs a recent verdict: a fresh check cannot run on a reused address,
/// because its pin never reaches this device. Returns how many were left out
/// so the step can say why.
({List<SavedAddress> usable, int hidden}) usableSavedAddresses(
  List<SavedAddress> addresses,
  bool flowRunsPresence, {
  DateTime? now,
}) {
  if (!flowRunsPresence) return (usable: addresses, hidden: 0);
  final usable = [for (final a in addresses) if (presenceVerdictIsRecent(a, now: now)) a];
  return (usable: usable, hidden: addresses.length - usable.length);
}

/// The offer sheet's title. With a name it greets the person, and only ever by
/// what the host app passed in `userData`: the address book's own name stays
/// private, or anyone holding an email could read whose it is. No name keeps
/// the plain title rather than leaving a stray comma.
String offerTitleKey(String? firstName) =>
    (firstName?.trim().isNotEmpty ?? false)
        ? 'address.book.offer.titleNamed'
        : 'address.book.offer.title';
