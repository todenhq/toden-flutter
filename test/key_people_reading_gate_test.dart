import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/document_people.dart';
import 'package:toden_flutter/src/widgets/icons/icons.dart';
import 'package:toden_flutter/src/widgets/key_people_reading_screen.dart';

// The key-people step's reading screen: shown while a company document is read
// for its people, "Found N people" for a moment when it lands, then the list.

Widget _host({required bool reading, int found = 0}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KeyPeopleReadingGate(
            reading: reading,
            found: found,
            child: const Text('the list'),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
      'explains the wait, then says how many were found, then shows the list',
      (tester) async {
    await tester.pumpWidget(_host(reading: true));
    expect(find.text(kReadingTitle), findsOneWidget);
    expect(find.text('the list'), findsNothing);

    await tester.pumpWidget(_host(reading: false, found: 2));
    await tester.pump();
    expect(find.text('Found 2 people'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1700));
    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets(
      'offers no way out by hand, and gives way on its own after a minute',
      (tester) async {
    await tester.pumpWidget(_host(reading: true));
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.text('the list'), findsNothing);
    await tester.pump(kReadingGiveUp + const Duration(seconds: 1));
    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets('settles one ticked card per person found, up to three',
      (tester) async {
    await tester.pumpWidget(_host(reading: true));
    await tester.pumpWidget(_host(reading: false, found: 1));
    await tester.pump();
    expect(find.text('Found 1 person'), findsOneWidget);
    // One tick on the status line, one on the single card.
    expect(
      find.byWidgetPredicate((w) => w is UiIcon && w.icon == UiIcons.check),
      findsNWidgets(2),
    );
    await tester.pump(const Duration(milliseconds: 1700));
  });

  testWidgets('is not shown when nothing is being read', (tester) async {
    await tester.pumpWidget(_host(reading: false));
    expect(find.text('the list'), findsOneWidget);
  });
}
