import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/theme/app_themes.dart';

void main() {
  group('Qalam Muslim theme presets', () {
    test('light preset produces a light Material theme', () {
      final theme = buildThemeData('light');

      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor.computeLuminance(), greaterThan(0.7));
      expect(theme.colorScheme.onSurface.computeLuminance(), lessThan(0.3));
    });

    test('dark preset produces a dark Material theme', () {
      final theme = buildThemeData('dark');

      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor.computeLuminance(), lessThan(0.2));
      expect(theme.colorScheme.onSurface.computeLuminance(), greaterThan(0.7));
    });
  });
}
