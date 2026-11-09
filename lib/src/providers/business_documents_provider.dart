import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── The business documents step: which group is open ────────────────────────
//
// The step walks its document groups one at a time, and the flow's back arrow
// walks them too before leaving the step (the web SDK's BusinessDocumentsStep
// does both). The screen owns the value; the shell reads it for the arrow.
// Scoped per flow by verificationFlowOverrides.

final businessDocumentGroupIndexProvider = StateProvider<int>((ref) => 0);

// ─── The supporting documents step: which document is open ───────────────────
//
// Shown one at a time like the business documents, and walked by the back
// arrow the same way. The screen owns the value; the shell reads it.

final supportingDocumentIndexProvider = StateProvider<int>((ref) => 0);
