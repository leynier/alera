import 'package:alera/src/features/browser/presentation/browser_native_callback_scope.dart';
import 'package:alera/src/features/browser/presentation/browser_tab_surface.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'temporary certificate exceptions are limited to HTTPS local origins',
    () {
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://localhost:8443')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://192.168.1.20')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://10.4.2.1')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://0.0.0.0')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://service.local')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(
          Uri.parse('https://[0:0:0:0:0:0:0:1]'),
        ),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://[fe80::1]')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://example.com')),
        isFalse,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://[fec0::1]')),
        isFalse,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('https://[febf::1]')),
        isTrue,
      );
      expect(
        isTemporaryLocalCertificateOrigin(Uri.parse('http://localhost:8080')),
        isFalse,
      );
    },
  );

  test('download names cannot escape the selected directory', () {
    expect(safeBrowserDownloadFileName('../secret.txt'), '.._secret.txt');
    expect(
      safeBrowserDownloadFileName(r'folder\secret.txt'),
      'folder_secret.txt',
    );
    expect(safeBrowserDownloadFileName('  '), 'download');
  });

  test('external browser action accepts only web URLs', () {
    expect(
      canOpenBrowserUrlExternally(Uri.parse('https://example.com/path')),
      isTrue,
    );
    expect(
      canOpenBrowserUrlExternally(Uri.parse('http://localhost:3000')),
      isTrue,
    );
    expect(canOpenBrowserUrlExternally(Uri.parse('about:blank')), isFalse);
    expect(canOpenBrowserUrlExternally(.file('/tmp/file.html')), isFalse);
  });
}
