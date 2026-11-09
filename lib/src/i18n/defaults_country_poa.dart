// The country summary row (on the Proof of Address step, the combined ID step
// and the business details step), the phone field's country code sheet, and the Proof of Address step's own
// furniture: the kinds' documents, how recent each must be, the accepted
// documents sheet, the capture tiles and the uploaded card.
//
// None of these are customisable (the shared list is capped), so they sit
// apart from kDefaultTexts, which holds customisable keys only, and
// resolveText reads them as a fallback the way it reads the business
// variants. Mirrors the web SDK's i18n/groups/proofOfAddress.ts,
// selectDocument.ts, business-country.ts and business-details.ts (keys and
// wording, byte for byte): keep them in step.

const Map<String, String> kCountryPoaTexts = {
  // ── The ID's country, on the combined ID step ──────────────────────────────
  'selectDocument.country.label': 'Your ID was issued in',
  'selectDocument.country.placeholder': 'Select a country',
  'selectDocument.country.change': 'Change',
  'selectDocument.country.choose': 'Choose',
  'selectDocument.country.selected': 'Selected',
  'selectDocument.country.search': 'Search countries…',
  'selectDocument.country.yourLocation': 'Your location',
  'selectDocument.country.noResults': 'No countries found.',
  'selectDocument.combined.title': 'Choose your ID',
  'selectDocument.combined.description':
      'Pick the country that issued it, then the ID you will use.',

  // ── The country of registration ────────────────────────────────────────────
  'business.details.countryCaption': 'Registered in',
  'business.details.countryPinnedLocation': 'Your location',
  'business.country.searchPlaceholder': 'Search countries…',
  'business.country.noMatch': 'No countries match.',
  'business.country.placeholder': 'Select a country',
  'business.country.change': 'Change',
  'business.country.choose': 'Choose',
  'business.country.selected': 'Selected',

  // ── The phone field's country code sheet (web: i18n/groups/contact.ts) ──────
  'contact.phone.codeTitle': 'Country code',

  // ── Proof of address: where the document is from ───────────────────────────
  'proofOfAddress.country.label': 'Country',
  'proofOfAddress.country.residence': 'Your address is in',
  'proofOfAddress.country.change': 'Change',
  'proofOfAddress.country.choose': 'Choose',
  'proofOfAddress.country.selected': 'Selected',
  'proofOfAddress.country.placeholder': 'Select country',
  'proofOfAddress.country.search': 'Search countries…',
  'proofOfAddress.country.yourLocation': 'Your location',
  'proofOfAddress.country.noMatches': 'No countries match.',

  // ── Proof of address: the step's own descriptions ──────────────────────────
  'proofOfAddress.description':
      'Upload a document that shows your name and home address, issued within the last {days} days.',
  'proofOfAddress.description.noName':
      'Upload a document that shows your home address, issued within the last {days} days.',

  // ── Proof of address: the documents inside each kind ───────────────────────
  'proofOfAddress.subtype.electricityBill': 'Electricity bill',
  'proofOfAddress.subtype.waterBill': 'Water bill',
  'proofOfAddress.subtype.gasBill': 'Gas bill',
  'proofOfAddress.subtype.internetBill': 'Internet or TV bill',
  'proofOfAddress.subtype.phoneBill': 'Phone bill',
  'proofOfAddress.subtype.wasteBill': 'Waste collection bill',
  'proofOfAddress.subtype.bankStatement': 'Bank statement',
  'proofOfAddress.subtype.creditCardStatement': 'Credit card statement',
  'proofOfAddress.subtype.mortgageStatement': 'Mortgage statement',
  'proofOfAddress.subtype.loanStatement': 'Loan statement',
  'proofOfAddress.subtype.tenancyAgreement': 'Tenancy agreement',
  'proofOfAddress.subtype.leaseAgreement': 'Lease agreement',
  'proofOfAddress.subtype.propertyTitle': 'Title deed or property certificate',
  'proofOfAddress.subtype.taxDocument': 'Tax letter or assessment',
  'proofOfAddress.subtype.propertyRatesBill': 'Council tax or property rates bill',
  'proofOfAddress.subtype.voterRegistration': 'Voter registration letter',
  'proofOfAddress.subtype.voterId': "Voter's ID card",
  'proofOfAddress.subtype.benefitsLetter': 'Benefits or pension letter',
  'proofOfAddress.subtype.governmentLetter': 'Other government letter',
  'proofOfAddress.subtype.insuranceDocument': 'Insurance policy or certificate',
  'proofOfAddress.subtype.employerLetter': 'Letter from an employer',
  'proofOfAddress.subtype.educationLetter': 'Letter from a school or university',
  'proofOfAddress.subtype.otherDocument': 'Other document showing your address',
  'proofOfAddress.subtypeShort.electricityBill': 'electricity',
  'proofOfAddress.subtypeShort.waterBill': 'water',
  'proofOfAddress.subtypeShort.gasBill': 'gas',
  'proofOfAddress.subtypeShort.internetBill': 'internet',
  'proofOfAddress.subtypeShort.phoneBill': 'phone',
  'proofOfAddress.subtypeShort.wasteBill': 'waste collection',
  'proofOfAddress.subtypeShort.bankStatement': 'bank',
  'proofOfAddress.subtypeShort.creditCardStatement': 'credit card',
  'proofOfAddress.subtypeShort.mortgageStatement': 'mortgage',
  'proofOfAddress.subtypeShort.loanStatement': 'loan',
  'proofOfAddress.subtypeShort.tenancyAgreement': 'tenancy',
  'proofOfAddress.subtypeShort.leaseAgreement': 'lease',
  'proofOfAddress.subtypeShort.propertyTitle': 'title deed',
  'proofOfAddress.subtypeShort.taxDocument': 'tax',
  'proofOfAddress.subtypeShort.propertyRatesBill': 'property rates',
  'proofOfAddress.subtypeShort.voterRegistration': 'voter registration',
  'proofOfAddress.subtypeShort.voterId': "voter's ID",
  'proofOfAddress.subtypeShort.benefitsLetter': 'benefits',
  'proofOfAddress.subtypeShort.governmentLetter': 'other official letters',
  'proofOfAddress.subtypeShort.insuranceDocument': 'insurance',
  'proofOfAddress.subtypeShort.employerLetter': 'employer',
  'proofOfAddress.subtypeShort.educationLetter': 'school or university',
  'proofOfAddress.subtypeShort.otherDocument': 'other documents',

  // ── Proof of address: how recent ───────────────────────────────────────────
  'proofOfAddress.validity.month': '1 month',
  'proofOfAddress.validity.months': '{count} months',
  'proofOfAddress.validity.year': '1 year',
  'proofOfAddress.validity.years': '{count} years',
  'proofOfAddress.validity.any': 'Any date',

  // ── Proof of address: the accepted documents sheet ─────────────────────────
  'proofOfAddress.accepted.open': 'See accepted documents',
  'proofOfAddress.accepted.title': 'Accepted documents',
  'proofOfAddress.accepted.description':
      'Upload any one of these, showing your name and address.',
  'proofOfAddress.accepted.close': 'Close',

  // ── Proof of address: the capture tiles and the uploaded card ──────────────
  'proofOfAddress.action.camera': 'Take a photo',
  'proofOfAddress.action.cameraHint': 'Use your camera',
  'proofOfAddress.action.file': 'Upload a file',
  'proofOfAddress.action.fileHint': 'PDF or image',
  'proofOfAddress.uploading': 'Uploading…',
  'proofOfAddress.replace': 'Replace',
  'proofOfAddress.remove': 'Remove',
};
