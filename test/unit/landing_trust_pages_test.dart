import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('links the app install guide at an anchor the landing page has', () {
    expect(
      File('landing/src/components/Install.astro').readAsStringSync(),
      contains('id="install"'),
      reason:
          'AleraUpdateConfig.installGuideUrl targets https://alera.build/#install',
    );
    expect(
      File(
        'lib/src/features/updater/domain/alera_update.dart',
      ).readAsStringSync(),
      contains('https://alera.build/#install'),
    );
  });

  group('landing trust pages', () {
    // Mandated verbatim by the SignPath Foundation code of conduct, on the
    // project home page and the download page. Breaking it is a breach of the
    // sponsorship terms and nothing else would catch a careless edit.
    const String attribution =
        'Free code signing provided by SignPath.io, '
        'certificate by SignPath Foundation';

    test('carries the SignPath attribution everywhere it is required', () {
      for (final path in <String>[
        'landing/src/pages/download.astro',
        'landing/src/components/Install.astro',
        'readme.md',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains(attribution),
          reason: '$path must carry the attribution as one contiguous string',
        );
        expect(source, contains('https://about.signpath.io'));
        expect(source, contains('https://signpath.org'));
      }
    });

    test('does not send visitors to a third-party font host', () {
      expect(
        File('landing/src/layouts/Layout.astro').readAsStringSync(),
        isNot(anyOf(contains('fonts.googleapis'), contains('fonts.gstatic'))),
        reason: 'the privacy policy names Vercel as the only website processor',
      );
    });

    test('links home sections in a form that resolves from subpages', () {
      expect(
        File('landing/src/components/Navbar.astro').readAsStringSync(),
        isNot(contains('href="#')),
        reason: 'the download page uses this navbar',
      );
    });

    test('resolves every page the trust documents link to', () {
      for (final path in <String>[
        'landing/src/pages/privacy.astro',
        'landing/src/pages/terms.astro',
        'landing/src/pages/account/delete.astro',
        'landing/src/pages/download.astro',
      ]) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'a broken legal link is worse than no link',
        );
      }
    });
  });
}
