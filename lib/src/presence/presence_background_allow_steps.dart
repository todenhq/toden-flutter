// What the phone shows after "Continue with automatic checks", in the OS's own words.
//
// The OS prompt cannot be retried, so the screen before it says exactly what to
// tap. That depends on the platform, on the Android version, and on whether
// location was already allowed: without it the OS asks for "while using" first,
// and only then for "all the time". Before Android 10 there is no "all the
// time" option at all; allowing location is the whole answer.
//
// English on purpose, like the rest of this screen: these name the OS's labels.
// Pure, and mirrors the React Native SDK's presence/background-allow-steps.ts;
// change both together.

class AllowSteps {
  const AllowSteps({required this.lead, required this.tap});

  final String lead;

  /// The OS's own label for the option to tap.
  final String tap;
}

const _willAsk = 'Next, your phone will ask. Tap:';

/// [androidApi] null reads as a current phone.
AllowSteps backgroundAllowSteps({
  required bool isIOS,
  int? androidApi,
  required bool foregroundGranted,
}) {
  if (isIOS) {
    return AllowSteps(
      lead: foregroundGranted
          ? _willAsk
          : 'Your phone will ask twice. First tap “Allow While Using App”, then:',
      tap: 'Change to Always Allow',
    );
  }
  if (androidApi != null && androidApi < 29) {
    return const AllowSteps(lead: _willAsk, tap: 'Allow');
  }
  if (androidApi == 29) {
    return AllowSteps(
      lead: foregroundGranted
          ? _willAsk
          : 'Your phone will ask twice. First tap “Allow only while using the app”, then:',
      tap: 'Allow all the time',
    );
  }
  return AllowSteps(
    lead: foregroundGranted
        ? 'Next, your phone opens its location settings. Choose:'
        : 'First tap “While using the app”. Your phone then opens its location settings. Choose:',
    tap: 'Allow all the time',
  );
}

/// Shown when the phone's answer could not be seen: where Settings has it.
AllowSteps backgroundSettingsSteps({required bool isIOS}) => AllowSteps(
      lead: 'If your phone didn’t ask, open Settings and set Location to:',
      tap: isIOS ? 'Always' : 'Allow all the time',
    );
