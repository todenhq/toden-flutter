import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/business_application.dart';
import '../config/key_person_stake.dart';
import '../config/key_people_section_defs.dart';
import '../config/theme.dart';
import '../providers/verification_provider.dart';
import '../widgets/ui_button.dart';
import 'key_people_add_edit.dart';
import 'key_people_footer.dart';
import 'key_people_sections_list.dart';
import '../config/document_people.dart';
import '../widgets/key_people_documents_note.dart';
import '../widgets/key_people_reading_screen.dart';
import '../i18n/text_scope.dart';

// ─── Business key-people screen ───────────────────────────────────────────────
//
// "Directors & owners", in SECTIONS: beneficial owners, shareholders, directors
// & representatives. They are views over one shared list, not buckets, so a
// director who also holds 30% appears in both (key_people_sections.dart). The
// FORM lives in the add/edit sheet; the card's X takes a person out of the
// section they are shown in, which is not the same as deleting them.
//
// Mirrors the web SDK's BusinessKeyPeopleStep and the RN screen 1:1.

class BusinessKeyPeopleScreen extends ConsumerWidget {
  const BusinessKeyPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final rows = ref.watch(kYCNotifierProvider.select((s) => s.keyPeople));
    final business = ref.watch(verificationConfigProvider).business;
    final minEntries = keyPeopleMinEntries(business);
    // Roles whose email is mandatory (the ones actually sent a verification
    // link) — threaded into every validity read so the card, the sheet and
    // the Continue gate agree on what "complete" means.
    final emailRequiredFor = keyPeopleRequireEmail(business);
    // Owners must give a stake unless the workflow turns that off.
    final stakeRequired = keyPeopleRequireOwnership(business);

    final validCount =
        rows.where((r) => r.isValidWith(emailRequiredFor, stakeRequired: stakeRequired)).length;
    final hasInvalid =
        rows.any((r) => !r.isBlank && !r.isValidWith(emailRequiredFor, stakeRequired: stakeRequired));
    final meetsMinimum = validCount >= minEntries;

    // Combined ownership above 100% is factually impossible — catch the typo
    // here rather than shipping it into the registry cross-check as a doomed
    // mismatch. Under 100% is fine (not every owner has to be listed).
    final totalPct = rows.fold<double>(0, (sum, r) => sum + keyPersonPct(r));
    final overAllocated = totalPct > 100;

    final threshold = keyPeopleThreshold(ref);
    // The people the company documents name, read as each was uploaded.
    final readingDocuments = ref.watch(
        kYCNotifierProvider.select((s) => s.documentPeopleReading.isNotEmpty));
    final fromDocuments = ref.watch(kYCNotifierProvider.select((s) =>
        documentPeopleCount(
            s.documentPeople, s.businessDocuments.map((d) => d.mediaId))));
    final keptFromRemoved = ref.watch(kYCNotifierProvider
        .select((s) => s.keyPeople.where((r) => r.documentRemoved).length));

    void onContinue() {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      // Half-typed rows are dropped rather than submitted: an entry the user
      // abandoned is not a person they disclosed.
      notifier.setKeyPeople(rows
          .where((r) => r.isValidWith(emailRequiredFor, stakeRequired: stakeRequired))
          .toList(growable: false));
      notifier.nextStep();
    }

    // A full-step screen while the documents are read, so the wait is explained.
    return KeyPeopleReadingGate(
      reading: readingDocuments,
      found: fromDocuments,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No lead paragraph: the step HEADER carries "List the company's
          // directors and owners of 25% or more…" (verification_widget.dart step
          // meta, matching the web SDK's StepHeader).
          if (rows.isEmpty && minEntries == 0)
            KeyPeopleHint(
              child: Text(
                context.verificationText('keyPeople.hints.skippable'),
                style: text.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            )
          else if (minEntries > 0 && validCount < minEntries)
            KeyPeopleHint(
              child: Text(
                'List at least $minEntries '
                '${minEntries == 1 ? 'person' : 'people'} to continue'
                '${validCount > 0 ? ' ($validCount of $minEntries added)' : ''}.',
                style: text.bodyMedium.copyWith(color: colors.textSecondary),
              ),
            ),
          if (rows.isEmpty || (minEntries > 0 && validCount < minEntries))
            const SizedBox(height: UiSpacing.md),

          if (readingDocuments || fromDocuments > 0 || keptFromRemoved > 0)
            KeyPeopleDocumentsNote(
                reading: readingDocuments,
                added: fromDocuments,
                kept: keptFromRemoved),

          KeyPeopleSectionsList(
            sections: keyPeopleSectionList(
                business, threshold, context.verificationText),
            rows: rows,
            threshold: threshold,
            emailRequiredFor: emailRequiredFor,
            uboUnidentifiable: ref
                .watch(kYCNotifierProvider.select((s) => s.uboUnidentifiable)),
            // Owners can still be added by hand; the register's arrive later.
            ownershipPending: ref.watch(kYCNotifierProvider
                .select((s) => s.businessCheck.ownershipPending)),
            canAdd: rows.length < kMaxKeyPeopleRows,
            onRows: (next) =>
                ref.read(kYCNotifierProvider.notifier).setKeyPeople(next),
            onAdd: (section) =>
                openKeyPersonEditor(context, ref, section: section),
            // The section comes WITH the tap: editing a card in Shareholders
            // must show the shareholder form, not the form for whichever hat
            // happens to be their strongest.
            onEdit: (section, index) => openKeyPersonEditor(context, ref,
                index: index, section: section),
            onExemption: (v) =>
                ref.read(kYCNotifierProvider.notifier).setUboUnidentifiable(v),
          ),
          if (rows.length >= kMaxKeyPeopleRows) ...[
            const SizedBox(height: UiSpacing.sm),
            Text(
              'You can list up to $kMaxKeyPeopleRows people here.',
              textAlign: TextAlign.center,
              style: text.bodyMedium.copyWith(color: colors.textMuted),
            ),
          ],
          const SizedBox(height: UiSpacing.md),

          KeyPeopleTotals(totalPct: totalPct),
          const SizedBox(height: UiSpacing.md),
          UiButton(
            label: context.verificationText('common.continue'),
            onPressed: meetsMinimum && !hasInvalid && !overAllocated
                ? onContinue
                : null,
          ),
        ],
      ),
    );
  }
}
