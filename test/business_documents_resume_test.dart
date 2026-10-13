import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/business_application.dart';
import 'package:myaza_kyc_sdk_flutter/src/config/submit_recovery.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/verification_state.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_progress.dart';
import 'package:myaza_kyc_sdk_flutter/src/providers/session_restore.dart';

// Reported 2026-09-29: a KYB applicant closed the SDK during their own ID
// check, came back, finished, and the submission was refused because the
// company documents they had uploaded were "missing". Progress never saved
// them. The refusal screen then offered only Close.

void main() {
  group('company documents survive a resume', () {
    test('are saved with the application and restored as uploaded', () {
      const before = VerificationState(
        currentStep: VerificationStep.idType,
        businessDocuments: [
          BusinessDocumentUpload(
            type: 'incorporation_certificate',
            mediaId: 'med_cert',
            fileName: 'cert.pdf',
            previewPath: '/tmp/never-saved.jpg',
            isPdf: true,
          ),
        ],
      );
      final progress = progressFromState(before);
      final saved = ((progress['data'] as Map)['businessApplication'] as Map)['documents'] as List;
      expect(saved, [
        {'type': 'incorporation_certificate', 'mediaId': 'med_cert', 'fileName': 'cert.pdf', 'isPdf': true},
      ]);

      final after = restoredState(const VerificationState(), progress);
      expect(after.businessDocuments, hasLength(1));
      final doc = after.businessDocuments.single;
      expect(doc.mediaId, 'med_cert');
      expect(doc.fileName, 'cert.pdf');
      expect(doc.isPdf, isTrue);
      // A preview is a local file and never rides progress.
      expect(doc.previewPath, isNull);
    });

    test('an entry without an upload is not restored', () {
      final after = restoredState(const VerificationState(), {
        'step': 'id-type',
        'data': {
          'businessApplication': {
            'documents': [
              {'type': 'memart', 'mediaId': ''},
              {'type': 'memart'},
            ],
          },
        },
      });
      expect(after.businessDocuments, isEmpty);
    });
  });

  group('Go back after a refused submission', () {
    const order = [
      VerificationStep.consent,
      VerificationStep.businessDetails,
      VerificationStep.businessDocuments,
      VerificationStep.businessKeyPeople,
      VerificationStep.applicantRole,
      VerificationStep.idType,
      VerificationStep.liveness,
      VerificationStep.submitted,
    ];

    test('lands on the step that owns the refusal', () {
      expect(recoveryStepFor('missing_documents', order), VerificationStep.businessDocuments);
      expect(recoveryStepFor('missing_company_info', order), VerificationStep.businessDetails);
      expect(recoveryStepFor('key_people_required', order), VerificationStep.businessKeyPeople);
      expect(recoveryStepFor('invalid_media', order, mediaKey: 'selfie'), VerificationStep.liveness);
    });

    test('falls back to the last step before submission', () {
      expect(recoveryStepFor('something_else', order), VerificationStep.liveness);
      // A named step this flow does not have.
      expect(recoveryStepFor('questionnaire_invalid', order), VerificationStep.liveness);
    });

    test('offers nothing where going back cannot help', () {
      expect(recoveryStepFor('insufficient_credits', order), isNull);
      expect(recoveryStepFor('invalid_api_key', order), isNull);
    });
  });
}
