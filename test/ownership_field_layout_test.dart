import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/screens/ownership_slider.dart';
import 'package:toden_flutter/src/widgets/ui_input.dart';

// The key person's Ownership % field: a text suffix ("%") once grew to the
// whole input, so what was typed drew in no space, and the slider under it sat
// short of the field's width.

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    );

void main() {
  testWidgets('a text suffix leaves the typed value room to show', (tester) async {
    final ctrl = TextEditingController(text: '27');
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(_host(UiInput(controller: ctrl, suffix: const Text('%'))));

    final field = tester.getSize(find.byType(EditableText));
    final suffix = tester.getSize(find.text('%'));
    expect(field.width, greaterThan(200));
    expect(suffix.width, lessThan(40));
    expect(find.text('27'), findsOneWidget);
  });

  testWidgets('the ownership slider spans the field', (tester) async {
    await tester.pumpWidget(_host(OwnershipSlider(value: 50, onChanged: (_) {})));
    expect(tester.getSize(find.byType(Slider)).width, 360);
    // No side inset, so the track runs the field's full width; RN's 32-high row.
    final slider = tester.widget<SliderTheme>(find.byType(SliderTheme).last);
    expect(slider.data.padding, EdgeInsets.zero);
    expect(tester.getSize(find.byType(Slider)).height, 32);
  });

  testWidgets('a tap off the field puts the keyboard away', (tester) async {
    final ctrl = TextEditingController();
    addTearDown(ctrl.dispose);
    await tester.pumpWidget(_host(Column(mainAxisSize: MainAxisSize.min, children: [
      UiInput(controller: ctrl),
      const SizedBox(key: Key('outside'), height: 200, width: 360),
    ])));
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('outside'))));
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.context?.widget is EditableText, isFalse);
  });
}
