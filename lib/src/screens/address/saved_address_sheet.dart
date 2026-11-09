import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/address_book.dart';
import '../../providers/address_book_provider.dart';
import '../../providers/address_step_order.dart';
import '../../providers/verification_provider.dart';
import '../../widgets/themed_sheet.dart';
import 'saved_address_sheet_body.dart';

/// Hosts the offer of a saved address over the first address step. It appears
/// only when the flow's email is recognised, ahead of any presence primer
/// (somebody using a saved address never needs it), and asks for one decision:
/// use it (a code to that email, then a pick) or enter a new one. The company
/// receives the address only once the verification passes and the person is
/// confirmed as the book's owner (kyc-core address-book/reuse). Closing the
/// sheet any way is entering a new address. Mirrors the React Native SDK's
/// SavedAddressSheet.
class SavedAddressOffer extends ConsumerStatefulWidget {
  final Widget child;

  /// A saved address was picked: leave the address flow forwards.
  final VoidCallback onUsed;

  const SavedAddressOffer({super.key, required this.child, required this.onUsed});

  @override
  ConsumerState<SavedAddressOffer> createState() => _SavedAddressOfferState();
}

class _SavedAddressOfferState extends ConsumerState<SavedAddressOffer> {
  bool _sheetUp = false;

  AddressBookNotifier get _book => ref.read(addressBookProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(addressBookProvider).sheetOpen) {
        _open();
      } else {
        _lookUp();
      }
    });
  }

  /// Ask once whether the email has an address to offer. Silent either way.
  /// `checking` counts too: a step changed under a lookup in flight asks again.
  Future<void> _lookUp() async {
    final phase = ref.read(addressBookProvider).phase;
    if (phase != AddressBookPhase.idle && phase != AddressBookPhase.checking) return;
    final config = ref.read(verificationConfigProvider);
    final state = ref.read(kYCNotifierProvider);
    final email = addressBookEmail(config.userData?.email, state.emailAddress, state.emailToken);
    if (!addressBookOfferFor(config, state).reuse || email == null) return;
    _book.checking();
    final api = ref.read(kYCNotifierProvider.notifier).api;
    bool recognised;
    try {
      recognised = await api.addressBookLookup(
        email,
        presence: config.addressCollection?.presenceEnabled == true,
      );
    } catch (_) {
      recognised = false;
    }
    if (mounted) _book.recognised(recognised);
  }

  Future<void> _open() async {
    if (_sheetUp) return;
    _sheetUp = true;
    final entry = await showUiSheet<SavedAddress>(
      context,
      isScrollControlled: true,
      builder: (_) => const SavedAddressSheetBody(),
    );
    _sheetUp = false;
    if (!mounted) return;
    final book = ref.read(addressBookProvider);
    final grant = book.grant;
    if (entry != null && grant != null) {
      ref.read(kYCNotifierProvider.notifier).setAddressBookReuse(AddressBookReuse(
          grant: grant, entryId: entry.entryId, label: entry.label, area: entry.area));
      _book.close();
      widget.onUsed();
      return;
    }
    if (book.sheetOpen) _book.close();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AddressBookState>(addressBookProvider, (previous, next) {
      if (next.sheetOpen && previous?.sheetOpen != true) _open();
    });
    return widget.child;
  }
}
