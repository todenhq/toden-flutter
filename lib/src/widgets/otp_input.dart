import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/contact_verification.dart';
import '../config/otp_code.dart';
import '../config/theme.dart';
import '../i18n/text_scope.dart';
import 'icons/icons.dart';
import 'ui_input.dart';

// ─── OTP input ────────────────────────────────────────────────────────────────
//
// Enters an N-digit OTP. Two styles (org-config-driven, matching the web SDK):
// `segmented` (N boxes, default) or `text` (a single spaced numeric field).
// Fires `onCompleted` when the last digit lands (auto-submit).
//
// Neither field limits its length or filters its input: both cut a paste before
// anybody reads it. The length is applied to the digits (config/otp_code.dart).
// A number pad has no paste key, so Paste code sits beside it.

class OtpInput extends StatefulWidget {
  final int length;
  final OtpInputStyle style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onCompleted;
  final bool enabled;

  const OtpInput({
    super.key,
    required this.length,
    required this.style,
    required this.onCompleted,
    this.onChanged,
    this.enabled = true,
  });

  @override
  State<OtpInput> createState() => _OtpInputState();
}

class _OtpInputState extends State<OtpInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _previous = '';
  bool _noCode = false;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final next = pastedCode(data?.text ?? '', widget.length);
    if (!mounted) return;
    if (next == null) {
      setState(() => _noCode = true);
      return;
    }
    _onChanged(next);
  }

  void _onChanged(String raw) {
    final clipped = otpCodeFrom(raw, _previous, widget.length);
    _previous = clipped;
    _noCode = false;
    if (clipped != _controller.text) {
      _controller.value = TextEditingValue(
        text: clipped,
        selection: TextSelection.collapsed(offset: clipped.length),
      );
    }
    setState(() {});
    widget.onChanged?.call(clipped);
    if (clipped.length == widget.length) widget.onCompleted(clipped);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.style == OtpInputStyle.text)
          UiInput(
            controller: _controller,
            hint: '•' * widget.length,
            keyboardType: TextInputType.number,
            autofocus: true,
            onChanged: _onChanged,
          )
        else
          _segmented(context),
        _pasteLink(context),
      ],
    );
  }

  Widget _pasteLink(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;
    return Padding(
      padding: const EdgeInsets.only(top: UiSpacing.xs),
      child: Column(
        children: [
          TextButton.icon(
            onPressed: widget.enabled ? _paste : null,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: UiIcon(UiIcons.copy, size: 16, color: colors.primary),
            label: Text(context.verificationText('contact.code.paste'),
                style: text.label.copyWith(color: colors.primary)),
          ),
          if (_noCode)
            Text(context.verificationText('contact.code.pasteNone'),
                textAlign: TextAlign.center,
                style: text.bodySmall.copyWith(color: UiColors.error)),
        ],
      ),
    );
  }

  Widget _segmented(BuildContext context) {
    final colors = context.myazaColors;
    final text = context.myazaText;

    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < widget.length; i++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: i == widget.length - 1 ? 0 : UiSpacing.xs,
                  ),
                  child: AspectRatio(
                    aspectRatio: 0.82,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.background,
                        border: Border.all(
                          color: i < _controller.text.length
                              ? colors.primary
                              : colors.border,
                          width: i < _controller.text.length ? 1.5 : 1.0,
                        ),
                        borderRadius: BorderRadius.circular(UiRadius.md),
                      ),
                      child: Text(
                        i < _controller.text.length ? _controller.text[i] : '',
                        style: text.heading2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // Transparent field over the boxes captures taps + keyboard input.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: true,
              keyboardType: TextInputType.number,
              showCursor: false,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
