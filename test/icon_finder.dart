import 'package:flutter_test/flutter_test.dart';
import 'package:myaza_kyc_sdk_flutter/src/widgets/icons/icons.dart';

/// Find a rendered [UiIcon] by the icon it draws.
///
/// `find.byIcon` cannot be used: it takes an [IconData], and the SDK's icons
/// are SVG path data rather than font glyphs. The constants are `const`, so
/// Dart canonicalises them and equality here is identity on the same constant.
Finder findUiIcon(UiIconData icon) => find.byWidgetPredicate(
      (widget) => widget is UiIcon && widget.icon == icon,
      description: 'UiIcon',
    );
