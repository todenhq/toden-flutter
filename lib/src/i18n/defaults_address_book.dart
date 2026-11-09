// The Toden address book in the address flow: the sheet that offers a saved
// address when the flow's email is recognised (a code, then a pick), and the
// sheet after the review step that saves the confirmed address to their book.
//
// None of these are customisable: they describe the person's own Toden
// account, not the organisation's flow. So they sit apart from kDefaultTexts,
// which holds customisable keys only, and resolveText reads them as a fallback
// the way it reads the business variants. Mirrors the web SDK's
// i18n/groups/address-book.ts (keys and wording) and the React Native SDK's
// copy: keep the three in step.

const Map<String, String> kAddressBookTexts = {
  'address.book.offer.title': 'You have a saved address',
  'address.book.offer.titleNamed': '{firstName}, you have a saved address',
  'address.book.offer.description':
      "Use the address you saved with Toden so you don't have to enter it again.",
  'address.book.offer.email': "We'll send a code to {email} to confirm it's you.",
  'address.book.offer.use': 'Use saved address',
  'address.book.offer.sending': 'Sending code…',
  'address.book.offer.new': 'Enter a new address',
  'address.book.code.title': 'Enter the code',
  'address.book.code.description': 'We sent a 6-digit code to {email}.',
  'address.book.code.check': 'Continue',
  'address.book.code.checking': 'Checking…',
  'address.book.code.resend': 'Send a new code',
  'address.book.pick.title': 'Choose your address',
  'address.book.pick.description':
      'Only the street and area are shown here. The full address is shared once your verification is complete.',
  'address.book.pick.use': 'Use this address',
  'address.book.pick.none':
      'There are no saved addresses you can use here. Enter a new address instead.',
  'address.book.pick.stale':
      'Addresses whose presence has not been confirmed in the last six months cannot be used for this check.',
  'address.book.presence.verified': 'Presence confirmed',
  'address.book.chosen.title': 'Your saved address',
  'address.book.chosen.badge': 'Saved address',
  'address.book.chosen.change': 'Use a different address',
  'address.book.continue': 'Continue',
  'address.book.refused':
      'That saved address can no longer be used. Try again, or enter a new address.',
  'address.book.error': 'Something went wrong. Try again.',
  'address.book.save.title': 'Save this address for next time?',
  'address.book.save.description':
      'Next time a company asks for your address, you can share it in a tap. Manage it any time at me.toden.co.',
  'address.book.save.photo': 'Your entrance photo is saved with it.',
  'address.book.save.directions': 'Include my directions',
  'address.book.save.confirm': 'Save address',
  'address.book.save.skip': 'Not now',
  // The code field's paste link: shared with the contact steps, and like these
  // not customisable.
  'contact.code.paste': 'Paste code',
  'contact.code.pasteNone': 'No code found. Copy it from your message and try again.',
};
