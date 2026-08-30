import 'dart:async';
import 'dart:io';

import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/browser/application/browser_native_callback_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_providers.dart';
import 'package:alera/src/features/browser/domain/browser_download.dart';
import 'package:alera/src/features/browser/domain/browser_permission.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/domain/browser_security.dart';
import 'package:alera/src/features/browser/domain/browser_trusted_certificate.dart';
import 'package:alera/src/features/browser/presentation/browser_certificate_trust_dialog.dart';
import 'package:alera/src/features/browser/presentation/browser_permission_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const BrowserNativeCallbackScope({super.key, required final Widget child})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<BrowserNativeCallbackScope> createState() =>
      _BrowserNativeCallbackScopeState();
}

class _BrowserNativeCallbackScopeState
    extends ConsumerState<BrowserNativeCallbackScope> {
  BrowserCallbackRegistration? _registration;

  @override
  void initState() {
    super.initState();
    _registration = ref
        .read(browserNativeCallbackCoordinatorProvider)
        .register(
          BrowserNativeCallbackHandlers(
            permission: _decidePermission,
            tls: _decideTls,
            download: _decideDownload,
          ),
        );
  }

  @override
  void dispose() {
    _registration?.dispose();
    super.dispose();
  }

  Future<BrowserPermissionDecision> _decidePermission(
    BrowserPermissionRequest request,
    BrowserCallbackCancellation cancellation,
  ) async {
    final handle = ref
        .read(browserSessionRegistryProvider)
        .handleForPageId(request.pageId);
    if (handle == null || !mounted || cancellation.isCancelled) {
      return BrowserPermissionDecision.deny;
    }
    final permissionService = ref.read(browserPermissionServiceProvider);
    final remembered = await permissionService.decisionFor(
      profileId: handle.state.profileId,
      origin: request.origin,
      permission: request.permission,
    );
    if (cancellation.isCancelled) {
      return BrowserPermissionDecision.deny;
    }
    if (remembered != BrowserPermissionDecision.ask) {
      return remembered;
    }
    final profileLabel = await _profileLabel(handle.state.profileId);
    if (!mounted || cancellation.isCancelled) {
      return BrowserPermissionDecision.deny;
    }
    final result = await handle.withFlutterOverlay(
      () => _showCancellableDialog<BrowserPermissionPromptResult>(
        cancellation,
        builder: (_) => BrowserPermissionDialog(
          request: request,
          profileLabel: profileLabel,
        ),
      ),
    );
    if (cancellation.isCancelled) {
      return BrowserPermissionDecision.deny;
    }
    final decision = result?.decision ?? BrowserPermissionDecision.deny;
    if (result?.rememberForProfile == true) {
      unawaited(
        _rememberPermission(
          cancellation: cancellation,
          profileId: handle.state.profileId,
          origin: request.origin,
          permission: request.permission,
          decision: decision,
        ),
      );
    }
    return decision;
  }

  Future<void> _rememberPermission({
    required BrowserCallbackCancellation cancellation,
    required String profileId,
    required String origin,
    required BrowserPermissionType permission,
    required BrowserPermissionDecision decision,
  }) async {
    await Future.pause(.zero);
    if (cancellation.isCancelled) {
      return;
    }
    try {
      await ref
          .read(browserPermissionServiceProvider)
          .remember(
            profileId: profileId,
            origin: origin,
            permission: permission,
            decision: decision,
          );
    } on Object {
      // The one-time decision remains valid if persistence is unavailable.
    }
  }

  Future<String> _profileLabel(String profileId) async {
    try {
      final profiles = await ref.read(browserProfileServiceProvider).list();
      for (final profile in profiles) {
        if (profile.id == profileId) {
          return profile.label;
        }
      }
    } on Object {
      // A missing catalog must not prevent the permission prompt.
    }
    return profileId == 'default' ? 'Default Profile' : 'This Profile';
  }

  Future<bool> _decideTls(
    BrowserTlsRequest request,
    BrowserCallbackCancellation cancellation,
  ) async {
    final url = request.url;
    final handle = ref
        .read(browserSessionRegistryProvider)
        .handleForPageId(request.pageId);
    if (url == null ||
        handle == null ||
        !isTemporaryLocalCertificateOrigin(url) ||
        normalizeBrowserCertificateHost(request.host) !=
            normalizeBrowserCertificateHost(url.host) ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(request.fingerprintSha256) ||
        request.errors.length != 1 ||
        !request.errors.contains(BrowserTlsErrorType.untrustedIssuer) ||
        !mounted ||
        cancellation.isCancelled) {
      return false;
    }
    final profileId = handle.state.profileId;
    final registry = ref.read(browserCertificateTrustRegistryProvider);
    if (await registry.isTrusted(
      profileId: profileId,
      host: request.host,
      fingerprintSha256: request.fingerprintSha256,
    )) {
      return !cancellation.isCancelled;
    }
    final profiles = await ref.read(browserProfileServiceProvider).list();
    BrowserProfile? profile;
    for (final value in profiles) {
      if (value.id == profileId) {
        profile = value;
        break;
      }
    }
    if (!mounted || cancellation.isCancelled) {
      return false;
    }
    final choice = await handle
        .withFlutterOverlay<BrowserCertificateTrustChoice?>(
          () => _showCancellableDialog<BrowserCertificateTrustChoice>(
            cancellation,
            builder: (_) => BrowserCertificateTrustDialog(
              request: request,
              profileLabel: profile?.label ?? _profileFallback(profileId),
              canPersist: profile?.persistent == true,
            ),
          ),
        );
    if (cancellation.isCancelled ||
        choice == null ||
        choice == BrowserCertificateTrustChoice.cancel) {
      return false;
    }
    if (choice == BrowserCertificateTrustChoice.session) {
      registry.trustForSession(
        profileId: profileId,
        host: request.host,
        fingerprintSha256: request.fingerprintSha256,
      );
      return true;
    }
    try {
      final now = DateTime.now().toUtc();
      await registry.trustPermanently(
        BrowserTrustedCertificate(
          profileId: profileId,
          host: normalizeBrowserCertificateHost(request.host),
          fingerprintSha256: normalizeBrowserCertificateFingerprint(
            request.fingerprintSha256,
          ),
          subject: request.subject,
          issuer: request.issuer,
          validFrom: request.validFrom,
          validTo: request.validTo,
          createdAt: now,
          lastUsedAt: now,
        ),
      );
      return !cancellation.isCancelled;
    } on Object {
      if (mounted) {
        AleraToast.show(
          context,
          message:
              'The certificate could not be saved. Navigation was blocked.',
          tone: .error,
        );
      }
      return false;
    }
  }

  Future<BrowserDownloadDecision> _decideDownload(
    BrowserDownloadRequest request,
    BrowserCallbackCancellation cancellation,
  ) async {
    final handle = ref
        .read(browserSessionRegistryProvider)
        .handleForPageId(request.pageId);
    if (handle == null || !mounted || cancellation.isCancelled) {
      return const BrowserDownloadDecision.deny();
    }
    final suggestedName = safeBrowserDownloadFileName(
      request.suggestedFileName,
    );
    final location = await handle.withFlutterOverlay(
      () => getSaveLocation(
        suggestedName: suggestedName,
        confirmButtonText: 'Save Download',
        canCreateDirectories: true,
      ),
    );
    return location == null || cancellation.isCancelled
        ? const BrowserDownloadDecision.deny()
        : BrowserDownloadDecision.accept(location.path);
  }

  Future<T?> _showCancellableDialog<T>(
    BrowserCallbackCancellation cancellation, {
    required WidgetBuilder builder,
  }) {
    if (cancellation.isCancelled) {
      return Future<T?>.value();
    }
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        unawaited(
          cancellation.whenCancelled.then((_) {
            if (!dialogContext.mounted) {
              return;
            }
            final route = ModalRoute.of(dialogContext);
            if (route?.isCurrent ?? false) {
              Navigator.of(dialogContext).pop();
            }
          }),
        );
        return builder(dialogContext);
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

String _profileFallback(String profileId) =>
    profileId == 'default' ? 'Default Profile' : 'This Profile';

@visibleForTesting
bool isTemporaryLocalCertificateOrigin(Uri uri) {
  if (uri.scheme != 'https' || uri.host.isEmpty) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host == '0.0.0.0' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local')) {
    return true;
  }
  final address = InternetAddress.tryParse(host);
  return address?.isLoopback == true ||
      _isLinkLocalAddress(address) ||
      _isPrivateIpv4(address);
}

bool _isLinkLocalAddress(InternetAddress? address) {
  if (address == null) {
    return false;
  }
  final bytes = address.rawAddress;
  return switch (address.type) {
    InternetAddressType.IPv4 => bytes[0] == 169 && bytes[1] == 254,
    InternetAddressType.IPv6 => bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80,
    _ => false,
  };
}

bool _isPrivateIpv4(InternetAddress? address) {
  if (address == null || address.type != InternetAddressType.IPv4) {
    return false;
  }
  final bytes = address.rawAddress;
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

@visibleForTesting
String safeBrowserDownloadFileName(String? value) {
  final normalized = value?.trim().replaceAll(RegExp(r'[/\\:\x00-\x1f]'), '_');
  if (normalized == null ||
      normalized.isEmpty ||
      normalized == '.' ||
      normalized == '..') {
    return 'download';
  }
  return normalized.length > 180 ? normalized.substring(0, 180) : normalized;
}
