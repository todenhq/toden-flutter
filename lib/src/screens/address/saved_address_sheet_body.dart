import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/address_book.dart';
import '../../config/contact_verification.dart' show OtpInputStyle;
import '../../config/theme.dart';
import '../../i18n/text_scope.dart';
import '../../providers/address_book_provider.dart';
import '../../providers/verification_provider.dart';
import '../../providers/verification_state.dart';
import '../../services/api_service.dart';
import '../../widgets/icons/icons.dart';
import '../../widgets/otp_input.dart';
import '../../widgets/ui_button.dart';
import 'address_book_parts.dart';

const int _codeLength = 6;

/// The offer, the code and the pick in one sheet. Pops the picked address; the
/// host applies it once the sheet has gone.
class SavedAddressSheetBody extends ConsumerStatefulWidget {
  const SavedAddressSheetBody({super.key});

  @override
  ConsumerState<SavedAddressSheetBody> createState() => _SavedAddressSheetBodyState();
}

class _SavedAddressSheetBodyState extends ConsumerState<SavedAddressSheetBody> {
  String _code = '';

  AddressBookNotifier get _book => ref.read(addressBookProvider.notifier);
  VerificationApiService get _api => ref.read(kYCNotifierProvider.notifier).api;
  VerificationState get _flow => ref.read(kYCNotifierProvider);

  String? get _email => addressBookEmail(
      ref.read(verificationConfigProvider).userData?.email, _flow.emailAddress, _flow.emailToken);

  /// The server's own words for a refusal it explained, else the generic line.
  void _fail(Object err, {bool code = false}) {
    final message = err is VerificationApiException && err.statusCode > 0 && err.statusCode < 500
        ? err.message
        : null;
    final key = message == null ? 'address.book.error' : null;
    code ? _book.codeRefused(key: key, message: message) : _book.fail(key: key, message: message);
  }

  /// Send the code (the offer's yes, and Send a new code).
  Future<void> _sendCode() async {
    final email = _email;
    if (email == null) return;
    _book.setBusy(true);
    try {
      final challengeId = await _api.addressBookCode(email);
      if (!mounted) return;
      _code = '';
      _book.codeSent(challengeId);
    } catch (err) {
      if (mounted) _fail(err);
    }
  }

  Future<void> _checkCode([String? typed]) async {
    final value = typed ?? _code;
    final challengeId = ref.read(addressBookProvider).challengeId;
    if (challengeId == null || value.length != _codeLength) return;
    _book.setBusy(true);
    try {
      final listing = await _api.addressBookAddresses(challengeId, value);
      if (!mounted) return;
      _book.listed(listing.grant, listing.addresses,
          flowRunsPresence: ref.read(verificationConfigProvider).addressCollection?.presenceEnabled == true);
    } catch (err) {
      if (!mounted) return;
      _code = '';
      _fail(err, code: true);
    }
  }

  void _enterNew() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final book = ref.watch(addressBookProvider);
    final t = context.verificationText;
    final text = context.myazaText;
    final muted = context.myazaColors.textSecondary;
    final email = _email ?? '';
    final error = book.errorMessage ?? (book.errorKey == null ? null : t(book.errorKey!));
    final errorLine = AddressBookError(error);
    final enterNew =
        UiButton.ghost(label: t('address.book.offer.new'), onPressed: book.busy ? null : _enterNew);

    final List<Widget> body = switch (book.phase) {
      AddressBookPhase.code => [
          AddressBookSheetHeading(
            icon: UiIcons.mail,
            title: t('address.book.code.title'),
            description: t('address.book.code.description', vars: {'email': email}),
          ),
          const SizedBox(height: UiSpacing.lg),
          OtpInput(
            key: ValueKey('address-book-code-${book.codeAttempt}'),
            length: _codeLength,
            style: OtpInputStyle.segmented,
            enabled: !book.busy,
            onChanged: (v) => setState(() => _code = v),
            onCompleted: (v) {
              _code = v;
              _checkCode(v);
            },
          ),
          errorLine,
          const SizedBox(height: UiSpacing.lg),
          UiButton(
            label: t(book.busy ? 'address.book.code.checking' : 'address.book.code.check'),
            isLoading: book.busy,
            onPressed: book.busy || _code.length != _codeLength ? null : _checkCode,
          ),
          const SizedBox(height: UiSpacing.sm),
          UiButton.ghost(label: t('address.book.code.resend'), onPressed: book.busy ? null : _sendCode),
        ],
      AddressBookPhase.pick => [
          AddressBookSheetHeading(
            icon: UiIcons.mapPin,
            title: t('address.book.pick.title'),
            description: t('address.book.pick.description'),
          ),
          const SizedBox(height: UiSpacing.md),
          if (book.addresses.isNotEmpty)
            SavedAddressList(addresses: book.addresses, selected: book.selected, onSelect: _book.select)
          else
            Text(t('address.book.pick.none'),
                textAlign: TextAlign.center, style: text.bodyMedium.copyWith(color: muted)),
          if (book.hidden > 0)
            Padding(
              padding: const EdgeInsets.only(top: UiSpacing.sm),
              child: Text(t('address.book.pick.stale'),
                  textAlign: TextAlign.center, style: text.bodySmall.copyWith(color: muted)),
            ),
          errorLine,
          const SizedBox(height: UiSpacing.md),
          if (book.addresses.isNotEmpty) ...[
            UiButton(
              label: t('address.book.pick.use'),
              onPressed: book.picked == null ? null : () => Navigator.of(context).pop(book.picked),
            ),
            const SizedBox(height: UiSpacing.sm),
          ],
          enterNew,
        ],
      _ => [
          AddressBookSheetHeading(
            icon: UiIcons.bookUser,
            title: t(offerTitleKey(ref.read(verificationConfigProvider).userData?.firstName)),
            description: t('address.book.offer.description'),
          ),
          const SizedBox(height: UiSpacing.md),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            UiIcon(UiIcons.mail, size: 16, color: muted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(t('address.book.offer.email', vars: {'email': email}),
                  textAlign: TextAlign.center, style: text.bodySmall.copyWith(color: muted)),
            ),
          ]),
          errorLine,
          const SizedBox(height: UiSpacing.lg),
          UiButton(
            label: t(book.busy ? 'address.book.offer.sending' : 'address.book.offer.use'),
            isLoading: book.busy,
            onPressed: book.busy ? null : _sendCode,
          ),
          const SizedBox(height: UiSpacing.sm),
          enterNew,
        ],
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(UiSpacing.lg, UiSpacing.xs, UiSpacing.lg, UiSpacing.lg),
        child: AnimatedSwitcher(
          // A soft fade between the phases, so the change reads as one sheet.
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
          child: Column(
            key: ValueKey(book.phase),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: body,
          ),
        ),
      ),
    );
  }
}
