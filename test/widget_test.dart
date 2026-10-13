import 'package:flutter_test/flutter_test.dart';

import 'package:streambox/screens/browse_screen.dart';
import 'package:streambox/screens/browser_screen.dart';
import 'package:streambox/services/auth_service.dart';
import 'package:streambox/theme/app_theme.dart';

void main() {
  group('in-app downloads', () {
    test('direct file links are detected', () {
      expect(isDirectFileLink('https://cdn.example.com/movie.mkv'), isTrue);
      expect(isDirectFileLink('https://example.com/get.php?file=film.mp4'),
          isTrue);
      expect(isDirectFileLink('https://example.com/watch/123'), isFalse);
    });

    test('site key ignores sub-domains', () {
      expect(siteOf('cdn.example.com'), 'example.com');
      expect(siteOf('www.example.co.uk'), 'example.co.uk');
    });
  });

  group('browser address bar', () {
    test('web address opens as typed', () {
      expect(BrowseScreen.resolveInput('example.com/a'),
          'https://example.com/a');
      expect(BrowseScreen.resolveInput('https://example.com'),
          'https://example.com');
    });

    test('plain words become a search', () {
      expect(BrowseScreen.resolveInput('dune part two'),
          'https://www.google.com/search?q=dune+part+two');
      expect(BrowseScreen.resolveInput('   '), '');
    });
  });

  group('themes', () {
    test('nine themes with distinct accents', () {
      expect(Palettes.all.length, 9);
      expect({for (final p in Palettes.all) p.accent}.length, 9);
    });
  });

  group('gmail-only login', () {
    test('only gmail addresses pass', () {
      expect(AuthService.isGmail('jane.doe@gmail.com'), isTrue);
      expect(AuthService.isGmail('  Jane@GMAIL.com '), isTrue);
      expect(AuthService.isGmail('jane@googlemail.com'), isTrue);
      expect(AuthService.isGmail('jane@company.com'), isFalse);
      expect(AuthService.isGmail('jane@gmail.com.evil.io'), isFalse);
      expect(AuthService.isGmail(''), isFalse);
    });
  });
}
