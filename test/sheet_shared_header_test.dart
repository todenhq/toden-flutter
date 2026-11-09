import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/widgets/dial_code_picker.dart';
import 'package:toden_flutter/src/widgets/themed_sheet.dart';
import 'package:toden_flutter/src/widgets/ui_select.dart';

// The house sheet, as the web SDK's drawer now draws it: floating 8px off the
// sides and bottom (the home indicator rides on it), a faint brand-tinted edge, a scrim at
// half strength, and one header (title, close) for every sheet.

Widget _host(void Function(BuildContext) open, {double bottomInset = 0}) => MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(390, 844), padding: EdgeInsets.only(bottom: bottomInset)),
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () => open(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a titled sheet: the title, its line and the close', (tester) async {
    await tester.pumpWidget(_host((c) => showUiSheet<void>(
          c,
          title: 'Accepted documents',
          description: 'Upload any one of these.',
          builder: (_) => const SizedBox(height: 120, child: Text('body')),
        )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Accepted documents'), findsOneWidget);
    expect(find.text('Upload any one of these.'), findsOneWidget);
    expect(find.byType(UiSheetCloseButton), findsOneWidget);

    await tester.tap(find.byType(UiSheetCloseButton));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('floats over a half-strength scrim with a brand-tinted edge', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(
      (c) => showUiSheet<void>(c, builder: (_) => const SizedBox(height: 120, child: Text('body'))),
      bottomInset: 34,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final barrier = tester.widget<ModalBarrier>(find.byType(ModalBarrier).last);
    expect(barrier.color, Colors.black.withValues(alpha: 0.5));

    final panel = tester.widget<Material>(find.ancestor(
      of: find.text('body'),
      matching: find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder),
    ).first);
    final shape = panel.shape! as RoundedRectangleBorder;
    expect(shape.side.color, UiColorScheme.light.primary.withValues(alpha: 0.2));

    // 8 off the sides and the bottom edge: the home indicator rides on the card.
    final rect = tester.getRect(find.byWidget(panel));
    expect(rect.left, 8);
    expect(rect.right, 390 - 8);
    expect(rect.bottom, 844 - 8);
  });

  testWidgets('the phone code sheet is headed Country code', (tester) async {
    await tester.pumpWidget(_host((c) => showDialCodePicker(c, 'NG')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Country code'), findsOneWidget);
  });

  testWidgets('a select is headed by what is being picked', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(
        body: UiSelect<String>(
          value: null,
          hint: 'Choose one',
          sheetTitle: 'Source of funds',
          options: const [UiSelectOption(value: 'a', label: 'Salary')],
          onChanged: (v) => picked = v,
        ),
      ),
    ));
    await tester.tap(find.text('Choose one'));
    await tester.pumpAndSettle();
    expect(find.text('Source of funds'), findsOneWidget);
    expect(find.byType(UiSheetCloseButton), findsOneWidget);
    await tester.tap(find.text('Salary'));
    await tester.pumpAndSettle();
    expect(picked, 'a');
  });

  testWidgets('a date opens a titled calendar sheet; a day picks it', (tester) async {
    DateTime? picked;
    await tester.pumpWidget(_host((c) async {
      picked = await showUiDatePicker(
        c,
        initialDate: DateTime(2026, 11, 8),
        firstDate: DateTime(1900),
        lastDate: DateTime(2030),
        title: 'Date of incorporation',
      );
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Date of incorporation'), findsOneWidget);
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(picked, DateTime(2026, 11, 12));
  });

  testWidgets('a tall sheet stops below the status bar even when the flow consumed it', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      // As inside the flow: the status bar is already taken off this context.
      home: Builder(builder: (outer) => MediaQuery.removePadding(
            context: outer,
            removeTop: true,
            child: Scaffold(body: Builder(builder: (c) => TextButton(
                  onPressed: () => showUiSheet<void>(c, isScrollControlled: true,
                      builder: (_) => const SingleChildScrollView(child: SizedBox(height: 2000, child: Text('tall')))),
                  child: const Text('open'),
                ))),
          )),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final panel = find.ancestor(
      of: find.text('tall'),
      matching: find.byWidgetPredicate((w) => w is Material && w.shape is RoundedRectangleBorder),
    ).first;
    expect(tester.getRect(panel).top, greaterThanOrEqualTo(59 + kUiSheetTopGap));
  });
}
