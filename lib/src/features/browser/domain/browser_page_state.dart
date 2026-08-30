import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';

enum BrowserLoadPhase { started, committed, finished, failed }

enum BrowserEngineAvailability { available, degraded, unavailable }

final class const BrowserPageState({
  required final BrowserPage page,
  required final Uri url,
  required final String title,
  required final BrowserLoadPhase loadPhase,
  required final bool canGoBack,
  required final bool canGoForward,
  required final BrowserSecurityState security,
  required final List<BrowserDownload> downloads,
  required final BrowserEngineAvailability engineAvailability,
  required final DateTime updatedAt,
  final double? loadProgress,
  final BrowserFailure? error,
  final String? capabilityReason,
}) {
  factory initial(
    BrowserPage page, {
    BrowserEngineAvailability availability =
        BrowserEngineAvailability.available,
    String? capabilityReason,
  }) {
    return BrowserPageState(
      page: page,
      url: page.initialUrl,
      title: '',
      loadPhase: .finished,
      loadProgress: null,
      canGoBack: false,
      canGoForward: false,
      security: .unknown,
      downloads: const <BrowserDownload>[],
      engineAvailability: availability,
      capabilityReason: capabilityReason,
      updatedAt: page.createdAt,
    );
  }

  String get pageId => page.pageId;

  String get workspaceId => page.workspaceId;

  String get profileId => page.profileId;

  bool get isLoading =>
      loadPhase == BrowserLoadPhase.started ||
      loadPhase == BrowserLoadPhase.committed;

  BrowserPageState copyWith({
    BrowserPage? page,
    Uri? url,
    String? title,
    BrowserLoadPhase? loadPhase,
    double? loadProgress,
    bool clearLoadProgress = false,
    bool? canGoBack,
    bool? canGoForward,
    BrowserSecurityState? security,
    BrowserFailure? error,
    bool clearError = false,
    List<BrowserDownload>? downloads,
    BrowserEngineAvailability? engineAvailability,
    String? capabilityReason,
    bool clearCapabilityReason = false,
    DateTime? updatedAt,
  }) {
    return BrowserPageState(
      page: page ?? this.page,
      url: url ?? this.url,
      title: title ?? this.title,
      loadPhase: loadPhase ?? this.loadPhase,
      loadProgress: clearLoadProgress
          ? null
          : (loadProgress ?? this.loadProgress),
      canGoBack: canGoBack ?? this.canGoBack,
      canGoForward: canGoForward ?? this.canGoForward,
      security: security ?? this.security,
      error: clearError ? null : (error ?? this.error),
      downloads: List<BrowserDownload>.unmodifiableOf(
        downloads ?? this.downloads,
      ),
      engineAvailability: engineAvailability ?? this.engineAvailability,
      capabilityReason: clearCapabilityReason
          ? null
          : (capabilityReason ?? this.capabilityReason),
      updatedAt: updatedAt?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}

final class const BrowserSurfaceToken(final String pageId);
