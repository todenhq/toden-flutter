import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toden_flutter/src/config/body_font.dart';

void main() {
  test('body text is set in the Geist face this package bundles', () {
    final style = bodyFont(const TextStyle(fontSize: 16, fontWeight: FontWeight.w500));
    expect(style.fontFamily, 'packages/$kBodyFontPackage/$kBodyFontFamily');
    expect(style.fontSize, 16);
    expect(style.fontWeight, FontWeight.w500);
  });

  test('the package name matches pubspec, or the font would silently not resolve', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('name: $kBodyFontPackage'));
  });

  test('every weight the SDK names is declared in pubspec and shipped', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: $kBodyFontFamily'));
    for (final weight in kBodyFontWeights) {
      final match = RegExp('asset: (assets/fonts/Geist_$weight\\w+\\.ttf)\\s+weight: $weight').firstMatch(pubspec);
      expect(match, isNotNull, reason: 'weight $weight is not declared');
      expect(File(match!.group(1)!).existsSync(), isTrue, reason: '${match.group(1)} is missing');
    }
  });

  test('the heading face is bundled too: every weight is declared and shipped', () {
    final style = headingFont(const TextStyle(fontSize: 20, fontWeight: FontWeight.w600));
    expect(style.fontFamily, 'packages/$kBodyFontPackage/$kHeadingFontFamily');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('- family: $kHeadingFontFamily'));
    for (final weight in kHeadingFontWeights) {
      final match =
          RegExp('asset: (assets/fonts/BricolageGrotesque_$weight\\w+\\.ttf)\\s+weight: $weight').firstMatch(pubspec);
      expect(match, isNotNull, reason: 'weight $weight is not declared');
      expect(File(match!.group(1)!).existsSync(), isTrue, reason: '${match.group(1)} is missing');
    }
  });

  test('no default text style fetches a font over the network', () {
    final theme = File('lib/src/config/theme.dart').readAsStringSync();
    expect(theme, isNot(contains('GoogleFonts.bricolageGrotesque')));
  });

  test('the theme sends small text and fields to Geist, and headings and 16px text to Bricolage Grotesque', () {
    final theme = File('lib/src/config/theme.dart').readAsStringSync();
    final small = RegExp(r'_bodyFontFamily,\s+bodyFont,').allMatches(theme).length;
    final heading = RegExp(r'_headingFontFamily,\s+headingFont,').allMatches(theme).length;
    final largeCopy = RegExp(r'_bodyFontFamily,\s+headingFont,').allMatches(theme).length;
    // bodyMedium, bodySmall and label in both classes, plus the input style.
    expect(small, 7);
    expect(heading, 6);
    // body and button (both 16px) in both classes. An org's body font still wins.
    expect(largeCopy, 4);
  });
}
