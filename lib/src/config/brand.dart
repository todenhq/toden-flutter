import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vendor brand constants for the SDK's own attribution — NOT the integrating
/// org's branding (that comes from `/api/v1/config`).
///
/// The platform is **Toden** (it was Myaza Trust).
const String kProductName = 'Toden';

/// The product site — where "who are these people?" gets answered.
const String kProductUrl = 'https://toden.co';

/// Package name — required by `Image.asset(..., package:)` so the wordmark
/// resolves from THIS package's bundle rather than the host app's.
const String kPackageName = 'myaza_kyc_sdk_flutter';

/// The Toden logo (the split-shield T beside "toden"). The ink flips with the
/// surface and the shield's purple half steps lighter on dark, so there are two
/// files rather than a tint. Rendered from kyc-dashboard's logo.svg.
const String kWordmarkAssetLight = 'assets/brand/toden-wordmark-light.png';
const String kWordmarkAssetDark = 'assets/brand/toden-wordmark-dark.png';

/// End-user legal documents referenced by the consent screen. These are MYAZA's
/// terms — the person consents to us processing their data as the verification
/// provider — so they are never org-overridable.
///
/// Tappable on the consent screen, via `url_launcher`. The plugin is a real
/// cost to every integrator, taken deliberately: consent given by tapping
/// Continue is only INFORMED if the documents it references can be opened, and
/// a printed address the user must retype is a poor substitute for that.
const String kTermsUrl = 'https://toden.co/legal/terms';
const String kPrivacyUrl = 'https://toden.co/legal/privacy';

/// Version of the consent wording. Consent is given by ACTING (tapping
/// Continue) rather than ticking a box, so bump this whenever the copy changes
/// materially and store it with the verification — otherwise nothing proves
/// which disclosure was on screen. Keep in step with the web SDK's value.
const String kConsentVersion = '2026-10-12.1';

/// Tones the footer mark may use — the design system's INK and LIGHT text
/// colours, not the brand purple.
///
/// Attribution, not advertising. A saturated purple mark is the loudest thing in
/// the footer on an org whose palette is yellow or green: it draws the eye to
/// the least important element on screen and reads as a clash rather than a
/// signature. Every comparable vendor mark is monochrome for the same reason.
///
/// Nothing is lost by it — the logo ASSET keeps the shield's purple half, so
/// the Toden identity is still carried by the logo while the text recedes.
///
/// Mirrors the web and React Native SDKs — keep the list and the rule in step.
const List<Color> _markTones = [
  Color(0xFF080A12),
  Color(0xFFF6F5FE),
];

/// WCAG AA for the small text this renders at.
const double _minMarkContrast = 4.5;

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// The mark tone that stays legible on [background].
///
/// The footer mark must NOT follow the org's palette: it is our attribution, and
/// an org whose brand sits close to ours would otherwise get a mark that either
/// stops reading as ours or vanishes into the background. Chosen by CONTRAST
/// rather than by light/dark, because an org can set any background — including
/// mid-tones where neither variant is obviously right.
///
/// Falls back to the most visible tone when none clears AA, so the answer is
/// always the best available rather than a fixed guess.
Color brandMarkColor(Color background) {
  for (final tone in _markTones) {
    if (_contrastRatio(tone, background) >= _minMarkContrast) return tone;
  }
  return _markTones.reduce(
    (best, tone) => _contrastRatio(tone, background) > _contrastRatio(best, background)
        ? tone
        : best,
  );
}
