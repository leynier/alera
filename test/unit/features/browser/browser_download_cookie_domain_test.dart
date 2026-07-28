import 'package:alera/src/features/browser/domain/browser_cookie.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('browser downloads', () {
    test('request and decisions retain values and enforce a real path', () {
      final requestedAt = DateTime.utc(2026, 7, 27);
      final request = BrowserDownloadRequest(
        pageId: 'page-1',
        url: Uri.parse('https://example.com/report.pdf'),
        requestedAt: requestedAt,
        suggestedFileName: 'report.pdf',
        mimeType: 'application/pdf',
        totalBytes: 42,
      );
      final minimal = BrowserDownloadRequest(
        pageId: 'page-2',
        url: Uri.parse('https://example.com/file'),
        requestedAt: requestedAt,
      );

      expect(request.pageId, 'page-1');
      expect(request.url.path, '/report.pdf');
      expect(request.requestedAt, requestedAt);
      expect(request.suggestedFileName, 'report.pdf');
      expect(request.mimeType, 'application/pdf');
      expect(request.totalBytes, 42);
      expect(minimal.suggestedFileName, isNull);
      expect(minimal.mimeType, isNull);
      expect(minimal.totalBytes, isNull);
      expect(const BrowserDownloadDecision.deny().accepted, isFalse);
      expect(const BrowserDownloadDecision.accept('').accepted, isFalse);
      expect(const BrowserDownloadDecision.accept('  ').accepted, isFalse);
      final destinationPath = '/tmp/report.pdf';
      expect(BrowserDownloadDecision.accept(destinationPath).accepted, isTrue);
    });

    test('download JSON round trips complete and minimal payloads', () {
      final download = BrowserDownload.fromJson(<String, Object?>{
        'id': 'download-1',
        'pageId': 'page-1',
        'fileName': 'report.pdf',
        'status': 'completed',
        'receivedBytes': 40.9,
        'totalBytes': 40.2,
        'savePath': '/tmp/report.pdf',
        'error': 'none',
        'startedAt': '2026-07-27T12:00:00-05:00',
      });

      expect(download.status, BrowserDownloadStatus.completed);
      expect(download.receivedBytes, 40);
      expect(download.totalBytes, 40);
      expect(download.startedAt, DateTime.utc(2026, 7, 27, 17));
      expect(download.progress, 1);
      expect(download.isTerminal, isTrue);
      expect(download.toJson(), <String, Object?>{
        'id': 'download-1',
        'pageId': 'page-1',
        'fileName': 'report.pdf',
        'status': 'completed',
        'receivedBytes': 40,
        'totalBytes': 40,
        'savePath': '/tmp/report.pdf',
        'error': 'none',
        'startedAt': '2026-07-27T17:00:00.000Z',
      });

      final minimal = BrowserDownload.fromJson(<String, Object?>{
        'id': 'download-2',
        'pageId': 'page-1',
        'fileName': 'file.bin',
        'status': 'future',
        'startedAt': '2026-07-27T17:00:00Z',
      });
      expect(minimal.status, BrowserDownloadStatus.failed);
      expect(minimal.receivedBytes, 0);
      expect(minimal.totalBytes, isNull);
      expect(minimal.savePath, isNull);
      expect(minimal.error, isNull);
      expect(minimal.toJson(), isNot(contains('totalBytes')));
      expect(minimal.toJson(), isNot(contains('savePath')));
      expect(minimal.toJson(), isNot(contains('error')));
    });

    test('download JSON rejects malformed required fields', () {
      final valid = <String, Object?>{
        'id': 'download',
        'pageId': 'page',
        'fileName': 'file.bin',
        'startedAt': '2026-07-27T17:00:00Z',
      };
      for (final entry in <MapEntry<String, Object?>>[
        const MapEntry<String, Object?>('id', 1),
        const MapEntry<String, Object?>('pageId', 1),
        const MapEntry<String, Object?>('fileName', 1),
        const MapEntry<String, Object?>('startedAt', 'invalid'),
      ]) {
        expect(
          () => BrowserDownload.fromJson(<String, Object?>{
            ...valid,
            entry.key: entry.value,
          }),
          throwsFormatException,
        );
      }
    });

    test('progress and terminal status cover every branch', () {
      BrowserDownload download({
        required BrowserDownloadStatus status,
        required int received,
        int? total,
      }) {
        return BrowserDownload(
          id: status.name,
          pageId: 'page',
          fileName: 'file',
          status: status,
          receivedBytes: received,
          totalBytes: total,
          startedAt: DateTime.utc(2026),
        );
      }

      expect(
        download(status: BrowserDownloadStatus.pending, received: 1).progress,
        isNull,
      );
      expect(
        download(
          status: BrowserDownloadStatus.pending,
          received: 1,
          total: 0,
        ).progress,
        isNull,
      );
      expect(
        download(
          status: BrowserDownloadStatus.downloading,
          received: -2,
          total: 10,
        ).progress,
        0,
      );
      expect(
        download(
          status: BrowserDownloadStatus.downloading,
          received: 5,
          total: 10,
        ).progress,
        0.5,
      );
      expect(
        download(
          status: BrowserDownloadStatus.completed,
          received: 20,
          total: 10,
        ).progress,
        1,
      );
      for (final status in BrowserDownloadStatus.values) {
        expect(
          download(status: status, received: 0).isTerminal,
          <BrowserDownloadStatus>{
            BrowserDownloadStatus.completed,
            BrowserDownloadStatus.cancelled,
            BrowserDownloadStatus.failed,
          }.contains(status),
          reason: status.name,
        );
      }
    });
  });

  group('browser cookies', () {
    test('cookie JSON round trips full values and UTC expiry', () {
      final cookie = BrowserCookie.fromJson(<String, Object?>{
        'name': 'session',
        'value': 'secret',
        'domain': '.example.com',
        'path': '/account',
        'secure': true,
        'httpOnly': true,
        'sameSite': 'strict',
        'expiresAt': '2026-07-27T12:00:00-05:00',
      });

      expect(cookie.name, 'session');
      expect(cookie.value, 'secret');
      expect(cookie.domain, '.example.com');
      expect(cookie.path, '/account');
      expect(cookie.secure, isTrue);
      expect(cookie.httpOnly, isTrue);
      expect(cookie.sameSite, BrowserCookieSameSite.strict);
      expect(cookie.expiresAt, DateTime.utc(2026, 7, 27, 17));
      expect(cookie.toJson(), <String, Object?>{
        'name': 'session',
        'value': 'secret',
        'domain': '.example.com',
        'path': '/account',
        'secure': true,
        'httpOnly': true,
        'sameSite': 'strict',
        'expiresAt': '2026-07-27T17:00:00.000Z',
      });
      expect(cookie.toJson(includeValue: false), isNot(contains('value')));
    });

    test('cookie JSON uses defaults and rejects missing identity fields', () {
      final cookie = BrowserCookie.fromJson(<String, Object?>{
        'name': 'theme',
        'value': 'dark',
        'domain': 'example.com',
        'sameSite': 'future',
        'expiresAt': 'invalid',
      });

      expect(cookie.path, '/');
      expect(cookie.secure, isFalse);
      expect(cookie.httpOnly, isFalse);
      expect(cookie.sameSite, BrowserCookieSameSite.unspecified);
      expect(cookie.expiresAt, isNull);
      expect(cookie.toJson(), isNot(contains('expiresAt')));

      for (final invalid in <Map<String, Object?>>[
        <String, Object?>{'value': 'v', 'domain': 'example.com'},
        <String, Object?>{'name': 'n', 'domain': 'example.com'},
        <String, Object?>{'name': 'n', 'value': 'v'},
      ]) {
        expect(() => BrowserCookie.fromJson(invalid), throwsFormatException);
      }
    });

    test('direct construction exposes all default cookie attributes', () {
      const cookie = BrowserCookie(
        name: 'name',
        value: 'value',
        domain: 'example.com',
      );

      expect(cookie.path, '/');
      expect(cookie.secure, isFalse);
      expect(cookie.httpOnly, isFalse);
      expect(cookie.sameSite, BrowserCookieSameSite.unspecified);
      expect(cookie.expiresAt, isNull);
    });
  });
}
