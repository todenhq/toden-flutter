import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'body_font.dart';

// ─── Theme-aware color scheme (ThemeExtension) ───────────────────────────────
//
// Inject via Theme.of(context).extensions.
// Access via context.myazaColors (extension below).

class UiColorScheme extends ThemeExtension<UiColorScheme> {
  final Color background;
  final Color backgroundSecondary;
  final Color textDark;
  final Color textSecondary;
  final Color textMuted;
  final Color border;
  final Color primary;
  /// Text/icon color rendered on top of [primary] (e.g. button labels).
  final Color onPrimary;
  final Color primary50;
  final Color primary100;
  final Color primary200;
  final Color gray300;
  final Color gray400;
  final Color successBg;
  final Color errorBg;
  final Color warningBg;
  final Color infoBg;

  const UiColorScheme({
    required this.background,
    required this.backgroundSecondary,
    required this.textDark,
    required this.textSecondary,
    required this.textMuted,
    required this.border,
    required this.primary,
    required this.onPrimary,
    required this.primary50,
    required this.primary100,
    required this.primary200,
    required this.gray300,
    required this.gray400,
    required this.successBg,
    required this.errorBg,
    required this.warningBg,
    required this.infoBg,
  });

  // ── Light ──────────────────────────────────────────────────────────────────

  static const UiColorScheme light = UiColorScheme(
    background:          Color(0xFFFFFFFF),
    backgroundSecondary: Color(0xFFF3F5F9),
    textDark:            Color(0xFF121522),
    textSecondary:       Color(0xFF646C7D),
    // React's muted-foreground, exactly. The mobile SDKs had invented a THIRD,
    // dimmer text tier that web does not have, and it failed WCAG AA in both
    // modes: 3.79:1 on white and 2.97:1 on the default dark, dropping to
    // 2.45:1 on the dark backgrounds orgs actually brand with. Nothing is
    // gained by a tier nobody can read, so it takes the same value as the tier
    // above it, the way web does with one token for both.
    textMuted:           Color(0xFF646C7D),
    border:              Color(0xFFDFE3EA),
    primary:             Color(0xFF5645F5),
    onPrimary:           Color(0xFFFFFFFF),
    primary50:           Color(0xFFF6F5FE),
    primary100:          Color(0xFFE9E7FE),
    primary200:          Color(0xFFD3CFFC),
    gray300:             Color(0xFFCDD2DC),
    gray400:             Color(0xFFB8BDC8),
    successBg:           Color(0xFFD8F4DC),
    errorBg:             Color(0xFFFCD8D8),
    warningBg:           Color(0xFFFFF1D6),
    infoBg:              Color(0xFFC8E9FF),
  );

  // ── Dark ───────────────────────────────────────────────────────────────────

  static const UiColorScheme dark = UiColorScheme(
    background:          Color(0xFF080A12),
    backgroundSecondary: Color(0xFF191E2E),
    textDark:            Color(0xFFF6F5FE),
    textSecondary:       Color(0xFF858B9F),
    textMuted:           Color(0xFF858B9F),
    border:              Color(0xFF262B3A),
    primary:             Color(0xFF7B6EF7),
    onPrimary:           Color(0xFFFFFFFF),
    primary50:           Color(0xFF1A1730),
    primary100:          Color(0xFF2A2651),
    primary200:          Color(0xFF3D3870),
    gray300:             Color(0xFF262B3A),
    gray400:             Color(0xFF646C7D),
    successBg:           Color(0xFF0B2B0C),
    errorBg:             Color(0xFF2B0A0A),
    warningBg:           Color(0xFF2B1B00),
    infoBg:              Color(0xFF001B3B),
  );

  // ── ThemeExtension impl ────────────────────────────────────────────────────

  @override
  UiColorScheme copyWith({
    Color? background,
    Color? backgroundSecondary,
    Color? textDark,
    Color? textSecondary,
    Color? textMuted,
    Color? border,
    Color? primary,
    Color? onPrimary,
    Color? primary50,
    Color? primary100,
    Color? primary200,
    Color? gray300,
    Color? gray400,
    Color? successBg,
    Color? errorBg,
    Color? warningBg,
    Color? infoBg,
  }) => UiColorScheme(
    background:          background          ?? this.background,
    backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
    textDark:            textDark            ?? this.textDark,
    textSecondary:       textSecondary       ?? this.textSecondary,
    textMuted:           textMuted           ?? this.textMuted,
    border:              border              ?? this.border,
    primary:             primary             ?? this.primary,
    onPrimary:           onPrimary           ?? this.onPrimary,
    primary50:           primary50           ?? this.primary50,
    primary100:          primary100          ?? this.primary100,
    primary200:          primary200          ?? this.primary200,
    gray300:             gray300             ?? this.gray300,
    gray400:             gray400             ?? this.gray400,
    successBg:           successBg           ?? this.successBg,
    errorBg:             errorBg             ?? this.errorBg,
    warningBg:           warningBg           ?? this.warningBg,
    infoBg:              infoBg              ?? this.infoBg,
  );

  @override
  UiColorScheme lerp(UiColorScheme? other, double t) {
    if (other == null) return this;
    return UiColorScheme(
      background:          Color.lerp(background,          other.background,          t)!,
      backgroundSecondary: Color.lerp(backgroundSecondary, other.backgroundSecondary, t)!,
      textDark:            Color.lerp(textDark,            other.textDark,            t)!,
      textSecondary:       Color.lerp(textSecondary,       other.textSecondary,       t)!,
      textMuted:           Color.lerp(textMuted,           other.textMuted,           t)!,
      border:              Color.lerp(border,              other.border,              t)!,
      primary:             Color.lerp(primary,             other.primary,             t)!,
      onPrimary:           Color.lerp(onPrimary,           other.onPrimary,           t)!,
      primary50:           Color.lerp(primary50,           other.primary50,           t)!,
      primary100:          Color.lerp(primary100,          other.primary100,          t)!,
      primary200:          Color.lerp(primary200,          other.primary200,          t)!,
      gray300:             Color.lerp(gray300,             other.gray300,             t)!,
      gray400:             Color.lerp(gray400,             other.gray400,             t)!,
      successBg:           Color.lerp(successBg,           other.successBg,           t)!,
      errorBg:             Color.lerp(errorBg,             other.errorBg,             t)!,
      warningBg:           Color.lerp(warningBg,           other.warningBg,           t)!,
      infoBg:              Color.lerp(infoBg,              other.infoBg,              t)!,
    );
  }
}

// ─── Header surface tint ──────────────────────────────────────────────────────

/// Surface tint for the KYC header chrome (brand + title + step indicator).
///
/// Both themes use the secondary surface, the colour the cards below it use.
/// Dark themes used a wash of the brand colour over the background, which read
/// as a pale purple band above grey cards. Used by both the sheet header block
/// and the full-screen Scaffold (status-bar area) so they stay in sync.
/// [isDark] is kept so callers need not change.
Color verificationHeaderSurface(UiColorScheme colors, {required bool isDark}) =>
    colors.backgroundSecondary;

// ─── Sheet grab handle ────────────────────────────────────────────────────────

/// The colour of a sheet's grab handle.
///
/// A grabber has to be SEEN to be used. The dark palette's `gray300` and
/// `border` share one value, about 1.4:1 against the dark sheet surfaces,
/// so on dark themes the handle all but vanished. There it is drawn in the
/// scheme's own text colour at 40%, which stays around 3:1 or better on any
/// dark surface an org brands (the way the system grabber works). Light
/// themes keep the colour the caller already used.
Color myazaHandleColor(UiColorScheme colors, {required Color light}) {
  final isDark = colors.background.computeLuminance() < 0.5;
  return isDark ? colors.textDark.withValues(alpha: 0.4) : light;
}

// ─── BuildContext extensions ──────────────────────────────────────────────────

extension UiBuildContextTheme on BuildContext {
  /// Returns the current Myaza color scheme (light or dark).
  UiColorScheme get myazaColors =>
      Theme.of(this).extension<UiColorScheme>() ?? UiColorScheme.light;

  /// Returns typography styles tinted with the current theme colors.
  UiThemeText get myazaText => UiThemeText(myazaColors);
}


// ─── Brand fonts ──────────────────────────────────────────────────────────────

/// Body / heading families from `appearance`. Mutable globals for the same
/// reason UiRadius is: one flow on screen at a time, set once from the
/// resolved config before the flow builds, and the alternative is threading a
/// second ThemeExtension through every text style.
String? _bodyFontFamily;
String? _headingFontFamily;

void applyBrandFonts({String? body, String? heading}) {
  _bodyFontFamily = (body ?? '').trim().isEmpty ? null : body!.trim();
  final h = (heading ?? '').trim();
  _headingFontFamily = h.isEmpty ? _bodyFontFamily : h;
}

/// Resolve one text style, honouring an org font when set.
///
/// `GoogleFonts.getFont` THROWS for a family it doesn't know, so it is guarded:
/// an unrecognised name falls back to a plain `TextStyle(fontFamily:)`, which
/// resolves against fonts the HOST APP has bundled. So a Google font works by
/// name, a self-hosted brand font works if the app registered it, and anything
/// else lands on the SDK default instead of crashing a verification flow.
TextStyle _brandFont(
  String? family,
  TextStyle Function(TextStyle) fallback,
  TextStyle base,
) {
  if (family == null) return fallback(base);
  try {
    return GoogleFonts.getFont(family, textStyle: base);
  } catch (_) {
    return base.copyWith(fontFamily: family);
  }
}

// ─── Theme-aware text styles ──────────────────────────────────────────────────

class UiThemeText {
  final UiColorScheme _colors;

  const UiThemeText(this._colors);

  TextStyle get heading1 => _brandFont(
    _headingFontFamily,
    headingFont,
    TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _colors.textDark),
  );

  TextStyle get heading2 => _brandFont(
    _headingFontFamily,
    headingFont,
    TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: _colors.textDark),
  );

  TextStyle get heading3 => _brandFont(
    _headingFontFamily,
    headingFont,
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _colors.textDark),
  );

  // The type rule: 16px and up is Bricolage Grotesque, smaller text and form
  // fields are Geist. An org's own body font still wins everywhere.
  TextStyle get body => _brandFont(
    _bodyFontFamily,
    headingFont,
    TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: _colors.textDark),
  );

  /// Text typed into a field. 16px like [body], but Geist: form fields stay in
  /// the interface font.
  TextStyle get input => _brandFont(
    _bodyFontFamily,
    bodyFont,
    TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: _colors.textDark),
  );

  TextStyle get bodyMedium => _brandFont(
    _bodyFontFamily,
    bodyFont,
    TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: _colors.textSecondary),
  );

  TextStyle get bodySmall => _brandFont(
    _bodyFontFamily,
    bodyFont,
    TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: _colors.textMuted),
  );

  TextStyle get button => _brandFont(
    _bodyFontFamily,
    headingFont,
    TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _colors.onPrimary),
  );

  TextStyle get label => _brandFont(
    _bodyFontFamily,
    bodyFont,
    TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _colors.textDark),
  );
}

// ─── Colors ───────────────────────────────────────────────────────────────────

class UiColors {
  UiColors._();

  // Primary — Myaza Purple
  static const Color primary = Color(0xFF5645F5); // PC-09 Main
  static const Color primaryDark = Color(0xFF1F156F);
  static const Color primary50 = Color(0xFFF6F5FE);
  static const Color primary100 = Color(0xFFE9E7FE);
  static const Color primary200 = Color(0xFFD3CFFC);
  static const Color primary300 = Color(0xFFBDB6FB);
  static const Color primary400 = Color(0xFFA6B8FA);
  static const Color primary500 = Color(0xFF9986F9);
  static const Color primary600 = Color(0xFF7B6EF7);
  static const Color primary700 = Color(0xFF6455F6);
  static const Color primary800 = Color(0xFF5B47F5);
  static const Color primary900 = Color(0xFF3A25F4);
  static const Color primary950 = Color(0xFF2400F2);

  // Secondary — Gold
  static const Color secondary = Color(0xFFF4B746); // SC-06 Main
  static const Color secondary50 = Color(0xFFFDF1DA);
  static const Color secondary100 = Color(0xFFFBE7C1);
  static const Color secondary200 = Color(0xFFFADBA2);
  static const Color secondary500 = Color(0xFFF4B746);
  static const Color secondary900 = Color(0xFF513D17);

  // Text
  static const Color textDark = Color(0xFF121522);
  static const Color textLight = Color(0xFFF6F5FE);
  static const Color textSecondary = Color(0xFF646C7D);
  static const Color textMuted = Color(0xFF858B9F);

  // Status
  static const Color success = Color(0xFF0DA211);
  static const Color successBg = Color(0xFFD8F4DC);
  static const Color error = Color(0xFFBD1B09);
  static const Color errorBg = Color(0xFFFCD8D8);
  static const Color warning = Color(0xFFFFC107);
  static const Color warningBg = Color(0xFFFFF1D6);
  static const Color info = Color(0xFF004FAF);
  static const Color infoBg = Color(0xFFC8E9FF);

  // Grays
  static const Color gray50 = Color(0xFFF7F8FB);
  static const Color gray100 = Color(0xFFF3F5F9);
  static const Color gray200 = Color(0xFFDFE3EA);
  static const Color gray300 = Color(0xFFCDD2DC);
  static const Color gray400 = Color(0xFFB8BDC8);
  static const Color gray500 = Color(0xFF858B9F);
  static const Color gray600 = Color(0xFF646C7D);
  static const Color gray700 = Color(0xFF444B5C);
  static const Color gray800 = Color(0xFF121522);

  // Borders
  static const Color border = Color(0xFFDFE3EA);

  // Background
  static const Color background = Color(0xFFFFFFFF);
  static const Color backgroundSecondary = Color(0xFFF3F5F9);
}

// ─── Typography ───────────────────────────────────────────────────────────────

class UiTypography {
  UiTypography._();

  // GETTERS, not fields. A `static TextStyle x = …` initializer runs once on
  // first access and caches — which would freeze whatever font was configured
  // at that instant, and `applyBrandFonts` runs when a flow launches. Getters
  // re-resolve every read, so a brand font applies even to a screen that was
  // already touched.

  static TextStyle get heading1 => _brandFont(
    _headingFontFamily,
    headingFont,
    const TextStyle(fontSize: 24,
    fontWeight: FontWeight.w700,
    color: UiColors.textDark),
  );

  static TextStyle get heading2 => _brandFont(
    _headingFontFamily,
    headingFont,
    const TextStyle(fontSize: 20,
    fontWeight: FontWeight.w600,
    color: UiColors.textDark),
  );

  static TextStyle get heading3 => _brandFont(
    _headingFontFamily,
    headingFont,
    const TextStyle(fontSize: 16,
    fontWeight: FontWeight.w600,
    color: UiColors.textDark),
  );

  static TextStyle get body => _brandFont(
    _bodyFontFamily,
    headingFont,
    const TextStyle(fontSize: 16,
    fontWeight: FontWeight.w400,
    color: UiColors.textDark),
  );

  static TextStyle get bodyMedium => _brandFont(
    _bodyFontFamily,
    bodyFont,
    const TextStyle(fontSize: 14,
    fontWeight: FontWeight.w400,
    color: UiColors.textSecondary),
  );

  static TextStyle get bodySmall => _brandFont(
    _bodyFontFamily,
    bodyFont,
    const TextStyle(fontSize: 12,
    fontWeight: FontWeight.w400,
    color: UiColors.textMuted),
  );

  static TextStyle get button => _brandFont(
    _bodyFontFamily,
    headingFont,
    const TextStyle(fontSize: 16,
    fontWeight: FontWeight.w600,
    color: Colors.white),
  );

  static TextStyle get label => _brandFont(
    _bodyFontFamily,
    bodyFont,
    const TextStyle(fontSize: 14,
    fontWeight: FontWeight.w500,
    color: UiColors.textDark),
  );
}

// ─── Radius ───────────────────────────────────────────────────────────────────

class UiRadius {
  UiRadius._();

  /// The shipped scale, and the basis every override is derived from.
  static const double _dxs = 8.0;
  static const double _dsm = 12.0;
  static const double _dmd = 16.0;
  static const double _dlg = 20.0;
  static const double _dxl = 24.0;

  /// NON-const so `appearance.borderRadius` can scale them.
  ///
  /// A mutable global is a real trade-off, taken deliberately: 58 call sites
  /// read `UiRadius.md` directly, and threading a ThemeExtension through all
  /// of them buys nothing here — exactly one KYC flow is on screen at a time, and
  /// the scale is set once from the resolved config before that flow builds. The
  /// alternative (a 58-site refactor) carries far more risk than this does.
  static double xs = _dxs;
  static double sm = _dsm;
  static double md = _dmd;
  static double lg = _dlg;
  static double xl = _dxl;

  /// `sm` (12) is the base — what buttons, inputs and cards use — so it is the
  /// rung a consumer is choosing when they say "our corners are 4px". The scale
  /// moves proportionally, keeping a card rounder than an input at every setting.
  ///
  /// [full] is deliberately untouched: it renders avatars and the camera oval,
  /// and scaling it turns circles into squircles.
  static void applyScale(double? base) {
    final b = base == null ? _dsm : base.clamp(0.0, 32.0);
    final ratio = b / _dsm;
    xs = _dxs * ratio;
    sm = _dsm * ratio;
    md = _dmd * ratio;
    lg = _dlg * ratio;
    xl = _dxl * ratio;
  }
  static const double full = 999.0;
}

// ─── Spacing ─────────────────────────────────────────────────────────────────

class UiSpacing {
  UiSpacing._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

// ─── Sizing ──────────────────────────────────────────────────────────────────

class UiSizing {
  UiSizing._();

  static const double buttonHeight = 48.0;
  static const double inputHeight = 48.0;
  static const double iconSize = 24.0;
  static const double avatarSize = 80.0;
  static const double cameraCircleSize = 260.0;
}
