import '../screens/liveness_immersive.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/verification_config.dart';
import '../config/contact_recovery.dart' show contactBackShown;
import '../config/id_selection_layout.dart' show countryOnIdStep;
import '../config/session_cancelled.dart';
import '../config/session_declined.dart';
import '../config/appearance_scheme.dart';
import '../config/bright_screen.dart';
import '../config/theme.dart';
import '../liveness/liveness_types.dart';
import '../providers/verification_provider.dart';
import '../providers/verification_state.dart';
import '../providers/liveness_provider.dart';
import '../providers/step_order.dart';
import '../providers/theme_provider.dart';
import '../utils/portrait_lock.dart';
import 'verification_flow_scope.dart';
import 'flow_close.dart';
import 'flow_step_meta.dart';
import '../i18n/text_scope.dart';

export 'verification_flow_scope.dart' show verificationFlowOverrides;
import '../screens/applicant_role_screen.dart';
import '../screens/business_details_screen.dart';
import '../screens/business_documents_screen.dart';
import '../screens/supporting_documents_screen.dart';
import '../screens/business_key_people_screen.dart';
import '../screens/consent_screen.dart';
import '../screens/contact_verification_screen.dart';
import '../screens/country_select_screen.dart';
import '../screens/document_capture_screen.dart';
import '../screens/id_input_screen.dart';
import '../screens/id_type_screen.dart';
import '../screens/nfc_screen.dart';
import '../providers/business_documents_provider.dart';
import '../screens/address/address_book_step.dart';
import '../screens/address/address_entrance_step.dart';
import '../screens/address/address_pin_step.dart';
import '../screens/address/address_review_step.dart';
import '../screens/address/address_search_step.dart';
import '../screens/proof_of_address_screen.dart';
import '../screens/questionnaire_screen.dart';
import 'multi_id_progress.dart';
import 'ui_pulse_loader.dart';
import 'workflow_gate.dart';
import '../screens/liveness_screen.dart';
import '../screens/submitted_screen.dart';
import '../utils/resolve_url.dart';
import 'bright_screen_boost.dart';
import 'verification_bottom_sheet.dart';
import 'sandbox_banner.dart';
import 'ui_button.dart';
import '../config/verification_result.dart';
import '../services/model_readiness.dart';
import 'icons/icons.dart';
import '../config/scope.dart';

/// Maps the appearance's initial theme to a ThemeMode. Null appearance/theme
/// and the explicit `system` value both follow the device setting.
// The flow's opening theme mode and its ProviderScope overrides both live in
// verification_flow_scope.dart, so the biometric host can mount the same scope without
// importing this file (which imports it — see that file's header).

// ─── Public entry points ──────────────────────────────────────────────────────

/// Static launcher — shows the KYC flow as a full-screen modal bottom sheet.
///
/// The environment (and base URL) is derived automatically from the API key
/// prefix — `pk_live_…` → production, `pk_test_…` → sandbox, `pk_dev_…` →
/// development. There is no `environment` parameter.
///
/// ```dart
/// Verification.show(
///   context: context,
///   config: VerificationConfig(apiKey: 'pk_live_…', country: 'NG'),
///   onSubmit: (s) => print('Submitted: ${s.verificationId}'),
///   onError:  (e) => print('Error: ${e.code} — ${e.message}'),
/// );
/// ```
class Verification {
  Verification._();

  static Future<void> show({
    required BuildContext context,
    required VerificationConfig config,
    void Function(VerificationSubmission)? onSubmit,
    void Function(VerificationError)? onError,
    VoidCallback? onClose,

    /// The verdict, on a flow that waits for it in the app (a biometric
    /// re-authentication on the default delivery). See [VerificationResult].
    void Function(VerificationResult)? onResult,
  }) async {
    // Fail loud on an invalid key prefix before presenting anything (throws
    // ArgumentError with a clear message).
    detectEnvironment(config.apiKey);

    // Resolve-before-mount: a workflow-driven flow is resolved first (behind a
    // loading barrier), then merged over the props (flow wins). On failure the
    // gate surfaces the error and we don't open the flow.
    var effectiveConfig = config;
    ServerSdkConfig? preloaded;
    if (config.workflowId != null && config.workflowId!.trim().isNotEmpty) {
      final result = await resolveWorkflowBeforeMount(context, config, onError);
      if (result == null) return;
      effectiveConfig = result.config;
      preloaded = result.serverConfig;
    }
    if (!context.mounted) return;

    // `country` is optional on the config so a workflow mount doesn't have to
    // invent one — the resolved flow supplies it above. THIS is where that becomes
    // a guarantee: everything downstream reads `effectiveCountry`, which treats a
    // country as always present, so a config that reaches the flow without one
    // would surface as an empty ID-type list rather than a stated problem.
    //
    // Only reachable by misconfiguration: no `country` AND no `workflowId`, or a
    // resolved flow that somehow carries neither (publish rejects a country-less
    // KYC draft, and a KYB flow's country comes from its business block).
    if ((effectiveConfig.country ?? '').trim().isEmpty) {
      onError?.call(const VerificationError(
        code: 'unknown',
        message:
            'No country configured. Pass `country`, or a `workflowId` whose '
            'published flow carries one.',
      ));
      return;
    }

    // Shape + type from the RESOLVED appearance (so a workflow's branding wins
    // over props). Applied here, before the flow builds, because both are
    // module-level scales read during build — see UiRadius.applyScale.
    UiRadius.applyScale(effectiveConfig.appearance?.borderRadius);
    applyBrandFonts(
      body: effectiveConfig.appearance?.fontFamily,
      heading: effectiveConfig.appearance?.headingFontFamily,
    );

    final overrides = _overridesFor(effectiveConfig, preloaded);

    // Android: push a full-screen page modal.
    // iOS / other: show a draggable bottom sheet.
    if (Platform.isAndroid) {
      return Navigator.of(context, rootNavigator: true)
          .push<void>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (ctx) => ProviderScope(
                overrides: overrides,
                child: _VerificationFlowWidget(
                  isFullScreen: true,
                  onSubmit: onSubmit,
                  onError: onError,
                  onClose: onClose,
                  onResult: onResult,
                ),
              ),
            ),
          )
          .then((_) => onClose?.call());
    }

    // When the consumer disables close, the sheet can't be dragged down or
    // dismissed by tapping the barrier — only a programmatic pop closes it.
    final allowDismiss = !effectiveConfig.disableClose;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: allowDismiss,
      isDismissible: allowDismiss,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (ctx) => ProviderScope(
        overrides: overrides,
        child: _VerificationFlowWidget(
          isFullScreen: false,
          onSubmit: onSubmit,
          onError: onError,
          onClose: onClose,
          onResult: onResult,
        ),
      ),
    ).then((_) => onClose?.call());
  }

  /// The ProviderScope overrides that mount a flow with [effectiveConfig] and,
  /// when a workflow was resolved before mount, its preloaded server config.
  /// The list itself lives in verification_flow_scope.dart, which both hosts import.
  static List<Override> _overridesFor(
    VerificationConfig effectiveConfig,
    ServerSdkConfig? preloaded,
  ) =>
      verificationFlowOverrides(effectiveConfig, preloaded);
}

/// Embeddable widget version. Wrap in your own layout.
class VerificationWidget extends StatelessWidget {
  final VerificationConfig config;
  final void Function(VerificationSubmission)? onSubmit;
  final void Function(VerificationError)? onError;
  final VoidCallback? onClose;
  final void Function(VerificationResult)? onResult;

  const VerificationWidget({
    super.key,
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  Widget build(BuildContext context) {
    // Fail loud on an invalid key prefix (throws ArgumentError).
    detectEnvironment(config.apiKey);

    // Workflow-driven: resolve first, then mount with the merged config.
    if (config.workflowId != null && config.workflowId!.trim().isNotEmpty) {
      return _EmbeddedWorkflowGate(
        config: config,
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
        onResult: onResult,
      );
    }

    return ProviderScope(
      overrides: Verification._overridesFor(config, null),
      child: _VerificationFlowWidget(
        onSubmit: onSubmit,
        onError: onError,
        onClose: onClose,
        onResult: onResult,
      ),
    );
  }
}

// ─── Embedded workflow gate ───────────────────────────────────────────────────
//
// The embeddable widget's resolve-before-mount: while the workflow resolves it
// shows a loader; on success it mounts the flow with the merged config +
// preloaded server config; on failure it reports onError once and shows the
// error message inline (there's no modal to pop, unlike Verification.show).

class _EmbeddedWorkflowGate extends StatefulWidget {
  final VerificationConfig config;
  final void Function(VerificationSubmission)? onSubmit;
  final void Function(VerificationError)? onError;
  final VoidCallback? onClose;
  final void Function(VerificationResult)? onResult;

  const _EmbeddedWorkflowGate({
    required this.config,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  State<_EmbeddedWorkflowGate> createState() => _EmbeddedWorkflowGateState();
}

class _EmbeddedWorkflowGateState extends State<_EmbeddedWorkflowGate> {
  late final Future<WorkflowGateResult> _future;
  bool _errorReported = false;

  @override
  void initState() {
    super.initState();
    _future = resolveWorkflowResult(widget.config);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WorkflowGateResult>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(UiSpacing.xl),
              child: UiPulseLoader(),
            ),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          final verificationErr = err is VerificationError
              ? err
              : const VerificationError(
                  code: 'invalid_workflow',
                  message: 'This verification workflow could not be loaded.',
                );
          if (!_errorReported) {
            _errorReported = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => widget.onError?.call(verificationErr),
            );
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(UiSpacing.xl),
              child: Text(verificationErr.message, textAlign: TextAlign.center),
            ),
          );
        }
        final result = snap.data!;
        return ProviderScope(
          overrides:
              Verification._overridesFor(result.config, result.serverConfig),
          child: _VerificationFlowWidget(
            onSubmit: widget.onSubmit,
            onError: widget.onError,
            onClose: widget.onClose,
            onResult: widget.onResult,
          ),
        );
      },
    );
  }
}

// ─── Internal flow widget ─────────────────────────────────────────────────────

class _VerificationFlowWidget extends ConsumerStatefulWidget {
  final bool isFullScreen;
  final void Function(VerificationSubmission)? onSubmit;
  final void Function(VerificationError)? onError;
  final VoidCallback? onClose;
  final void Function(VerificationResult)? onResult;

  const _VerificationFlowWidget({
    this.isFullScreen = false,
    this.onSubmit,
    this.onError,
    this.onClose,
    this.onResult,
  });

  @override
  ConsumerState<_VerificationFlowWidget> createState() =>
      _VerificationFlowWidgetState();
}

class _VerificationFlowWidgetState
    extends ConsumerState<_VerificationFlowWidget> with PortraitLock {
  /// One stable key per step, so a step's State survives being REPARENTED.
  ///
  /// The full-bleed camera swaps the whole shell — sheet-with-chrome for a bare
  /// Scaffold — which puts the step screen at a different position in the tree.
  /// Without a GlobalKey, Flutter tears the old State down and builds a fresh
  /// one: the document step lost `_ready`, fell back to its primer, lowered the
  /// immersive flag, and the shell swapped straight back — a remount loop where
  /// the camera never opened at all.
  final _stepKeys = <VerificationStep, GlobalKey>{};

  /// The step screen itself, inside the multi-ID wrapper: see _screenWithMultiId.
  final _multiIdScreenKeys = <VerificationStep, GlobalKey>{};

  // Ensures a fatal config-load failure is reported to onError at most once.
  bool _configErrorReported = false;
  // Ensures a cancelled session is reported to onError at most once.
  bool _cancelReported = false;
  // And a declined one.
  bool _declineReported = false;

  @override
  void initState() {
    // PortraitLock pins the flow upright for its lifetime and restores the
    // host's orientations on close — see utils/portrait_lock.dart for why the
    // camera preview makes this load-bearing rather than cosmetic.
    super.initState();

    // On Android both on-device models are fetched by Play Services rather than
    // shipped in the app. Asking now lets the downloads overlap the first
    // screens, so the liveness step and the passport scanner rarely have to
    // wait. The text model is the larger one and is needed earlier. A no-op
    // off Android and once a model is on the phone.
    primeFaceModel();
    primeTextModel();
  }

  @override
  void dispose() {
    // The orientation release is PortraitLock's.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final config = ref.read(verificationConfigProvider);

    final step = state.currentStep;
    // Watched only on its own step: the back arrow walks its groups.
    final docGroup = step == VerificationStep.businessDocuments
        ? ref.watch(businessDocumentGroupIndexProvider)
        : 0;
    final supportingDoc = step == VerificationStep.supportingDocuments
        ? ref.watch(supportingDocumentIndexProvider)
        : 0;
    final meta = flowStepMeta(
      step,
      config: config,
      state: state,
      t: ref.watch(verificationTextProvider),
      selfieComplete: step == VerificationStep.liveness &&
          ref.watch(livenessNotifierProvider.select((s) => s.phase)) ==
              LivenessPhase.complete,
    );

    // ── Resolve theme ──────────────────────────────────────────────────────
    final themeMode = ref.watch(verificationThemeModeProvider);
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final userIsDark = themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system && systemBrightness == Brightness.dark);
    final baseScheme = userIsDark ? UiColorScheme.dark : UiColorScheme.light;
    // Fold in the dark overrides FIRST: the appearance is applied on top of the
    // active base scheme, so a light background would otherwise overwrite the
    // dark one and the toggle would do nothing on a branded flow.
    final userScheme = applyAppearance(
        baseScheme, config.appearance?.forBrightness(userIsDark));

    // ── Bright screen during liveness ──────────────────────────────────────
    // From the selfie camera screen to the end of the step, the screen is the
    // light on the face: the flow crosses into the organisation's LIGHT palette
    // and the screen is held at full brightness (config/bright_screen.dart).
    // The primers before the camera keep the normal theme. The person's own
    // theme comes back when the step is left; their toggle is hidden meanwhile.
    final brightScreen = livenessBrightScreenActive(
      enabled: config.livenessBrightScreen,
      onLivenessStep: step == VerificationStep.liveness,
      cameraOn: ref.watch(livenessCameraOnProvider),
    );
    final litScheme = brightScreenScheme(config.appearance);

    // ── Resolve org branding for the persistent header ─────────────────────
    // `appearance.logo = 'default'` pulls the org logo from the server config
    // response; any other value is a literal network URL. Falls back to the
    // local logoAsset, then to nothing.
    final appearance = config.appearance;
    final branding = state.serverConfig.branding;
    final appearanceLogo = appearance?.logo;
    // The server's `branding.logo` is absolute, built from its PUBLIC_SERVER_URL
    // — which can differ from the host the SDK reaches it on (a dev tunnel, a
    // LAN IP vs `.local`, …), so it may 404 on-device. Rebase it onto the URL
    // the SDK actually talks to; a consumer's literal `appearance.logo` URL is
    // used as-is.
    // An empty logo is the workflow's "None": no logo at all, not even the
    // app's own logoAsset (a workflow's appearance wins over the app's).
    final logoNone = appearanceLogo != null && appearanceLogo.isEmpty;
    // Unset is the organisation's logo, as 'default' is (decision
    // 2026-11-13), unless the app bundled its own [logoAsset].
    final useOrgLogo = appearanceLogo == 'default' ||
        (appearanceLogo == null && appearance?.logoAsset == null);
    final logoUrl = logoNone
        ? null
        : useOrgLogo
            ? rebaseServerUrl(
                branding?.logo,
                resolveBaseUrl(config.apiKey, devUrl: config.devUrl),
              )
            : appearanceLogo;
    final companyName = appearance?.companyName ?? branding?.companyName;

    void onToggleTheme() {
      final current = ref.read(verificationThemeModeProvider);
      final effective = current == ThemeMode.system
          ? (systemBrightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light)
          : current;
      ref.read(verificationThemeModeProvider.notifier).state =
          effective == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    }

    // ── Compute step info (progress fraction + total count) ───────────────
    final stepInfo = _computeStepInfo(state, config);
    final progress = stepInfo?.progress;

    // ── Back callback (null = hide back button) ────────────────────────────
    // Hidden on the flow's OPENING step (consent, or the first real step when
    // the workflow switched the consent screen off), not on consent by name.
    // A multi-ID run returns to the ID picker for its next check, where Back
    // means "redo the previous one", so a committed slot keeps the arrow.
    final opening = openingStep(config, serverConfig: state.serverConfig);
    final VoidCallback? onBack = switch (step) {
      VerificationStep.submitted => null, // terminal
      // The business documents step walks back through its groups first.
      VerificationStep.businessDocuments when docGroup > 0 => () => ref
          .read(businessDocumentGroupIndexProvider.notifier)
          .state = docGroup - 1,
      // So does the supporting documents step through its documents.
      VerificationStep.supportingDocuments when supportingDoc > 0 => () => ref
          .read(supportingDocumentIndexProvider.notifier)
          .state = supportingDoc - 1,
      _ when step == opening && state.multiIdSlots.isEmpty => null,
      // A contact step reached by recovering a refused submission has no Back.
      _ when !contactBackShown(step, state.expiredContact) => null,
      _ => notifier.previousStep,
    };

    // ── Prevent dismissal during submission, or when the consumer disables
    //    close (programmatic pop is then the only way out). ──────────────────
    // A cancelled or declined run has nothing left to protect, so it may
    // always be closed.
    final canDismiss = (step != VerificationStep.submitted ||
            state.sessionCancelledMessage != null ||
            state.sessionDeclined != null) &&
        !config.disableClose;

    // ── Fatal config-load failure (e.g. wrong API key) blocks the flow ─────
    // It replaces the normal step with a clear error screen, strips the
    // progress bar / back button, and reports the error to onError once.
    final serverConfig = state.serverConfig;
    // A business workflow with a biometric scope is refused outright: it
    // should never arrive (publish refuses it), and it must never open a
    // camera (config/scope.dart unsupportedScopeConfig).
    final unsupportedScope =
        unsupportedScopeConfig(config.subjectType, config.scope);
    final configError = unsupportedScope
        ? kUnsupportedScopeMessage
        : serverConfig.status == ServerConfigStatus.error && serverConfig.fatal
            ? (serverConfig.error ??
                'Unable to start verification. Please try again.')
            : null;
    if (configError != null && !_configErrorReported) {
      _configErrorReported = true;
      final verificationError = VerificationError(
        code: unsupportedScope
            ? 'invalid_workflow'
            : switch (serverConfig.statusCode) {
                401 => 'invalid_api_key',
                403 => 'feature_disabled',
                _ => 'unknown',
              },
        message: configError,
      );
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onError?.call(verificationError));
    }

    // ── Cancelled by the organisation (config/session_cancelled.dart) ─────
    // Terminal for this run: the same chrome-free blocking screen, with its
    // own title, and `session_cancelled` reported to onError once.
    final cancelledMessage =
        configError == null ? state.sessionCancelledMessage : null;
    if (cancelledMessage != null && !_cancelReported) {
      _cancelReported = true;
      final verificationError = VerificationError(
          code: kSessionCancelledCode, message: cancelledMessage);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onError?.call(verificationError));
    }

    // ── Declined by the server (config/session_declined.dart) ────────────
    // Exactly parallel: the same screen with the decline's own title, and
    // `session_declined` reported to onError once.
    final declined = configError == null && cancelledMessage == null
        ? state.sessionDeclined
        : null;
    if (declined != null && !_declineReported) {
      _declineReported = true;
      final verificationError = VerificationError(
          code: kSessionDeclinedCode, message: declined.message);
      WidgetsBinding.instance
          .addPostFrameCallback((_) => widget.onError?.call(verificationError));
    }
    final blockingMessage =
        configError ?? cancelledMessage ?? declined?.message;

    // ── Screen routing ────────────────────────────────────────────────────
    final screen = blockingMessage != null
        ? _ConfigErrorScreen(
            title: cancelledMessage != null
                ? kSessionCancelledTitle
                : declined?.title ?? 'Unable to start verification',
            icon: cancelledMessage != null || declined != null
                ? UiIcons.circleX
                : UiIcons.circleAlert,
            message: blockingMessage,
            onClose: () {
              widget.onClose?.call();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          )
        : _screenWithMultiId(step);

    // The flow's own close, for a full-screen screen a step opens over the
    // header (the photo camera): the header X's handler, or null exactly when
    // the header shows no X (widgets/flow_close.dart).
    final VoidCallback? flowClose = canDismiss
        ? () {
            widget.onClose?.call();
            final nav = Navigator.of(context);
            if (nav.canPop()) nav.pop();
          }
        : null;

    // Keyed so the SAME State moves between the two shells instead of being
    // rebuilt — see _stepKeys.
    final keyedScreen = blockingMessage != null
        ? screen
        : KeyedSubtree(
            key: _stepKeys.putIfAbsent(step, GlobalKey.new),
            child: FlowClose(onClose: flowClose, child: screen),
          );

    // Show the country flag beside the title on the ID-selection steps (the
    // effective country — the picked one in a multi-region flow).
    // On the combined layout the country row below names it; the header need
    // not repeat it.
    final headerCountry = blockingMessage == null &&
            (step == VerificationStep.idType ||
                step == VerificationStep.idInput) &&
            !(step == VerificationStep.idType &&
                countryOnIdTypeStep(config, state))
        ? effectiveCountry(config, state)
        : null;

    // The whole shell, painted in [colorScheme]: the person's own theme, the
    // lit one, or a frame of the crossing between them.
    Widget shell(
      UiColorScheme colorScheme,
      bool isDark,
      Color headerSurface,
    ) {
      final sheet = VerificationBottomSheet(
        environment: state.serverConfig.environment,
        title: blockingMessage != null ? '' : meta.title,
        description: blockingMessage != null ? null : meta.description,
        progress: blockingMessage != null ? null : progress,
        stepCount: blockingMessage != null ? null : stepInfo?.stepCount,
        onBack: blockingMessage != null ? null : onBack,
        onClose: widget.onClose,
        canDismiss: canDismiss,
        isFullScreen: widget.isFullScreen,
        isDark: isDark,
        headerSurface: headerSurface,
        // Only wire the toggle when the consumer opted in; a null callback hides
        // the button and keeps the flow on the appearance theme. Hidden too
        // while the bright screen holds the flow light: it could not act.
        onToggleTheme:
            config.showThemeToggle && !brightScreen ? onToggleTheme : null,
        progressStyle: config.progressStyle,
        // Hide the brand bar on a fatal config error — show a clean, chrome-free
        // error screen (just the theme/fullscreen controls), like the web SDK.
        logoUrl: blockingMessage != null ? null : logoUrl,
        logoAsset:
            blockingMessage != null || logoNone ? null : appearance?.logoAsset,
        companyName: blockingMessage != null ? null : companyName,
        trustAttribution:
            blockingMessage != null ? null : branding?.trustAttribution,
        country: headerCountry,
        // Which steps get the whole body instead of the shared scroll view: see
        // _fillsViewport.
        fillsViewport: blockingMessage == null && _fillsViewport(step),
        child: keyedScreen,
      );

      // ── Immersive capture ─────────────────────────────────────────────────
      // A camera step asks for the whole screen (state.immersiveCapture). The
      // sheet's header, padding and scroll view are what force a small viewfinder
      // on a short phone — and a camera you have to SCROLL to is a broken camera.
      // So the sheet is bypassed entirely: the screen owns the display, edge to
      // edge and behind the system bars, and draws its own back/close controls.
      // Scoped to the document step as well as the flag: if that step unmounts
      // while the flag is still raised, the NEXT step must not inherit a
      // chrome-free shell.
      // The liveness camera takes the screen the same way. It keeps the flow's
      // own colours (its blur is tinted with them), so it also keeps the
      // themed system bars, and the shell draws its back and close.
      final immersiveLiveness = blockingMessage == null &&
          state.immersiveCapture &&
          step == VerificationStep.liveness;
      final immersive = blockingMessage == null &&
          state.immersiveCapture &&
          step == VerificationStep.documentCapture;

      final overlayStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        // Bottom system-nav / gesture area uses the body background (not the
        // tinted header that the Scaffold paints behind the status bar).
        systemNavigationBarColor: colorScheme.background,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      );

      Widget themed(Widget child) => Theme(
            data: Theme.of(context).copyWith(extensions: [colorScheme]),
            child: child,
          );

      if (immersiveLiveness) {
        return themed(AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Scaffold(
            backgroundColor: colorScheme.background,
            body: Stack(
              fit: StackFit.expand,
              children: [
                LivenessOwnTheme(scheme: userScheme, child: keyedScreen),
                // In the person's OWN theme, not the lit one: on a dark flow
                // the bright screen is there to light the face, and two white
                // buttons are no part of that.
                Theme(
                  data: Theme.of(context).copyWith(extensions: [userScheme]),
                  child: LivenessImmersiveControls(
                    onBack: onBack,
                    // The same explicit close as the sheet's: tell the host,
                    // then pop past the step-back guard.
                    onClose: canDismiss
                        ? () {
                            widget.onClose?.call();
                            final nav = Navigator.of(context);
                            if (nav.canPop()) nav.pop();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ));
      }

      if (immersive) {
        return themed(AnnotatedRegion<SystemUiOverlayStyle>(
          // Light icons: the camera feed behind the status bar is dark.
          value: overlayStyle.copyWith(
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: Colors.black,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: Colors.black,
            // No SafeArea: the feed runs under the bars on purpose. The screen
            // insets its own controls.
            body: keyedScreen,
          ),
        ));
      }

      if (widget.isFullScreen) {
        return themed(AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlayStyle,
          child: Scaffold(
            // Body background fills the bottom system-nav/gesture inset, keeping
            // it the dark body colour. The status-bar inset is painted with the
            // header tint below so the top matches the header band.
            backgroundColor: colorScheme.background,
            body: Column(
              children: [
                // Strip behind the status bar. Normally the header tint so the
                // top matches the header band — but when the environment banner
                // is showing, the banner is what sits directly below, so the
                // strip takes ITS amber instead and the warning reads as one
                // unbroken band from the top of the screen (matching RN). Both
                // are translucent over the same Scaffold background, so the
                // composite is identical to the banner's own.
                Container(
                  height: MediaQuery.of(context).padding.top,
                  color: SandboxBanner.showsFor(state.serverConfig.environment)
                      ? SandboxBanner.tint
                      : headerSurface,
                ),
                Expanded(child: SafeArea(top: false, child: sheet)),
              ],
            ),
          ),
        ));
      }

      return themed(AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlayStyle,
        child: LayoutBuilder(
          builder: (ctx, _) {
            final sheetHeight = MediaQuery.of(context).size.height * 0.92;
            return SizedBox(height: sheetHeight, child: sheet);
          },
        ),
      ));
    }

    return BrightScreenBoost(
      active: brightScreen,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: brightScreen ? 1 : 0),
        duration: brightScreenTransition(
          disableAnimations: MediaQuery.disableAnimationsOf(context),
        ),
        curve: Curves.easeInOut,
        builder: (context, t, _) {
          final lit = blendBrightScreen(
            userScheme: userScheme,
            userIsDark: userIsDark,
            litScheme: litScheme,
            t: t,
          );
          return shell(lit.scheme, lit.isDark, lit.headerSurface);
        },
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Progress indicator, computed from the same `buildStepOrder` the navigation
  /// uses (single source of truth). The terminal `submitted` step is excluded
  /// from the count.
  ({double progress, int stepCount})? _computeStepInfo(
      VerificationState state, VerificationConfig config) {
    final step = state.currentStep;
    if (step == VerificationStep.submitted) return null;

    final steps = buildStepOrder(config, state)
        .where((s) => s != VerificationStep.submitted)
        .toList();
    final idx = steps.indexOf(step);
    if (idx < 0) return null;
    return (progress: (idx + 1) / steps.length, stepCount: steps.length);
  }

  /// The steps given the sheet's whole body instead of its shared scroll view.
  ///
  /// Country select owns its own scroll (pinned search + full-height list),
  /// matching the web SDK's flex-1 body. Document capture wants the full
  /// viewport too: it is about to go immersive, and on the frames before that
  /// flag flips it would otherwise render inside the scroll view with unbounded
  /// height, which the camera cannot lay out against. The address pin and
  /// entrance steps fill it as well: the map owns every touch, so Continue rides
  /// StickyActions at the bottom of a BOUNDED body rather than under a surface a
  /// short phone cannot scroll past.
  ///
  /// Every other step lays out inside the scroll view, so its height is
  /// unbounded and nothing wrapping its screen may flex it.
  static bool _fillsViewport(VerificationStep step) =>
      step == VerificationStep.countrySelect ||
      step == VerificationStep.documentCapture ||
      step == VerificationStep.addressCollection ||
      step == VerificationStep.addressEntrance;

  /// The steps a multi-ID run walks once PER ID — the ones whose screen is
  /// about one particular check and therefore need the position strip above.
  static const Set<VerificationStep> _multiIdSteps = {
    VerificationStep.idType,
    VerificationStep.idInput,
    VerificationStep.documentCapture,
    VerificationStep.nfc,
    VerificationStep.liveness,
  };

  /// Wraps a step's screen with the multi-ID position strip when a run is
  /// active, so a three-ID run is not three visits to the same-looking screen
  /// with nothing saying which is which.
  Widget _screenWithMultiId(VerificationStep step) {
    final plan = ref.read(kYCNotifierProvider.notifier).multiIdPlan();
    if (plan == null || !_multiIdSteps.contains(step)) {
      return _screenForStep(step);
    }
    // Keyed, because the liveness step sits under the strip in the sheet and
    // on its own once its camera takes the screen: without a key that move
    // would rebuild the step and restart the camera.
    final screen = KeyedSubtree(
      key: _multiIdScreenKeys.putIfAbsent(step, GlobalKey.new),
      child: _screenForStep(step),
    );
    // The full-screen liveness camera has no room for the strip, and no
    // bounded height to give a screen placed under it.
    if (step == VerificationStep.liveness &&
        ref.read(kYCNotifierProvider).immersiveCapture) {
      return screen;
    }
    // A step inside the sheet's scroll view has UNBOUNDED height, and an
    // Expanded cannot lay out there: a debug build asserts and paints nothing,
    // which left the multi-ID ID picker blank (2026-09-15; a release build skips
    // the assertion and happened to render). Only a step given the whole body
    // (document capture, whose immersive shell is bounded too) may flex its
    // screen under the strip.
    if (!_fillsViewport(step)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [MultiIdProgress(plan: plan), screen],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MultiIdProgress(plan: plan),
        Expanded(child: screen),
      ],
    );
  }

  Widget _screenForStep(VerificationStep step) => switch (step) {
        VerificationStep.consent => const ConsentScreen(),
        // Reached on a combined layout only from older state (a resumed run):
        // the ID-type step carries the country there.
        VerificationStep.countrySelect => countryOnIdStep(
                ref.read(verificationConfigProvider).idSelectionLayout)
            ? const IdTypeScreen()
            : const CountrySelectScreen(),
        VerificationStep.idType => const IdTypeScreen(),
        VerificationStep.documentCapture =>
          DocumentCaptureScreen(onError: widget.onError),
        VerificationStep.idInput => const IdInputScreen(),
        VerificationStep.liveness => LivenessScreen(onError: widget.onError),
        VerificationStep.submitted => SubmittedScreen(
            onSubmitted: widget.onSubmit,
            onError: widget.onError,
            onResult: widget.onResult,
            onDone: () {
              widget.onClose?.call();
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
          ),
        // Steps below are gated OFF in buildStepOrder until their workstreams
        // land (country-select WS3, questionnaire WS4, contact WS4.5, PoA WS5,
        // NFC Phase 2), so they're never routed to yet. Placeholder keeps the
        // switch exhaustive; each WS replaces its case with the real screen.
        VerificationStep.questionnaire => const QuestionnaireScreen(),
        VerificationStep.businessDetails => const BusinessDetailsScreen(),
        VerificationStep.businessKeyPeople => const BusinessKeyPeopleScreen(),
        VerificationStep.applicantRole => const ApplicantRoleScreen(),
        VerificationStep.businessDocuments => BusinessDocumentsScreen(
            onError: (e) => widget.onError?.call(
              e is VerificationError
                  ? e
                  : const VerificationError(
                      code: 'upload_failed',
                      message: 'Business document upload failed.'),
            ),
          ),
        VerificationStep.supportingDocuments => SupportingDocumentsScreen(
            onError: (e) => widget.onError?.call(
              e is VerificationError
                  ? e
                  : const VerificationError(
                      code: 'upload_failed',
                      message: 'Supporting document upload failed.'),
            ),
          ),
        VerificationStep.proofOfAddress => ProofOfAddressScreen(
            onError: (e) => widget.onError?.call(
                  e is VerificationError
                      ? e
                      : const VerificationError(
                          code: 'upload_failed',
                          message: 'Proof of address upload failed.'),
                )),
        // The address flow: find it, confirm it, show it, commit it. Each is a
        // real step in the order (see step_order.dart), so the progress bar
        // and the header's back arrow need nothing special here.
        VerificationStep.addressBook => const AddressBookStep(),
        VerificationStep.addressSearch => const AddressSearchStep(),
        VerificationStep.addressCollection => const AddressPinStep(),
        VerificationStep.addressEntrance => const AddressEntranceStep(),
        VerificationStep.addressReview => const AddressReviewStep(),
        // Both contact steps mount the SAME widget type, so without distinct
        // keys Flutter matches them by (runtimeType, key) and REUSES the State
        // across email → phone: the phone step would inherit the email step's
        // in-flight flags (stuck spinner), challenge id and destination.
        VerificationStep.contactEmail => const ContactVerificationScreen(
            key: ValueKey('contact-email'), channel: 'email'),
        VerificationStep.contactPhone => const ContactVerificationScreen(
            key: ValueKey('contact-phone'), channel: 'phone'),
        VerificationStep.nfc => const NfcScreen(),
      };
}

// ─── Config error screen ──────────────────────────────────────────────────────
//
// Shown when the SDK can't load its server config because of a fatal auth
// failure (e.g. a wrong API key). Blocks the flow so the user gets a clear
// message instead of a silently broken ID-type list. Mirrors the web SDK's
// ConfigErrorScreen and the styling of SubmittedScreen's error view.

class _ConfigErrorScreen extends StatelessWidget {
  final String title;
  final UiIconData icon;
  final String message;
  final VoidCallback onClose;

  const _ConfigErrorScreen({
    required this.title,
    required this.icon,
    required this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    // Mirrors the web SDK's ConfigErrorScreen: icon → title → message →
    // full-width Close button stacked as one vertically-centered group
    // (gap-6 / 24px between blocks, 4px within the text block), with a single
    // fade-in on the whole group.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: UiSpacing.md,
          vertical: UiSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Icon circle (80×80, destructive @10%), centered.
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: UiColors.error.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: UiIcon(
                  icon,
                  size: 40,
                  color: UiColors.error,
                ),
              ),
            ),
            const SizedBox(height: UiSpacing.lg),
            Text(
              title,
              style: text.heading2,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UiSpacing.xs),
            Text(
              message,
              style: text.bodyMedium.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: UiSpacing.lg),
            UiButton(label: 'Close', onPressed: onClose),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}
