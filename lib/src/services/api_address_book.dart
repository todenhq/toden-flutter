part of 'api_service.dart';

// ─── The Toden address book on the wire ──────────────────────────────────────
//
// Reusing an address the person saved with Toden: whether their email has one,
// a code to that email, then their saved addresses (street and area only) and a
// one-time grant the submission spends. The calls are instance methods on
// VerificationApiService (addressBookLookup / addressBookCode /
// addressBookAddresses) rather than an extension, so a test can stub them; the
// error mapper keeps the server's own code (404 `address_book_unavailable`, 400
// `invalid_email` / `invalid_code`, 429 `rate_limited`). Mirrors the web SDK's
// API client.

/// What `POST /address-book/addresses` answers with a correct code.
class AddressBookListing {
  final String grant;
  final String? expiresAt;
  final List<SavedAddress> addresses;

  const AddressBookListing({required this.grant, this.expiresAt, this.addresses = const []});

  factory AddressBookListing.fromJson(Map<String, dynamic> json) => AddressBookListing(
        grant: json['grant'] as String? ?? '',
        expiresAt: json['expiresAt'] as String?,
        addresses: [
          for (final row in (json['addresses'] as List? ?? const []).whereType<Map>())
            if (SavedAddress.fromJson(row.cast<String, dynamic>()) case final SavedAddress a) a,
        ],
      );
}
