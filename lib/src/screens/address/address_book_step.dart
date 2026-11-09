import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/theme.dart';
import '../../i18n/text_scope.dart';
import '../../providers/address_book_provider.dart';
import '../../providers/address_step_order.dart';
import '../../providers/verification_provider.dart';
import '../../providers/verification_state.dart';
import '../../widgets/ui_button.dart';
import 'address_book_parts.dart';
import 'address_flow_scaffold.dart';

/// The picked saved address, in place of the capture steps. The person lands
/// here going back from the step after the address: they can carry on, or use
/// a different address, which brings the offer back over the first address
/// step. Mirrors the React Native SDK's AddressBookStep.
class AddressBookStep extends ConsumerStatefulWidget {
  const AddressBookStep({super.key});

  @override
  ConsumerState<AddressBookStep> createState() => _AddressBookStepState();
}

class _AddressBookStepState extends ConsumerState<AddressBookStep>
    with AddressFlowScaffold<AddressBookStep> {
  @override
  VerificationStep get step => VerificationStep.addressBook;

  void _change() {
    flow.notifier.setAddressBookReuse(null);
    ref.read(addressBookProvider.notifier).restart();
    final first = firstCaptureStep(
        addressStepsFor(ref.read(verificationConfigProvider), ref.read(kYCNotifierProvider)));
    if (first != null) flow.notifier.goToStep(first);
  }

  @override
  Widget buildBody(BuildContext context) {
    final chosen = ref.watch(kYCNotifierProvider.select((s) => s.addressBookReuse));
    if (chosen == null) return const SizedBox.shrink();
    final t = context.verificationText;
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ChosenSavedAddress(chosen: chosen),
        const SizedBox(height: UiSpacing.md),
        UiButton(label: t('address.book.continue'), onPressed: flow.exitForward),
        const SizedBox(height: UiSpacing.sm),
        UiButton.ghost(label: t('address.book.chosen.change'), onPressed: _change),
      ]),
    ).animate().fadeIn(duration: 250.ms);
  }
}
