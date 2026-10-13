import 'package:hugeicons/hugeicons.dart';

import 'app_icon.dart';
import 'glyphs.dart';

export 'app_icon.dart';

/// Every icon the SDK draws, under the name the call site already used.
///
/// The names are Lucide's, which this SDK drew before the set changed. Keeping
/// them is what lets the web, React Native and Flutter SDKs stay in lockstep by
/// NAME rather than by glyph: `UiIcons.fingerprint` means the same thing in
/// all three, whatever each one renders it with.
///
/// Wherever the web SDK already carries an icon, the entry here resolves to the
/// SAME Hugeicons glyph, taken from its mapping through the set's own alias
/// table rather than guessed from the name. The rest were chosen by meaning
/// against the catalogue.
///
/// Adding one: add the constant, and add it to the web SDK's barrel under the
/// same name if that SDK draws it too. Nothing outside this directory may
/// import `package:hugeicons` directly - see icons_test.dart.
class UiIcons {
  UiIcons._();

  static const UiIconData arrowLeft = HugeIcons.strokeRoundedArrowLeft01;
  static const UiIconData arrowRight = HugeIcons.strokeRoundedArrowRight01;
  static const UiIconData badgeCheck = HugeIcons.strokeRoundedBadgeCheck;
  static const UiIconData bellRing = HugeIcons.strokeRoundedBellRing;
  static const UiIconData bookUser = HugeIcons.strokeRoundedBookUser;
  static const UiIconData building2 = HugeIcons.strokeRoundedBuilding02;
  static const UiIconData calendar = HugeIcons.strokeRoundedCalendar01;
  static const UiIconData camera = HugeIcons.strokeRoundedCamera01;
  static const UiIconData cameraOff = HugeIcons.strokeRoundedCameraOff01;
  static const UiIconData check = HugeIcons.strokeRoundedCheck;
  static const UiIconData chevronDown = HugeIcons.strokeRoundedChevronDown;
  static const UiIconData chevronRight = HugeIcons.strokeRoundedChevronRight;
  static const UiIconData circle = HugeIcons.strokeRoundedCircle;
  static const UiIconData circleAlert = HugeIcons.strokeRoundedAlertCircle;
  static const UiIconData circleCheck =
      HugeIcons.strokeRoundedCheckmarkCircle02;
  static const UiIconData circleDashed = HugeIcons.strokeRoundedCircleDashed;
  static const UiIconData circleHelp = HugeIcons.strokeRoundedHelpCircle;
  static const UiIconData circleX = HugeIcons.strokeRoundedCancelCircle;
  static const UiIconData contact = HugeIcons.strokeRoundedContact;
  static const UiIconData copy = HugeIcons.strokeRoundedCopy;
  static const UiIconData creditCard = HugeIcons.strokeRoundedCreditCard;
  static const UiIconData eye = HugeIcons.strokeRoundedEye;
  static const UiIconData eyeOff = HugeIcons.strokeRoundedEyeOff;
  static const UiIconData fileText = HugeIcons.strokeRoundedFile02;
  static const UiIconData filter = HugeIcons.strokeRoundedFilter;
  static const UiIconData fingerprint = HugeIcons.strokeRoundedFingerPrint;
  static const UiIconData flaskConical = HugeIcons.strokeRoundedFlaskConical;
  static const UiIconData glasses = HugeIcons.strokeRoundedGlasses;
  static const UiIconData globe = HugeIcons.strokeRoundedGlobe;
  static const UiIconData house = HugeIcons.strokeRoundedHome01;
  static const UiIconData idCard = HugeIcons.strokeRoundedIdentityCard;
  static const UiIconData image = HugeIcons.strokeRoundedImage01;
  static const UiIconData imageUp = HugeIcons.strokeRoundedImageUpload;
  static const UiIconData info = HugeIcons.strokeRoundedInformationCircle;
  static const UiIconData landmark = HugeIcons.strokeRoundedLandmark;
  static const UiIconData lightbulb = HugeIcons.strokeRoundedBulb;
  static const UiIconData locateFixed = HugeIcons.strokeRoundedGps02;
  static const UiIconData lock = HugeIcons.strokeRoundedLock;
  static const UiIconData mail = HugeIcons.strokeRoundedMail01;
  static const UiIconData mapPin = HugeIcons.strokeRoundedMapPin;
  static const UiIconData mapPinCheck =
      HugeIcons.strokeRoundedLocationCheck01;
  static const UiIconData mapPinHouse = HugeIcons.strokeRoundedMapPinHouse;
  static const UiIconData mapPinned = HugeIcons.strokeRoundedLocation02;
  // Hugeicons' Maximize02 is a PINCH GESTURE glyph (a hand), not the corner
  // arrows Lucide's `maximize2` describes. `strokeRoundedExpand` is the same
  // drawing the web SDK and the dashboard use for this.
  static const UiIconData maximize2 = HugeIcons.strokeRoundedExpand;
  static const UiIconData messageSquare = HugeIcons.strokeRoundedMessage01;
  // The counterpart of `maximize2`: the web SDK's `Minimize2` is this drawing.
  static const UiIconData minimize2 = HugeIcons.strokeRoundedCollapse;
  static const UiIconData minus = HugeIcons.strokeRoundedMinusSign;
  static const UiIconData moon = HugeIcons.strokeRoundedMoon;
  // Lucide's `moveLeft` is a LONG arrow: a full-width shaft with a small head.
  // Hugeicons has no equivalent — its MoveLeft is a MOVE affordance (an arrow
  // trailing a dot), ArrowLeft/ArrowLeft01 are bare chevrons with no shaft,
  // ArrowLeft03/05 run into a vertical bar, and the longest true arrow,
  // ArrowLeft02, spans only 13.5 of 24 units against Lucide's 20. So this one
  // glyph is drawn locally, exactly as the web SDK draws it.
  static const UiIconData moveLeft = kLongArrowLeft;
  static const UiIconData nfc = HugeIcons.strokeRoundedSmartphoneNfc;
  // The web SDK's `PenLine`: the mark for signing, and for editing a signature.
  static const UiIconData penLine = HugeIcons.strokeRoundedPenTool01;
  static const UiIconData pencil = HugeIcons.strokeRoundedPencil;
  static const UiIconData pencilLine = HugeIcons.strokeRoundedPencilEdit01;
  static const UiIconData plus = HugeIcons.strokeRoundedAdd01;
  static const UiIconData radar = HugeIcons.strokeRoundedRadar01;
  static const UiIconData receiptText = HugeIcons.strokeRoundedReceiptText;
  static const UiIconData refreshCcw = HugeIcons.strokeRoundedRefresh;
  static const UiIconData refreshCw = HugeIcons.strokeRoundedRefreshCw;
  // Lucide's `rotateCcw` is a circular arrow. Hugeicons' RotateLeft01 is a
  // HAND rotating an object, so every Retake and retry control drew a hand.
  // Same drawing as `refreshCcw`, which is the plain circular arrow, and the
  // same fix the web SDK takes.
  static const UiIconData rotateCcw = HugeIcons.strokeRoundedRefresh;
  static const UiIconData scan = HugeIcons.strokeRoundedScan;
  static const UiIconData scanFace = HugeIcons.strokeRoundedFaceId;
  static const UiIconData scanLine = HugeIcons.strokeRoundedScan;
  static const UiIconData search = HugeIcons.strokeRoundedSearch01;
  static const UiIconData share2 = HugeIcons.strokeRoundedShare01;
  static const UiIconData shieldCheck = HugeIcons.strokeRoundedSecurityCheck;
  static const UiIconData slidersHorizontal =
      HugeIcons.strokeRoundedSlidersHorizontal;
  static const UiIconData smartphone = HugeIcons.strokeRoundedSmartPhone01;
  static const UiIconData stamp = HugeIcons.strokeRoundedStamp;
  static const UiIconData sparkles = HugeIcons.strokeRoundedSparkles;
  static const UiIconData sun = HugeIcons.strokeRoundedSun01;
  static const UiIconData timer = HugeIcons.strokeRoundedTimer01;
  static const UiIconData triangleAlert = HugeIcons.strokeRoundedAlert01;
  static const UiIconData type = HugeIcons.strokeRoundedText;
  static const UiIconData upload = HugeIcons.strokeRoundedUpload01;
  static const UiIconData user = HugeIcons.strokeRoundedUser;
  static const UiIconData userRound = HugeIcons.strokeRoundedUserCircle;
  static const UiIconData userRoundPlus = HugeIcons.strokeRoundedUserAdd01;
  static const UiIconData usersRound = HugeIcons.strokeRoundedUserGroup;
  static const UiIconData videoOff = HugeIcons.strokeRoundedVideoOff;
  static const UiIconData x = HugeIcons.strokeRoundedCancel01;
  static const UiIconData zap = HugeIcons.strokeRoundedFlash;
  static const UiIconData zapOff = HugeIcons.strokeRoundedFlashOff;
}
