import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../config/photo_mode.dart';
import '../config/proof_of_address.dart';
import '../config/scope.dart';
import '../config/theme.dart';
import '../config/upload_limits.dart';
import '../i18n/business_variants.dart';
import '../providers/poa_step.dart';
import '../providers/verification_provider.dart';
import '../services/api_service.dart';
import '../widgets/address_country_control.dart';
import '../widgets/media_source_sheet.dart';
import '../widgets/ui_button.dart';
import 'proof_of_address_accepted.dart';
import 'proof_of_address_kinds.dart';
import 'proof_of_address_parts.dart';
import 'proof_of_address_pick.dart';
import 'photo_camera.dart';
import '../i18n/text_scope.dart';

part 'proof_of_address_upload.dart';

// ─── Proof of Address screen ──────────────────────────────────────────────────
//
// The applicant says which country the document is from, picks its kind,
// and takes a photo or uploads a file (image or PDF). The server reads it
// asynchronously, recognises which document within the kind it is, and checks
// the name, address and date: a soft check that never changes the
// verification's own status. The SDK only collects it. Mirrors the web SDK's
// steps/ProofOfAddressStep and the RN twin.
//
//   country   on EVERY scope (config/poa_country_gate.dart): the address
//             scope's declared country, else the document's own, starting
//             from the ID's.
//   kind      a radio list, shown only when more than one kind is offered;
//             "See accepted documents" opens what each kind takes.
//   capture   the tiles `proofOfAddress.capture` asks for, then the uploaded
//             card with Replace / Remove, then Continue.

class ProofOfAddressScreen extends ConsumerStatefulWidget {
  final void Function(Object error)? onError;
  const ProofOfAddressScreen({super.key, this.onError});

  @override
  ConsumerState<ProofOfAddressScreen> createState() =>
      _ProofOfAddressScreenState();
}

class _ProofOfAddressScreenState extends ConsumerState<ProofOfAddressScreen> {
  bool _uploading = false;
  String? _fileName;
  String? _error;

  // Kept so the uploaded card can show the user what they actually picked:
  // the only way to catch "wrong photo from the camera roll" before submitting.
  Uint8List? _previewBytes;
  bool _previewIsPdf = false;

  ProofOfAddressConfig get _cfg =>
      ref.read(verificationConfigProvider).proofOfAddress ??
      const ProofOfAddressConfig(enabled: true);

  /// The kind picked, as the header and the upload read it (poa_step.dart).
  PoaDocumentType get _type => poaStepKind(
      ref.read(verificationConfigProvider), ref.read(kYCNotifierProvider));

  /// `setState` for the upload ops in the part file: a protected member may
  /// only be called from the State itself, so the extension goes through this.
  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final t = context.verificationText;
    final config = ref.watch(verificationConfigProvider);
    final state = ref.watch(kYCNotifierProvider);
    final notifier = ref.read(kYCNotifierProvider.notifier);
    final cfg = _cfg;
    final scoped = configScope(config.scope) == 'address';

    // Where the document is from; Continue holds while null.
    final poaCountry = poaStepCountry(config, state);
    // Per-country overrides narrow the offer.
    final offered = cfg.offeredTypesFor(poaCountry);
    final selected = poaStepKind(config, state);
    String labelFor(PoaDocumentType kind) => cfg.labelFor(kind, t);
    final uploaded = state.mediaIds.proofOfAddress != null;
    final business = context.scopedBusinessFlow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Every scope: where the document is from. On the address scope it is
        // the flow's declared country; elsewhere the document's own.
        AddressCountryControl(
          value: poaCountry,
          label: t(businessKey('proofOfAddress.country.residence', business)),
          onPick: (code) => scoped
              ? notifier.setCountry(code)
              : notifier.setPoaCountry(code),
        ),
        const SizedBox(height: 20),

        // Locked once a file is attached: switching the kind afterwards would
        // mislabel the document already uploaded.
        if (offered.length > 1) ...[
          PoaKindList(
            kinds: offered,
            value: selected,
            enabled: !uploaded && !_uploading,
            poa: cfg,
            labelFor: labelFor,
            language: config.language,
            onChanged: (kind) => notifier.setPoaDocumentType(kind.key),
          ),
          const SizedBox(height: 4),
        ],

        PoaAcceptedLink(
          kinds: offered,
          selected: selected,
          poa: cfg,
          labelFor: labelFor,
        ),
        const SizedBox(height: 8),

        if (uploaded && !_uploading)
          PoaUploadedCard(
            fileName: _fileName,
            typeLabel: labelFor(selected),
            previewBytes: _previewBytes,
            isPdf: _previewIsPdf,
            country: poaCountry,
            onReplace: () => cfg.capture == PoaCapture.camera ? _takePhoto() : _pickFile(),
            onRemove: _remove,
          )
        else
          PoaUploadActions(
            capture: cfg.capture,
            uploading: _uploading,
            onCamera: _takePhoto,
            onFile: _pickFile,
          ),

        if (_error != null) ...[
          const SizedBox(height: UiSpacing.sm),
          Text(_error!, style: text.bodySmall.copyWith(color: UiColors.error)),
        ],

        // Continue arrives with the document: before it, the tiles are the
        // action.
        if (uploaded) ...[
          const SizedBox(height: 20),
          UiButton(
            label: context.verificationText('common.continue'),
            onPressed: !_uploading && poaCountry != null
                ? () {
                    // Pinned for the submission, which sends it as the
                    // document's country.
                    notifier.setPoaCountry(poaCountry);
                    notifier.nextStep();
                  }
                : null,
          ),
        ],
      ],
    );
  }
}

