// The names this package first shipped under. They still work and point
// at the current ones, so an existing integration upgrades with no code
// change. New code should use the current names.

import 'config/verification_config.dart';
import 'config/verification_result.dart';
import 'providers/verification_state.dart';
import 'widgets/verification_bottom_sheet.dart';
import 'config/theme.dart';
import 'presence/background_presence.dart';
import 'presence/foreground_presence.dart';
import 'presence/presence_reporter.dart';
import 'widgets/ui_alert.dart';
import 'widgets/ui_button.dart';
import 'widgets/ui_card.dart';
import 'widgets/ui_input.dart';
import 'widgets/verification_widget.dart';

@Deprecated('Use Verification')
typedef MyazaKYC = Verification;
@Deprecated('Use VerificationWidget')
typedef MyazaKYCWidget = VerificationWidget;
@Deprecated('Use VerificationConfig')
typedef MyazaKYCConfig = VerificationConfig;
@Deprecated('Use VerificationAppearance')
typedef MyazaKYCAppearance = VerificationAppearance;
@Deprecated('Use VerificationThemeMode')
typedef MyazaThemeMode = VerificationThemeMode;
@Deprecated('Use VerificationProgressStyle')
typedef MyazaProgressStyle = VerificationProgressStyle;

@Deprecated('Use AddressPresence')
typedef MyazaAddressPresence = AddressPresence;
@Deprecated('Use BackgroundPresence')
typedef MyazaBackgroundPresence = BackgroundPresence;
@Deprecated('Use PresenceService')
typedef MyazaPresenceService = PresenceService;

@Deprecated('Use UiColors')
typedef MyazaColors = UiColors;
@Deprecated('Use UiTypography')
typedef MyazaTypography = UiTypography;
@Deprecated('Use UiRadius')
typedef MyazaRadius = UiRadius;
@Deprecated('Use UiSpacing')
typedef MyazaSpacing = UiSpacing;
@Deprecated('Use UiSizing')
typedef MyazaSizing = UiSizing;
@Deprecated('Use UiButton')
typedef MyazaButton = UiButton;
@Deprecated('Use UiButtonVariant')
typedef MyazaButtonVariant = UiButtonVariant;
@Deprecated('Use UiInput')
typedef MyazaInput = UiInput;
@Deprecated('Use UiCard')
typedef MyazaCard = UiCard;
@Deprecated('Use UiAlert')
typedef MyazaAlert = UiAlert;
@Deprecated('Use UiAlertVariant')
typedef MyazaAlertVariant = UiAlertVariant;

@Deprecated('Use VerificationConsentContent')
typedef KYCConsentContent = VerificationConsentContent;
@Deprecated('Use VerificationSuccessContent')
typedef KYCSuccessContent = VerificationSuccessContent;
@Deprecated('Use VerificationError')
typedef KYCError = VerificationError;
@Deprecated('Use VerificationSubmission')
typedef KYCSubmission = VerificationSubmission;
@Deprecated('Use VerificationResult')
typedef KYCResult = VerificationResult;
@Deprecated('Use VerificationStep')
typedef KYCStep = VerificationStep;
@Deprecated('Use VerificationState')
typedef KYCState = VerificationState;
@Deprecated('Use VerificationMediaIds')
typedef KYCMediaIds = VerificationMediaIds;
@Deprecated('Use VerificationSubmissionResult')
typedef KYCSubmissionResult = VerificationSubmissionResult;
@Deprecated('Use VerificationBottomSheet')
typedef KycBottomSheet = VerificationBottomSheet;
