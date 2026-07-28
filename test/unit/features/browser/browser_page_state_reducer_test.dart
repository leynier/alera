import 'package:alera/src/features/browser/application/browser_page_state_reducer.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('about blank starts finished and not loading', () {
    final state = _state();

    expect(state.url.toString(), 'about:blank');
    expect(state.loadPhase, BrowserLoadPhase.finished);
    expect(state.isLoading, isFalse);
  });

  test('navigation advances through started committed and finished', () {
    final state = _state();
    final url = Uri.parse('https://example.com');

    final started = reduceBrowserPageEvent(
      state,
      BrowserNavigationStarted(
        pageId: state.pageId,
        occurredAt: DateTime.utc(2026, 1, 2),
        url: url,
      ),
    );
    expect(started.loadPhase, BrowserLoadPhase.started);
    expect(started.isLoading, isTrue);
    expect(started.security.level, BrowserSecurityLevel.unknown);

    final committed = reduceBrowserPageEvent(
      started,
      BrowserNavigationCommitted(
        pageId: state.pageId,
        occurredAt: DateTime.utc(2026, 1, 3),
        url: url,
      ),
    );
    expect(committed.loadPhase, BrowserLoadPhase.committed);
    expect(committed.isLoading, isTrue);
    expect(committed.security.level, BrowserSecurityLevel.secure);

    final finished = reduceBrowserPageEvent(
      committed,
      BrowserNavigationFinished(
        pageId: state.pageId,
        occurredAt: DateTime.utc(2026, 1, 4),
        url: url,
        title: 'Example',
      ),
    );
    expect(finished.loadPhase, BrowserLoadPhase.finished);
    expect(finished.isLoading, isFalse);
  });

  test(
    'committed URLs expose secure, insecure, and local connection state',
    () {
      expect(
        _finished('https://example.com').security.level,
        BrowserSecurityLevel.secure,
      );
      expect(
        _finished('http://example.com').security.level,
        BrowserSecurityLevel.insecure,
      );
      expect(
        _finished('http://localhost:8080').security.level,
        BrowserSecurityLevel.local,
      );
    },
  );

  test('navigation clears the previous committed security state', () {
    final secure = _finished('https://example.com');

    final loading = reduceBrowserPageEvent(
      secure,
      BrowserNavigationStarted(
        pageId: secure.pageId,
        occurredAt: DateTime.utc(2026, 1, 2),
        url: Uri.parse('https://other.example'),
      ),
    );

    expect(loading.security.level, BrowserSecurityLevel.unknown);
    expect(loading.security.origin, 'https://other.example');
  });

  test(
    'certificate load failures are distinguished from ordinary failures',
    () {
      final state = _state();

      final failed = reduceBrowserPageEvent(
        state,
        BrowserLoadFailed(
          pageId: state.pageId,
          occurredAt: DateTime.utc(2026, 1, 2),
          url: Uri.parse('https://example.com'),
          failure: const BrowserFailure(
            code: BrowserErrorCode.certificateRejected,
            message: 'The TLS certificate was rejected.',
          ),
        ),
      );

      expect(failed.security.level, BrowserSecurityLevel.certificateFailure);
      expect(failed.security.origin, 'https://example.com');
      expect(failed.loadPhase, BrowserLoadPhase.failed);
      expect(failed.isLoading, isFalse);
    },
  );

  test('late progress cannot change a finished or failed load', () {
    final finished = _finished('https://example.com');
    final lateProgress = BrowserProgressChanged(
      pageId: finished.pageId,
      occurredAt: DateTime.utc(2026, 1, 4),
      progress: 1,
    );

    expect(
      identical(reduceBrowserPageEvent(finished, lateProgress), finished),
      isTrue,
    );

    final failed = reduceBrowserPageEvent(
      finished,
      BrowserLoadFailed(
        pageId: finished.pageId,
        occurredAt: DateTime.utc(2026, 1, 5),
        failure: const BrowserFailure(
          code: BrowserErrorCode.unknown,
          message: 'Load failed.',
        ),
      ),
    );
    expect(
      identical(reduceBrowserPageEvent(failed, lateProgress), failed),
      isTrue,
    );
  });

  test('download progress preserves its original metadata', () {
    final state = _state();
    final startedAt = DateTime.utc(2026, 1, 2);
    final requested = reduceBrowserPageEvent(
      state,
      BrowserDownloadChanged(
        pageId: state.pageId,
        occurredAt: startedAt,
        download: BrowserDownload(
          id: 'download-1',
          pageId: state.pageId,
          fileName: 'report.pdf',
          status: BrowserDownloadStatus.pending,
          receivedBytes: 0,
          totalBytes: 24,
          savePath: '/tmp/report.pdf',
          startedAt: startedAt,
        ),
      ),
    );

    final progressed = reduceBrowserPageEvent(
      requested,
      BrowserDownloadChanged(
        pageId: state.pageId,
        occurredAt: DateTime.utc(2026, 1, 3),
        download: BrowserDownload(
          id: 'download-1',
          pageId: state.pageId,
          fileName: 'download-1',
          status: BrowserDownloadStatus.downloading,
          receivedBytes: 12,
          startedAt: DateTime.utc(2026, 1, 3),
        ),
      ),
    );

    expect(progressed.downloads.single.fileName, 'report.pdf');
    expect(progressed.downloads.single.savePath, '/tmp/report.pdf');
    expect(progressed.downloads.single.totalBytes, 24);
    expect(progressed.downloads.single.startedAt, startedAt);
  });
}

BrowserPageState _finished(String rawUrl) {
  final state = _state();
  final committed = reduceBrowserPageEvent(
    state,
    BrowserNavigationCommitted(
      pageId: state.pageId,
      occurredAt: DateTime.utc(2026, 1, 2),
      url: Uri.parse(rawUrl),
    ),
  );
  return reduceBrowserPageEvent(
    committed,
    BrowserNavigationFinished(
      pageId: state.pageId,
      occurredAt: DateTime.utc(2026, 1, 3),
      url: Uri.parse(rawUrl),
      title: 'Example',
    ),
  );
}

BrowserPageState _state() {
  return BrowserPageState.initial(
    BrowserPage(
      pageId: 'page-1',
      workspaceId: 'workspace-1',
      profileId: 'default',
      initialUrl: Uri.parse('about:blank'),
      createdAt: DateTime.utc(2026),
    ),
  );
}
