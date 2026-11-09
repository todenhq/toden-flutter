// The business documents step's own furniture: the group titles, the status
// pills, the progress line, the previous and next group rows, the accepted
// documents and how recent each must be, the upload card, and the errors the
// step and a refused submission show.
//
// None of these are customisable (only the step's title and description are),
// so they sit apart from kDefaultTexts, which holds customisable keys only, and
// resolveText reads them as a fallback the way it reads the business variants.
// Mirrors the web SDK's i18n/groups/business-documents.ts and the
// general.error.missingDocuments* texts (keys and wording): keep them in step.

const Map<String, String> kBusinessDocumentTexts = {
  'business.documents.group.legalPresence': 'Legal presence',
  'business.documents.group.companyDetails': 'Company details',
  'business.documents.group.ownership': 'Ownership structure',
  'business.documents.group.representativeAuthorisation':
      'Authority to represent the business',
  'business.documents.group.address': 'Business address',
  'business.documents.group.financial': 'Financial statements',
  'business.documents.group.tax': 'Tax registration',
  'business.documents.group.regulatory': 'Licences and permits',
  'business.documents.group.other': 'Other documents',
  'business.documents.status.required': 'Required',
  'business.documents.status.optional': 'Optional',
  'business.documents.status.next': 'Next',
  'business.documents.skipped': 'Skipped',
  'business.documents.change': 'Change',
  'business.documents.progress': '{current} of {total}',
  'business.documents.accepts': 'Any one of these',
  'business.documents.acceptsOne': 'Upload this document',
  'business.documents.validity': 'From the last {months} months',
  'business.documents.drop.tap': 'Tap to choose a file',
  'business.documents.uploaded': 'Uploaded',
  'business.documents.uploading': 'Uploading…',
  'business.documents.replace': 'Replace',
  'business.documents.remove': 'Remove',
  'business.documents.skip': 'Skip',
  'business.documents.next': 'Next',
  'business.documents.errorUpload':
      'Upload failed. Please check your connection and try again.',
  'general.error.missingDocumentsNamed':
      'Required business documents are missing: {documents}. Please go back and upload them.',
  'general.error.missingDocuments':
      'Some required business documents are missing. Please go back and upload them.',
};
