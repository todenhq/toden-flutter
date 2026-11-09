import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/biometric_copy.dart';
import '../config/biometric_options.dart';
import '../config/verification_config.dart';
import '../config/verification_result.dart';
import '../config/result_copy.dart';
import '../config/scope.dart';
import '../config/selfie_upload_wait.dart';
import '../config/session_cancelled.dart';
import '../config/theme.dart';
import '../config/contact_recovery.dart';
import '../config/submit_recovery.dart';
import '../providers/step_order.dart' show buildStepOrder;
import '../providers/verification_state.dart';
import 'submitted_error_view.dart';
import 'submitted_result_view.dart';
import 'submitted_waiting_view.dart';
import '../widgets/check_badge.dart';
import '../providers/verification_provider.dart';
import '../services/api_service.dart';
import '../services/verification_error_mapper.dart';
import '../widgets/keep_links_sheet.dart';
import '../widgets/key_people_await_list.dart';
import '../widgets/presence_blocks.dart';
import '../providers/awaiting_people.dart';
import '../presence/background_ask_controller.dart';
import 'background_ask_screen.dart';
import '../presence/presence_background_primer.dart';
import '../widgets/ui_button.dart';
import '../i18n/text_scope.dart';
import '../widgets/key_people_ownership_note.dart';

// ─── Submission status (local UI state) ──────────────────────────────────────

// background: the "allow all the time" screen (presence_background_primer.dart).
enum _SubmitStatus { submitting, background, success, error }

/// The default description depends on WHAT was submitted. A KYB applicant told
/// "your identity verification has been submitted" is being told about the
/// wrong thing: they submitted a company, and an address-only applicant
/// submitted a pin. Mirrors the web SDK's successDescription (scope map
/// included).
const Map<String, String> _kScopeDescriptions = {
  'address': "Your address verification has been submitted. "
      "You'll be notified of the result.",
  'biometric-authentication': "Your face check has been submitted. "
      "You'll be notified of the result.",
  'biometric-enrollment': "Your face enrolment has been submitted. "
      "You'll be notified of the result.",
  'questionnaire': "Your answers have been submitted. "
      "You'll be notified of the result.",
  'contact': "Your contact verification has been submitted. "
      "You'll be notified of the result.",
};

// ─── Submitted screen ─────────────────────────────────────────────────────────
//
// Replaces the old ProcessingScreen + ResultScreen pair. On mount, calls
// verificationProvider.submitAsync() which POSTs to /api/v1/verify. The server
// returns 202 with { verificationId, status: 'pending' } in ~200ms — the
// SDK's job ends there. Final result arrives via webhook to the org's
// backend.

class SubmittedScreen extends ConsumerStatefulWidget {
  /// Called once the verify request succeeds (202).
  final void Function(VerificationSubmission submission)? onSubmitted;

  /// Called when the verify request fails (network, 401, 402, etc).
  final void Function(VerificationError error)? onError;

  /// Called when the user taps Done after a successful submission, OR
  /// taps "Close" on the error screen. Closes the modal/sheet.
  final VoidCallback? onDone;

  /// The verdict, on a flow that WAITS for it in the app (a biometric
  /// re-authentication on the default delivery). Fires once, never on a wait
  /// that timed out. See [VerificationResult].
  final void Function(VerificationResult result)? onResult;

  const SubmittedScreen({
    super.key,
    this.onSubmitted,
    this.onError,
    this.onDone,
    this.onResult,
  });

  @override
  ConsumerState<SubmittedScreen> createState() => _SubmittedScreenState();
}

class _SubmittedScreenState extends ConsumerState<SubmittedScreen> {
  _SubmitStatus _status = _SubmitStatus.submitting;
  VerificationSubmission? _submission;
  VerificationError? _error;

  /// Set while a transient failure is being retried — drives the "Reconnecting…
  /// retrying (n/total)" copy under the spinner.
  ({int attempt, int total})? _retryInfo;
  /// Where Go back lands after a refusal (submit_recovery.dart); null when
  /// going back cannot help.
  VerificationStep? _recoverTo;

  bool _kicked = false;
  late final BackgroundAskController _background =
      BackgroundAskController(ref.read(verificationConfigProvider));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _submit());
  }

  @override
  void dispose() {
    _background.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_kicked || !mounted) return;
    _kicked = true;

    setState(() {
      _status = _SubmitStatus.submitting;
      _error = null;
      _retryInfo = null;
    });

    // The biometric scopes hand over BEFORE the selfie upload lands (the
    // review is off, so nothing on the liveness screen gated on it): wait for
    // the upload's own record here, under the same loading screen. A failed
    // upload was already reported to onError by the screen that ran it. A
    // flow with no liveness step has no selfie to wait for.
    SelfieUploadSnapshot readUpload() {
      final s = ref.read(kYCNotifierProvider);
      return SelfieUploadSnapshot(selfieUpload: s.selfieUpload, selfieMediaId: s.mediaIds.selfie);
    }

    final config = ref.read(verificationConfigProvider);
    final hasLiveness =
        buildStepOrder(config, ref.read(kYCNotifierProvider)).contains(VerificationStep.liveness);
    if (!config.showsSelfieReviewOption &&
        selfieUploadExpected(readUpload(), hasLivenessStep: hasLiveness)) {
      final upload = await awaitSelfieUpload(
        read: readUpload,
        subscribe: (listener) {
          final sub = ref.listenManual<VerificationState>(kYCNotifierProvider, (_, __) => listener());
          return sub.close;
        },
      );
      if (!mounted) return;
      if (upload is SelfieUploadFailed) {
        setState(() {
          _status = _SubmitStatus.error;
          _error = VerificationError(code: 'upload_failed', message: upload.message);
        });
        return;
      }
    }

    try {
      final notifier = ref.read(kYCNotifierProvider.notifier);
      final result = await notifier.submitAsync(
        onRetry: (attempt, total) {
          if (mounted) {
            setState(() => _retryInfo = (attempt: attempt, total: total));
          }
        },
      );
      if (!mounted) return;

      final config = ref.read(verificationConfigProvider);
      final submission = VerificationSubmission(
        verificationId: result.verificationId,
        status: result.status,
        metadata: {...?config.metadata},
        submittedAt: DateTime.now(),
      );

      widget.onSubmitted?.call(submission);
      // The SDK's own presence calls (presence_auto_report.dart), and the
      // background ask when there is one to make.
      final ask = await _background.begin(resumed: false);
      if (!mounted) return;
      setState(() {
        _status = ask ? _SubmitStatus.background : _SubmitStatus.success;
        _submission = submission;
        _retryInfo = null;
      });
    } on VerificationApiException catch (e) {
      if (!mounted) return;
      // An organisation cancelled this verification: no Try again, no Go back.
      // The flow swaps to the dedicated cancelled screen, which reports
      // `session_cancelled` to onError once (config/session_cancelled.dart).
      final cancelled = sessionCancelledMessageFor(e);
      if (cancelled != null) {
        ref.read(kYCNotifierProvider.notifier).markSessionCancelled(cancelled);
        return;
      }
      // The saved address could not be used (grant spent or expired, or its
      // presence verdict too old): the offer comes back over the address step
      // rather than ending on an error.
      if (kAddressBookReuseRefusals.contains(e.error)) {
        ref.read(kYCNotifierProvider.notifier).addressBookReuseRefused();
        return;
      }
      // A refusal over stale contact proofs is recoverable in-flow: clear the
      // dead tokens and walk back to the contact step, which routes straight
      // back here once re-verified (see config/contact_recovery.dart).
      final channels = expiredContactChannels(e);
      if (channels.isNotEmpty) {
        final notifier = ref.read(kYCNotifierProvider.notifier);
        notifier.clearContactProofs(channels);
        notifier.goToStep(contactStepFor(channels.first));
        return;
      }
      // Retries (if any) are exhausted — surface a typed error.
      final error = mapToVerificationError(e, context: ErrorContext.verify);
      final mediaKey = e.details?['mediaKey'];
      final recoverTo = recoveryStepFor(
        e.error,
        buildStepOrder(ref.read(verificationConfigProvider), ref.read(kYCNotifierProvider)),
        mediaKey: mediaKey is String ? mediaKey : null,
      );
      setState(() {
        _status = _SubmitStatus.error;
        _error = error;
        _retryInfo = null;
        _recoverTo = recoverTo;
      });
      widget.onError?.call(error);
    } catch (_) {
      if (!mounted) return;
      const error = VerificationError(
        code: 'unknown',
        message: 'Something went wrong. Please try again.',
      );
      setState(() {
        _status = _SubmitStatus.error;
        _error = error;
        _retryInfo = null;
      });
      widget.onError?.call(error);
    }
  }

  void _retry() {
    _kicked = false;
    _submit();
  }

  /// Try Again after a failed selfie upload re-enters the liveness screen,
  /// whose mount resumes the interrupted upload and hands straight back here.
  /// The record is reset first so this screen waits for the NEW attempt rather
  /// than reading the old failure a second time.
  void _retryUpload() {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    notifier.setSelfieUpload(kIdleSelfieUpload);
    notifier.goToStep(VerificationStep.liveness);
  }

  void _close() {
    widget.onDone?.call();
  }

  /// Done, with a catch: if key people still owe a check, their invite links
  /// die with this screen — so offer the session's web page (where the links
  /// stay live) before letting the flow close. Workflow opt-out:
  /// `keyPeopleLinkRecovery: false` (on by default).
  /// [hasOutstanding] comes from the SERVER's settled list where there is one,
  /// falling back to "we minted invites" before it arrives. Offering to keep
  /// links alive when everybody has already verified is a prompt about nothing.
  void _handleDone(bool hasOutstanding) {
    final verificationState = ref.read(kYCNotifierProvider);
    final config = ref.read(verificationConfigProvider);
    final url = verificationState.sessionUrl;
    if (hasOutstanding && url != null && config.keyPeopleLinkRecovery) {
      showKeepLinksSheet(context, url: url, onDone: _close);
      return;
    }
    _close();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(verificationConfigProvider);
    // Catalogue texts; the org's success.title/description are their older
    // fields and still win, tokens filled. A scope's own line keeps this
    // SDK's wording (only the base descriptions are customisable).
    final t = textFnFor(config);
    final successTitle = t('result.success.title', legacy: config.success?.title);
    final scoped = _kScopeDescriptions[configScope(config.scope)];
    // A scoped business workflow names the business in its scope's line.
    final scopedBusiness = isScopedBusiness(config.subjectType, config.scope);
    final successDescription = t(
        scoped != null
            ? scopedBusiness
                ? 'result.success.description.${configScope(config.scope)}.business'
                : 'result.success.description.scope'
            : config.subjectType == 'business'
                ? 'result.success.description.business'
                : 'result.success.description.individual',
        legacy: config.success?.description,
        fallback: scoped);

    final scope = configScope(config.scope);
    final showDone = config.showsDoneButtonOption;

    return LayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            constraints.maxHeight.isFinite ? constraints.maxHeight : 480.0;
        // A flow that waits for its verdict (a biometric re-authentication, by
        // default) renders the result view from the FIRST build: it shows the
        // one loading screen through the upload wait, the submission and the
        // poll, then the verdict. onSubmitted has already fired by then.
        final Widget child = _status == _SubmitStatus.error
            ? ErrorView(
                error: _error!,
                onRetry: switch (_error!.code) {
                  'upload_failed' => _retryUpload,
                  'network_error' => _retry,
                  _ => null,
                },
                onClose: _close,
                // Only where Try Again is not the answer: a refusal about what
                // was entered is fixed on its own step, and the flow comes back
                // here to submit again.
                onGoBack: _recoverTo == null ||
                        _error!.code == 'upload_failed' ||
                        _error!.code == 'network_error'
                    ? null
                    : () => ref.read(kYCNotifierProvider.notifier).goToStep(_recoverTo!),
              )
            : config.waitsForResultOption
                ? SubmittedResultView(
                    verificationId: _status == _SubmitStatus.success
                        ? _submission!.verificationId
                        : null,
                    retryInfo: _retryInfo,
                    showDone: showDone,
                    onResult: widget.onResult,
                    onDone: _close,
                  )
                : _status == _SubmitStatus.submitting
                    ? Builder(builder: (_) {
                        final copy = describeWaiting(
                          scope: scope,
                          waitsForResult: false,
                          retry: _retryInfo,
                          override: config.biometricCopy.waiting,
                          t: textFnFor(config),
                        );
                        return SubmittedWaitingView(
                          title: copy.title,
                          description: copy.description,
                          retrying: _retryInfo != null,
                        );
                      })
                    : _status == _SubmitStatus.background
                    ? BackgroundAskScreen(
                        config: config,
                        controller: _background,
                        onDone: () => setState(() => _status = _SubmitStatus.success),
                      )
                    : _SuccessView(
                        background: _background,
                        submission: _submission!,
                        title: successTitle,
                        description: successDescription,
                        // KYB: per-person verification links for full-KYC key
                        // people, rendered so the applicant can send each one
                        // immediately.
                        invites: ref.watch(kYCNotifierProvider).keyPeopleInvites,
                        showDone: showDone,
                        onDone: _handleDone,
                      );
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: child,
        );
      },
    );
  }
}

// ─── Success view ─────────────────────────────────────────────────────────────

class _SuccessView extends ConsumerStatefulWidget {
  /// The "allow all the time" answer, for the presence card.
  final BackgroundAskController background;
  final VerificationSubmission submission;
  final String title;
  final String description;
  final List<KeyPersonInvite> invites;

  /// The `doneButton` option: off for a host that dismisses the flow itself.
  final bool showDone;
  final void Function(bool hasOutstanding) onDone;

  const _SuccessView({
    required this.background,
    required this.submission,
    required this.title,
    required this.description,
    this.invites = const [],
    this.showDone = true,
    required this.onDone,
  });

  @override
  ConsumerState<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends ConsumerState<_SuccessView> {
  AwaitingPeopleController? _awaiting;

  @override
  void initState() {
    super.initState();
    // WHO the application is waiting on, from the server. The invite links
    // above are the applicant's own list; registry discovery runs after
    // submission and can add directors nobody listed, so this is the only
    // account of the people that is actually complete.
    final sessionId = ref.read(kYCNotifierProvider).sessionId;
    // KYB only: an individual verification has no key people to wait on.
    final cfg = ref.read(verificationConfigProvider);
    if (sessionId == null || !isBusinessApplication(cfg.subjectType, cfg.scope)) {
      return;
    }
    _awaiting = AwaitingPeopleController(
      api: ref.read(kYCNotifierProvider.notifier).api,
      sessionId: sessionId,
    )..addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _awaiting?..removeListener(_onUpdate)..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final title = widget.title;
    final description = widget.description;
    final invites = widget.invites;
    final awaiting = _awaiting?.people;

    // KYB: hold the success screen until the server has settled WHO the
    // application is waiting on. Shown earlier, Done sat beside a list still
    // loading, and an applicant could close the sheet without ever seeing the
    // people they have to chase. Bounded by the controller's give-up.
    if (_awaiting != null && !_awaiting!.finished) {
      final t = context.verificationText;
      return SubmittedWaitingView(
        title: t('keyPeople.pending.title'),
        description: t('keyPeople.pending.body'),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: UiSpacing.xl),
            const Center(child: CheckBadge()),
            const SizedBox(height: UiSpacing.lg),
            Text(
              title,
              style: text.heading1.copyWith(height: 1.2),
              textAlign: TextAlign.center,
            )
                .animate(delay: 200.ms)
                .fadeIn(duration: 350.ms)
                .moveY(begin: 8, end: 0, duration: 350.ms),
            const SizedBox(height: UiSpacing.sm),
            Text(
              description,
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ).animate(delay: 320.ms).fadeIn(duration: 350.ms),
            // ONE list, from the SERVER. The applicant's own draft invites used
            // to render above this with their own copy/share buttons, so the
            // same people appeared twice and a reader had to hold both lists to
            // answer "who still owes me something". The link lives on the row.
            //
            // The screen is held until the server says its list is settled (see
            // the early return above): a list shown earlier is one director
            // short, permanently. Absent here only when the give-up passed with
            // nothing readable, which is better than a list that may be wrong.
            if (ref.read(verificationConfigProvider).addressCollection?.presenceEnabled == true &&
                ref.read(kYCNotifierProvider).address != null)
              ListenableBuilder(
                listenable: widget.background,
                builder: (context, _) {
                  final config = ref.read(verificationConfigProvider);
                  final business = config.subjectType == 'business';
                  return PresenceExpectations(
                    background: widget.background.outcome,
                    finishLine: finishSentence(
                      effortWithoutBackground(presencePolicyOf(config), isBusiness: business),
                      isBusiness: business,
                    ),
                    onTurnOn: widget.background.openSettings,
                  );
                },
              ).animate(delay: 400.ms).fadeIn(duration: 350.ms),
            if (awaiting != null)
              KeyPeopleAwaitList(people: awaiting)
                  .animate(delay: 450.ms)
                  .fadeIn(duration: 350.ms),
            // Shareholders a slow register sends late join the list above,
            // with their links, when they arrive.
            if (awaiting != null && _awaiting!.ownershipPending)
              const KeyPeopleOwnershipNote(submitted: true),
            const SizedBox(height: UiSpacing.xl),
          ],
        ),
        if (widget.showDone)
          UiButton(
            label: context.verificationText('common.done'),
            onPressed: () => widget.onDone(
              awaiting != null
                  // Shareholders still on their way bring links of their own.
                  ? _awaiting!.ownershipPending ||
                      awaiting.any((p) => p.stillOwes)
                  : invites.isNotEmpty,
            ),
          )
              .animate(delay: 600.ms)
              .fadeIn(duration: 300.ms)
              .moveY(begin: 8, end: 0, duration: 300.ms)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
