import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../i18n/text_scope.dart';
import '../widgets/icons/icons.dart';

/// "Uploaded" and the file size under a document's name. Wraps rather than
/// running under the row's actions on a narrow phone or at a large text size,
/// so the size has no separator to orphan.
class BusinessDocumentUploadedStatus extends StatelessWidget {
  const BusinessDocumentUploadedStatus({super.key, required this.size});

  /// The size as shown, or null when it is not known (a restored session).
  final String? size;

  @override
  Widget build(BuildContext context) {
    final text = context.myazaText;
    final colors = context.myazaColors;
    final size = this.size;
    return Wrap(
      spacing: UiSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text.rich(TextSpan(children: [
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: UiSpacing.xs + 2),
              child: UiIcon(UiIcons.circleCheck,
                  size: 14, color: UiColors.success),
            ),
          ),
          TextSpan(
              text: context.verificationText('business.documents.uploaded'),
              style: text.bodySmall.copyWith(color: UiColors.success)),
        ])),
        if (size != null)
          Text(size,
              style: text.bodySmall.copyWith(color: colors.textSecondary)),
      ],
    );
  }
}
