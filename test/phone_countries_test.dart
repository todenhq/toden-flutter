import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/toden_flutter.dart';
import 'package:toden_flutter/src/config/theme.dart';
import 'package:toden_flutter/src/widgets/phone_number_input.dart';

// The phone field offers only the workflow's dial-code countries. Mirrors the
// web SDK's components/PhoneNumberInput.test.tsx.

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(extensions: const [UiColorScheme.light]),
      home: Scaffold(body: SizedBox(width: 390, child: child)),
    );

PhoneNumberInput _input({List<String>? countries, String defaultCountry = 'NG'}) =>
    PhoneNumberInput(
      defaultCountry: defaultCountry,
      countries: countries,
      autofocus: false,
      onChanged: (_, __) {},
    );

void main() {
  testWidgets('offers a picker when the workflow allows every country', (tester) async {
    await tester.pumpWidget(_host(_input(defaultCountry: 'NG')));
    expect(find.text('+234'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);
    await tester.tap(find.text('+234'));
    await tester.pumpAndSettle();
    expect(find.text('Country code'), findsOneWidget);
  });

  testWidgets('shows one country fixed, with no picker', (tester) async {
    await tester.pumpWidget(_host(_input(countries: const ['NG'], defaultCountry: 'GH')));
    expect(find.text('+234'), findsOneWidget);
    await tester.tap(find.text('+234'));
    await tester.pumpAndSettle();
    expect(find.text('Country code'), findsNothing);
  });

  testWidgets('starts on a country the workflow offers when the default is not one', (tester) async {
    await tester.pumpWidget(_host(_input(countries: const ['GH', 'KE'], defaultCountry: 'NG')));
    expect(find.text('+233'), findsOneWidget);
    expect(find.text('+234'), findsNothing);
    // The sheet lists only the offered countries.
    await tester.tap(find.text('+233'));
    await tester.pumpAndSettle();
    expect(find.text('Kenya'), findsOneWidget);
    expect(find.text('Nigeria'), findsNothing);
  });

  testWidgets('a list arriving late keeps the chosen code inside it', (tester) async {
    await tester.pumpWidget(_host(_input(defaultCountry: 'NG')));
    expect(find.text('+234'), findsOneWidget);
    await tester.pumpWidget(_host(_input(countries: const ['GH'], defaultCountry: 'NG')));
    await tester.pump();
    expect(find.text('+233'), findsOneWidget);
  });

  test('the workflow config carries the countries, upper case', () {
    final c = PhoneVerificationConfig.fromJson({'enabled': true, 'countries': ['ng', 'gh']});
    expect(c.countries, ['NG', 'GH']);
    expect(PhoneVerificationConfig.fromJson({'enabled': true}).countries, isEmpty);
    expect(phoneDialCountries(const []), isNull);
    expect(phoneStartCountry('ZA', const ['GH', 'KE']), 'GH');
    expect(phoneStartCountry('KE', const ['GH', 'KE']), 'KE');
  });
}
