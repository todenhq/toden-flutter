import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/country_id_types.dart';
import '../config/id_types.dart';
import '../config/nin_slip.dart';
import '../config/retired_id_types.dart';
import '../config/theme.dart';
import '../providers/verification_provider.dart';
import '../providers/verification_state.dart';
import '../providers/step_order.dart';
import '../widgets/ui_pulse_loader.dart';
import '../widgets/icons/icons.dart';
import 'id_country_field.dart';

// ─── ID type selection screen ─────────────────────────────────────────────────

class IdTypeScreen extends ConsumerWidget {
  const IdTypeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(verificationConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final colors = context.myazaColors;
    final text = context.myazaText;

    // The server's granted list is authoritative — every offered ID is resolved
    // through [resolveIdTypeDefinition] so Global-Document IDs (no curated
    // entry) still render from the server row's metadata. The consumer's
    // `idTypes` prop, when set, narrows the offering by key. While config is
    // loading we render a placeholder; on error we fall back to the curated
    // list for the country (server still 403s anything actually disabled).
    final serverConfig = state.serverConfig;
    final country = effectiveCountry(config, state);
    // The picked country's own idTypes narrow the list; otherwise the
    // top-level `idTypes` prop applies. Null/empty = all granted. Shared with
    // the multi-ID plan so the picker and the slot options cannot disagree.
    final propKeys = pinnedIdTypesFor(config, country);
    bool allowed(String key) =>
        propKeys == null || propKeys.isEmpty || propKeys.contains(key);

    final available = switch (serverConfig.status) {
      ServerConfigStatus.ready => [
          for (final row in serverConfig.idTypes)
            if (row.country == country && allowed(row.idType))
              resolveIdTypeDefinition(
                country,
                row.idType,
                label: row.label,
                requiresDocumentCapture: row.requiresDocumentCapture,
                scanSides: row.scanSides,
                supportsNfc: row.supportsNfc,
              ),
        ],
      // A retired type (BVN Premium, now BVN's premium option) is never
      // offered, even from the local list used when the server config fails.
      ServerConfigStatus.error => curatedIdTypesForCountry(country)
          .where((c) => allowed(c.key) && !isRetiredIdType(country, c.key))
          .toList(),
      ServerConfigStatus.loading => const <IdTypeConfig>[],
    };

    // Document Intelligence off ⇒ number-only IDs only, so drop every
    // document-scanned ID from the picker rather than offering one and then
    // skipping its capture step: that produced a submission with no document
    // for an ID that needs one. "This ID cannot be verified in this flow" is a
    // fact about availability, not a step to skip. Mirrors the web SDK.
    // A workflow from before NIN and its slip merged may list both: only the
    // slip is offered then (config/nin_slip.dart).
    final offered = withoutNinBesideSlip(country, available, (t) => t.key);
    final base = config.enableDocumentCapture
        ? offered
        : offered.where((t) => !t.requiresDocumentCapture).toList();

    // Multi-ID: this picker is for ONE check of several. It may only offer
    // picks that are still free AND leave every later check something to
    // offer — the server validates the same rule, so an unsafe pick would be a
    // submission it rejects.
    final plan = ref.read(kYCNotifierProvider.notifier).multiIdPlan();
    final visible = plan == null
        ? base
        : base.where((t) => plan.safeOptions.contains(t.key)).toList();

    // The combined layout picks the country here, above the IDs, rather than
    // on a step of its own (config/id_selection_layout.dart).
    final countryHere = countryOnIdTypeStep(config, state);
    final countryField = countryHere
        ? Padding(
            padding: const EdgeInsets.only(bottom: UiSpacing.md),
            child: IdCountryField(
              options: [
                for (final c in countrySelectOptions(config, state)) c.toUpperCase(),
              ],
            ),
          )
        : null;

    if (serverConfig.status == ServerConfigStatus.loading) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (countryField != null) countryField,
          const Padding(
            padding: EdgeInsets.symmetric(vertical: UiSpacing.xl),
            child: Center(child: UiPulseLoader()),
          ),
        ],
      );
    }

    if (serverConfig.status == ServerConfigStatus.ready && visible.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (countryField != null) countryField,
          Padding(
            padding: const EdgeInsets.all(UiSpacing.md),
            child: Container(
              padding: const EdgeInsets.all(UiSpacing.md),
              decoration: BoxDecoration(
                color: colors.errorBg,
                borderRadius: BorderRadius.circular(UiRadius.md),
                border: Border.all(color: UiColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                'No ID types are enabled for your organization. Contact your administrator to request access.',
                style: text.bodyMedium.copyWith(color: UiColors.error),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (countryField != null) countryField,
        // ── ID type cards ────────────────────────────────────────────────────
        ...visible.map((idTypeConfig) {
          final isSelected = state.selectedIdType?.key == idTypeConfig.key;
          return Padding(
            // The web list's gap-3.
            padding: const EdgeInsets.only(bottom: 12),
            child: _IdTypeCard(
              config: idTypeConfig,
              isSelected: isSelected,
              // Picking an ID type ADVANCES — there is no Continue button. It's
              // a single-select list with nothing else on the step to confirm,
              // so a second tap only restates a decision already made. It also
              // matches country-select, which advances on tap: one list
              // advancing and the next not was the inconsistency worth
              // removing. A mis-tap costs one Back.
              onTap: () {
                notifier.setIdType(idTypeConfig);
                notifier.nextStep();
              },
            ),
          );
        }),
      ],
    );
  }
}

// ─── Individual ID type card ──────────────────────────────────────────────────

/// The ID glyph's size: drawn bare on the card, so larger than a tiled icon.
const double kIdTypeIconSize = 40;

class _IdTypeCard extends StatelessWidget {
  final IdTypeConfig config;
  final bool isSelected;
  final VoidCallback onTap;

  const _IdTypeCard({
    required this.config,
    required this.isSelected,
    required this.onTap,
  });

  // Same lucide icons as the web SDK's IdTypeStep (ID_TYPE_ICONS). Keyed by the
  // server ID key so Global-Document IDs get a sensible default icon.
  static UiIconData _iconFor(String key) => switch (key) {
        'bvn' || 'bvn-premium' => UiIcons.landmark, // Bank Verification
        'tax-id' => UiIcons.receiptText, // Tax ID (NIN-keyed)
        'nin' || 'vnin' || 'nin-phone' => UiIcons.fingerprint,
        'phone-number' => UiIcons.smartphone,
        'passport' => UiIcons.bookUser,
        'drivers-license' => UiIcons.idCard,
        'pvc' || 'voters' => UiIcons.contact, // Voter's Card
        _ => UiIcons.fileText, // the web's FileText: the NIN slip and the rest
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    final borderColor = isSelected ? colors.primary : colors.border;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary50 : colors.background,
        // The web card: rounded-xl, p-4, a 1px border that turns primary
        // when chosen.
        borderRadius: BorderRadius.circular(UiRadius.sm),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: colors.textDark.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(UiRadius.sm),
          splashColor: colors.primary.withValues(alpha: 0.06),
          highlightColor: colors.primary.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: UiSpacing.md,
              vertical: UiSpacing.md,
            ),
            child: Row(
              children: [
                // ── Icon ─────────────────────────────────────────────────────
                // The glyph alone, no tile behind it: the card is the frame.
                // Larger than the web SDK's h-7 on a phone, by design.
                UiIcon(
                  _iconFor(config.key),
                  size: kIdTypeIconSize,
                  color: isSelected ? colors.primary : colors.textSecondary,
                ),
                const SizedBox(width: 12),

                // ── Label ────────────────────────────────────────────────────
                // Tapping a row ADVANCES immediately (no Continue button), and
                // like the web card it carries no chevron or radio beside it.
                Expanded(
                  child: Text(
                    config.label,
                    style: text.label.copyWith(
                      fontSize: 18,
                      height: 24 / 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
