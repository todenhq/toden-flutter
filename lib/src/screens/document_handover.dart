import 'package:flutter/material.dart';

import 'submitted_waiting_view.dart';

// ─── Handing over without the review ────────────────────────────────────────
//
// What the document step shows while a scan moves straight on, with the review
// screen switched off: the photo is uploading and being checked, and there is
// nothing to do. A problem brings the review back. A loading state, so fixed
// wording, outside the customisable texts. Mirrors the RN DocumentHandover.

class DocumentHandover extends StatelessWidget {
  final ({int attempt, int total})? retryInfo;

  const DocumentHandover({super.key, this.retryInfo});

  @override
  Widget build(BuildContext context) {
    final retry = retryInfo;
    return SubmittedWaitingView(
      title: 'Checking your document',
      description: retry == null
          ? 'This only takes a moment.'
          : 'Upload failed. Retrying (${retry.attempt}/${retry.total})…',
      retrying: retry != null,
    );
  }
}
