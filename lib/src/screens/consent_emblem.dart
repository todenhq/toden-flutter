import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../config/trust_attribution.dart';
import '../providers/verification_provider.dart';
import '../utils/resolve_url.dart';
import '../widgets/icons/icons.dart';
import '../widgets/toden_mark.dart';

// ─── The mark over the consent title ─────────────────────────────────────────
//
// Toden's split shield on a plain muted square, in the colours the footer
// draws it in (widgets/toden_mark.dart todenMarkColours): the ink chosen for
// the sheet's background, the right half Toden's purple. No border, gradient,
// glow, motion or shadow: the words below carry the screen.
//
// Where the organisation's own logo replaces Toden's in the footer (a paid
// custom attribution), its logo sits on the square instead, never Toden's
// mark, and a shield when it has none. Mirrors the web SDK's
// steps/ConsentEmblem.

/// The square's side and corner radius, and the mark's size on it.
const double kConsentEmblemSize = 64;
const double kConsentEmblemRadius = 20;
const double kConsentEmblemMarkSize = 36;

class ConsentEmblem extends ConsumerWidget {
  const ConsentEmblem({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.myazaColors;
    final config = ref.watch(verificationConfigProvider);
    final branding =
        ref.watch(kYCNotifierProvider.select((s) => s.serverConfig.branding));
    final whiteLabel = needsProcessorDisclosure(branding?.trustAttribution);

    final Widget child;
    if (!whiteLabel) {
      final mark = todenMarkColours(colors.background);
      child = TodenMark(
          size: kConsentEmblemMarkSize, ink: mark.ink, accent: mark.accent);
    } else {
      // The org's logo as the sheet's header resolves it: `appearance.logo`
      // 'default' is the server's branding logo, any other value a URL.
      final configured = config.appearance?.logo;
      // Unset is the organisation's logo, as 'default' is; '' is "None".
      final logo = configured == 'default' || configured == null
          ? rebaseServerUrl(branding?.logo,
              resolveBaseUrl(config.apiKey, devUrl: config.devUrl))
          : configured;
      final shield =
          UiIcon(UiIcons.shieldCheck, size: 32, color: colors.primary);
      child = logo == null || logo.isEmpty
          ? shield
          : Image.network(
              logo,
              width: kConsentEmblemMarkSize,
              height: kConsentEmblemMarkSize,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => shield,
            );
    }

    return ExcludeSemantics(
      child: Container(
        width: kConsentEmblemSize,
        height: kConsentEmblemSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: BorderRadius.circular(kConsentEmblemRadius),
        ),
        child: child,
      ),
    );
  }
}
