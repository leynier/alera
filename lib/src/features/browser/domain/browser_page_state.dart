import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';

enum BrowserLoadPhase { started, committed, finished, failed }

enum BrowserEngineAvailability { available, degraded, unavailable }

final class BrowserPageState {
  const BrowserPageState({
    required this.page,
    required this.url,
    required this.title,
    required this.loadPhase,
    required this.canGoBack,
    required this.canGoForward,
    required this.security,
    required this.downloads,
    required this.engineAvailability,
    required this.updatedAt,
    this.loadProgress,
    this.error,
    this.capabilityReason,
  });

  factory BrowserPageState.initial(
    BrowserPage page, {
    BrowserEngineAvailability availability =
        BrowserEngineAvailability.available,
    String? capabilityReason,
  }) {
    return BrowserPageState(
      page: page,
      url: page.initialUrl,
      title: '',
      loadPhase: BrowserLoadPhase.finished,
      loadProgress: null,
      canGoBack: false,
      canGoForward: false,
      security: BrowserSecurityState.unknown,
      downloads: const <BrowserDownload>[],
      engineAvailability: availability,
      capabilityReason: capabilityReason,
      updatedAt: page.createdAt,
    );
  }

  final BrowserPage page;
  final Uri url;
  final String title;
  final BrowserLoadPhase loadPhase;
  final double? loadProgress;
  final bool canGoBack;
  final bool canGoForward;
  final BrowserSecurityState security;
  final BrowserFailure? error;
  final List<BrowserDownload> downloads;
  final BrowserEngineAvailability engineAvailability;
  final String? capabilityReason;
  final DateTime updatedAt;

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
      downloads: List<BrowserDownload>.unmodifiable(
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

final class BrowserSurfaceToken {
  const BrowserSurfaceToken(this.pageId);

  final String pageId;
}
