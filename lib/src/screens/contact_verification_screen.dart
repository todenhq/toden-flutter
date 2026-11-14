import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/contact_recovery.dart';
import '../providers/verification_provider.dart';
import '../services/api_service.dart';
import '../services/contact_errors.dart';
import '../widgets/ui_alert.dart';
import 'contact_header_sync.dart';
import 'contact_verification_actions.dart';
import 'contact_verification_entry.dart';
import 'contact_verification_parts.dart';
import 'contact_verification_verified.dart';
import 'contact_verification_settings.dart';

// ─── Contact verification screen (email / phone OTP) ──────────────────────────
//
// One component, two mounts (channel: 'email' | 'phone'): enter a destination →
// send a code → enter the OTP → verify → advance.
// NOTE: each mount needs a distinct key — see _screenForStep.

class ContactVerificationScreen extends ConsumerStatefulWidget {
  final String channel; // 'email' | 'phone'
  const ContactVerificationScreen({super.key, required this.channel});

  @override
  ConsumerState<ContactVerificationScreen> createState() =>
      _ContactVerificationScreenState();
}

class _ContactVerificationScreenState
    extends ConsumerState<ContactVerificationScreen> {
  final _emailCtrl = TextEditingController();
  String _destination = '';
  bool _phoneValid = false;
  String? _challengeId;
  DateTime? _expiresAt;
  String _code = '';
  bool _sending = false;
  bool _checking = false;
  String? _error;

  /// The current code is used up (services/contact_errors.dart isCodeUsedUp):
  /// the field is read-only and the primary action sends a new code. Cleared
  /// only by a code sent successfully.
  bool _codeUsedUp = false;

  /// Codes sent so far; each one remounts the code field empty.
  int _sends = 0;

  /// Wrong codes entered; each one also remounts the field empty, so the
  /// applicant types the next try into a clean field.
  int _wrongEntries = 0;

  /// User-picked delivery channel; null leaves the workflow's first offered
  /// channel as the default.
  String? _via;

  /// Resend, optionally switching channel first.
  void _resend(String? switchTo) {
    if (switchTo != null) setState(() => _via = switchTo);
    _send();
  }

  bool get _isPhone => widget.channel == 'phone';
  ContactChannelSettings get _settings => ContactChannelSettings.resolve(
        ref.read(verificationConfigProvider),
        widget.channel,
        geoCountry: ref.read(kYCNotifierProvider).serverConfig.geoCountry,
      );

  /// What the server actually sent, which its pinned workflow decides.
  int? _sentCodeLength;

  /// Any request in flight — drives the button loader and input disabling.
  bool get _busy => _sending || _checking;
  bool get _canSend =>
      _isPhone ? _phoneValid : isPlausibleContactEmail(_destination);
  bool get _canVerify => _code.trim().length >= kMinCodeLength;
  VerificationApiService get _api => ref.read(kYCNotifierProvider.notifier).api;

  /// Entered via submit recovery? (The server refused this channel's proof at
  /// submit — the token had expired or was already claimed.) Captured once:
  /// verifying clears the flag, and Continue must still route back to
  /// `submitted` afterwards (which auto-submits with the fresh proof).
  late final bool _recovery =
      ref.read(kYCNotifierProvider).expiredContact.contains(widget.channel);

  void _advance() {
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final target = stepAfterContactVerified(
      recovery: _recovery,
      expired: ref.read(kYCNotifierProvider).expiredContact,
      channel: widget.channel,
    );
    if (target != null) {
      notifier.goToStep(target);
    } else {
      notifier.nextStep();
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend || _busy) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final settings = _settings;
    try {
      final res = await _api.contactSend(
        channel: widget.channel,
        destination: _destination,
        via: _via ?? settings.defaultChannel,
        codeLength: settings.codeLength,
        maxAttempts: settings.maxAttempts,
        sessionId: ref.read(kYCNotifierProvider).sessionId,
      );
      if (!mounted) return;
      setState(() {
        _sentCodeLength = sentCodeLength(res.codeLength, settings.codeLength);
        _challengeId = res.challengeId;
        _expiresAt = DateTime.tryParse(res.expiresAt ?? '');
        _code = '';
        _codeUsedUp = false;
        _sends++;
        _sending = false;
      });
    } catch (e) {
      // Catch everything: a non-API failure (socket/TLS/parse) must still clear
      // the spinner, otherwise the button stays stuck mid-send with no message.
      if (!mounted) return;
      if (_endsSession(e)) {
        setState(() => _sending = false);
        return;
      }
      setState(() {
        _sending = false;
        _error = describeSendError(e);
      });
    }
  }

  Future<void> _check(String code) async {
    final value = code.trim();
    if (_challengeId == null ||
        _busy ||
        _codeUsedUp ||
        value.length < kMinCodeLength) {
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final res = await _api.contactCheck(
        challengeId: _challengeId!,
        code: value,
        sessionId: ref.read(kYCNotifierProvider).sessionId,
        country: ref.read(kYCNotifierProvider).selectedCountry,
      );
      if (!mounted) return;
      if (res.verified && res.token.isNotEmpty) {
        // Clear before advancing — a stuck `true` reads as an endless spinner.
        setState(() => _checking = false);
        ref
            .read(kYCNotifierProvider.notifier)
            .setContactProof(widget.channel, res.token, _destination);
        _advance();
      } else {
        setState(() {
          _checking = false;
          _error = 'That code is not correct. Please try again.';
          _code = '';
          _wrongEntries++;
        });
      }
    } catch (e) {
      if (!mounted) return;
      if (_endsSession(e)) {
        setState(() => _checking = false);
        return;
      }
      setState(() {
        _checking = false;
        _codeUsedUp = isCodeUsedUp(e);
        _error = describeCheckError(e);
        // A wrong code clears the field; a network failure keeps what was
        // typed so the applicant can simply try again.
        if (isWrongCode(e)) {
          _code = '';
          _wrongEntries++;
        }
      });
    }
  }

  /// A cancelled or declined session ends the flow on its own screen
  /// (config/session_declined.dart); this step names the channel it was on.
  bool _endsSession(Object e) => ref
      .read(kYCNotifierProvider.notifier)
      .endOnSessionRefusal(e, channel: widget.channel);

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final state = ref.watch(kYCNotifierProvider);
    final verifiedToken = _isPhone ? state.phoneToken : state.emailToken;

    if (verifiedToken != null) {
      return ContactVerifiedView(
        isPhone: _isPhone,
        destination: _isPhone ? state.phoneNumber : state.emailAddress,
        onContinue: _advance,
      );
    }

    final hasChallenge = _challengeId != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContactHeaderSync(
          channel: widget.channel,
          via: _isPhone ? (_via ?? settings.defaultChannel ?? '') : '',
          destination: hasChallenge ? _destination : '',
        ),
        if (_recovery && !hasChallenge) ...[
          UiAlert(
            variant: UiAlertVariant.warning,
            title: 'Please verify again',
            message:
                'Your earlier confirmation has expired, so please verify ${_isPhone ? 'your number' : 'your email'} once more. Everything else is saved, and we will submit again straight after.',
          ),
          const SizedBox(height: 16),
        ],
        if (!hasChallenge)
          ContactEntryPanel(
            isPhone: _isPhone,
            emailController: _emailCtrl,
            defaultCountry: settings.defaultCountry,
            geoCountry: settings.geoCountry,
            dialCountries: settings.dialCountries,
            enabled: !_busy,
            onEmailChanged: (v) => setState(() => _destination = v.trim()),
            onPhoneChanged: (e164, valid) => setState(() {
              _destination = e164;
              _phoneValid = valid;
            }),
            offeredChannels: settings.offeredChannels,
            pickedChannel: _via ?? settings.defaultChannel ?? 'sms',
            onPickChannel: (c) => setState(() => _via = c),
          )
        else
          ContactCodePanel(
            codeLength: _sentCodeLength ?? settings.codeLength,
            style: settings.inputStyle,
            alphanumeric: settings.alphanumeric,
            enabled: !_busy,
            challengeId: _challengeId!,
            // Sends and wrong entries both only grow, so the sum changes on
            // each and remounts the field empty.
            sendCount: _sends + _wrongEntries,
            codeUsedUp: _codeUsedUp,
            expiresAt: _expiresAt,
            onChanged: (c) => setState(() => _code = c),
            onCompleted: _check,
            onResend: _busy ? null : _resend,
            otherChannel: settings.otherThan(_via),
          ),
        ContactActions(
          error: _error,
          hasChallenge: hasChallenge,
          isBusy: _busy,
          isPhone: _isPhone,
          codeUsedUp: hasChallenge && _codeUsedUp,
          onSubmit: _busy
              ? null
              : hasChallenge && _codeUsedUp
                  ? () => _resend(null)
                  : (hasChallenge ? _canVerify : _canSend)
                      ? (hasChallenge ? () => _check(_code) : _send)
                      : null,
          onSkip: settings.required ? null : _advance,
        ),
      ],
    );
  }
}
