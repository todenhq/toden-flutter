import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/address_book.dart';

// ─── The saved address offer's state machine ─────────────────────────────────
//
// idle → checking → offer → code → pick, or closed. It is a sheet over the
// first address step, not a step: the email comes from the flow
// (config/address_book.dart), the server says whether it has an address this
// flow can take, and nothing shows when it does not. `closed` stays closed for
// the attempt, so a person who chose to enter an address is not asked again on
// the way back.
//
// A provider rather than the sheet's own state because the offer outlives the
// screens under it: the search and pin steps each host it. Pure state: the
// widgets make the calls. Reset with the flow (VerificationNotifier.reset) and
// scoped per flow by verificationFlowOverrides. Mirrors the React Native SDK's
// store/addressBook.ts.

enum AddressBookPhase { idle, checking, offer, code, pick, closed }

class AddressBookState {
  final AddressBookPhase phase;
  final String? challengeId;

  /// Bumped each time the code field must start empty (a new code, a wrong
  /// one), so the field remounts rather than keeping stale digits.
  final int codeAttempt;
  final String? grant;
  final List<SavedAddress> addresses;

  /// Saved addresses this flow cannot take (a presence flow needs a recent verdict).
  final int hidden;
  final String? selected;
  final bool busy;

  /// A catalogue text key for the error line, or the server's own words.
  final String? errorKey;
  final String? errorMessage;

  const AddressBookState({
    this.phase = AddressBookPhase.idle,
    this.challengeId,
    this.codeAttempt = 0,
    this.grant,
    this.addresses = const [],
    this.hidden = 0,
    this.selected,
    this.busy = false,
    this.errorKey,
    this.errorMessage,
  });

  bool get hasError => errorKey != null || errorMessage != null;

  /// Whether the sheet is the thing on screen.
  bool get sheetOpen =>
      phase == AddressBookPhase.offer || phase == AddressBookPhase.code || phase == AddressBookPhase.pick;

  /// The picked entry; one address needs no choosing and starts selected.
  SavedAddress? get picked => addresses.where((a) => a.entryId == selected).firstOrNull;

  AddressBookState copyWith({
    AddressBookPhase? phase,
    String? challengeId,
    int? codeAttempt,
    String? grant,
    List<SavedAddress>? addresses,
    int? hidden,
    String? selected,
    bool? busy,
    // Replaces both error fields with the ones passed (null clears them).
    bool clearError = false,
    String? errorKey,
    String? errorMessage,
  }) =>
      AddressBookState(
        phase: phase ?? this.phase,
        challengeId: challengeId ?? this.challengeId,
        codeAttempt: codeAttempt ?? this.codeAttempt,
        grant: grant ?? this.grant,
        addresses: addresses ?? this.addresses,
        hidden: hidden ?? this.hidden,
        selected: selected ?? this.selected,
        busy: busy ?? this.busy,
        errorKey: clearError ? errorKey : (errorKey ?? this.errorKey),
        errorMessage: clearError ? errorMessage : (errorMessage ?? this.errorMessage),
      );
}

class AddressBookNotifier extends Notifier<AddressBookState> {
  @override
  AddressBookState build() => const AddressBookState();

  void checking() => state = state.copyWith(phase: AddressBookPhase.checking);

  /// The lookup answered. A later decision is left alone.
  void recognised(bool recognised) {
    if (state.phase != AddressBookPhase.checking) return;
    state = state.copyWith(phase: recognised ? AddressBookPhase.offer : AddressBookPhase.closed);
  }

  void select(String entryId) => state = state.copyWith(selected: entryId);

  void setBusy(bool busy) => state = state.copyWith(busy: busy, clearError: true);

  void fail({String? key, String? message}) =>
      state = state.copyWith(clearError: true, errorKey: key, errorMessage: message, busy: false);

  /// The code went out: ask for it.
  void codeSent(String challengeId) => state = state.copyWith(
        challengeId: challengeId,
        phase: AddressBookPhase.code,
        codeAttempt: state.codeAttempt + 1,
        busy: false,
        clearError: true,
      );

  /// The code was refused: clear the field for another go.
  void codeRefused({String? key, String? message}) {
    fail(key: key, message: message);
    state = state.copyWith(codeAttempt: state.codeAttempt + 1);
  }

  /// The code was right: the person's saved addresses, as this flow can take them.
  void listed(String grant, List<SavedAddress> addresses, {required bool flowRunsPresence}) {
    final listed = usableSavedAddresses(addresses, flowRunsPresence);
    state = AddressBookState(
      phase: AddressBookPhase.pick,
      challengeId: state.challengeId,
      codeAttempt: state.codeAttempt,
      grant: grant,
      addresses: listed.usable,
      hidden: listed.hidden,
      selected: listed.usable.length == 1 ? listed.usable.single.entryId : null,
    );
  }

  /// The person will enter an address: the offer stays closed.
  void close() => state = state.copyWith(phase: AddressBookPhase.closed, busy: false, clearError: true);

  /// Back to the offer, from the picked address. The email is already
  /// recognised, so nothing is looked up again.
  void restart() => state = const AddressBookState(phase: AddressBookPhase.offer);

  /// The server refused the pick: the offer comes back, saying why.
  void refused() =>
      state = const AddressBookState(phase: AddressBookPhase.offer, errorKey: 'address.book.refused');

  /// A new verification starts from nothing.
  void reset() => state = const AddressBookState();
}

final addressBookProvider =
    NotifierProvider<AddressBookNotifier, AddressBookState>(AddressBookNotifier.new);
