part of 'mobile_codex_chat_screen.dart';

class _MobileCodexWorkspaceScope extends InheritedWidget {
  const _MobileCodexWorkspaceScope({
    required this.hostId,
    required this.workspaceId,
    required this.cwd,
    required super.child,
  });

  final String hostId;
  final String workspaceId;
  final String? cwd;

  static _MobileCodexWorkspaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MobileCodexWorkspaceScope>();

  @override
  bool updateShouldNotify(_MobileCodexWorkspaceScope oldWidget) =>
      hostId != oldWidget.hostId ||
      workspaceId != oldWidget.workspaceId ||
      cwd != oldWidget.cwd;
}

@visibleForTesting
class MobileCodexWorkspaceLinkTarget {
  const MobileCodexWorkspaceLinkTarget({
    required this.path,
    this.line,
    this.displayName,
  });

  final String path;
  final int? line;
  final String? displayName;
}

Future<void> _openMobileCodexPath(
  BuildContext context,
  String raw, {
  String? displayName,
  String? cwd,
  bool parseLineReferences = false,
}) async {
  final value = raw.trim();
  if (value.isEmpty) return;
  final target = mobileCodexPathTarget(
    value,
    parseLineReferences: parseLineReferences,
  );
  final localLineReference =
      parseLineReferences &&
      target.line != null &&
      _isMobileCodexLocalLineReference(value);
  final uri = Uri.tryParse(value);
  if (!localLineReference &&
      uri != null &&
      mobileCodexShouldLaunchExternalUri(value, uri)) {
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        _reportMobileCodexLinkFailure(context, uri);
      }
    } on Object catch (error, stackTrace) {
      if (context.mounted) {
        _reportMobileCodexLinkFailure(context, uri, error, stackTrace);
      } else {
        _MobileCodexChatScreenState._logger.warning(
          'Could not open link. URL: $uri',
          error,
          stackTrace,
        );
      }
    }
    return;
  }
  try {
    final scope = _MobileCodexWorkspaceScope.maybeOf(context);
    if (scope == null) return;
    if (target.path.isEmpty) return;
    final client = await ProviderScope.containerOf(
      context,
    ).read(mobileCodexClientProvider(scope.hostId).future);
    if (!context.mounted) return;
    if (client is! MobileCodexWorkspaceClient) {
      _reportMobileCodexPreviewUnavailable(context);
      return;
    }
    final workspaceClient = client as MobileCodexWorkspaceClient;
    final effectiveCwd = cwd?.trim().isNotEmpty == true
        ? cwd!.trim()
        : scope.cwd;
    final workspacePath = mobileCodexWorkspaceRelativePath(
      path: target.path,
      cwd: effectiveCwd,
    );
    final unresolvedAbsolutePath =
        workspacePath == null && _isAbsoluteMobileCodexPath(target.path);
    final usePromptAttachment =
        unresolvedAbsolutePath && !workspaceClient.supportsCodexWorkspaceFiles;
    if (usePromptAttachment
        ? !workspaceClient.supportsPromptAttachmentRead
        : !workspaceClient.supportsCodexWorkspaceFiles) {
      _reportMobileCodexPreviewUnavailable(context);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _MobileWorkspaceFileViewer(
          client: workspaceClient,
          workspaceId: scope.workspaceId,
          cwd: effectiveCwd,
          target: MobileCodexWorkspaceLinkTarget(
            path: workspacePath ?? target.path,
            line: target.line,
            displayName: displayName,
          ),
          promptAttachment: usePromptAttachment,
          fallbackToPromptAttachment:
              unresolvedAbsolutePath &&
              workspaceClient.supportsCodexWorkspaceFiles &&
              workspaceClient.supportsPromptAttachmentRead,
        ),
      ),
    );
  } on Object catch (error, stackTrace) {
    if (context.mounted) {
      _reportMobileCodexLinkFailure(context, value, error, stackTrace);
    } else {
      _MobileCodexChatScreenState._logger.warning(
        'Could not open link. Target: $value',
        error,
        stackTrace,
      );
    }
  }
}

void _reportMobileCodexPreviewUnavailable(BuildContext context) {
  const message = 'File preview requires a newer Alera runtime.';
  _MobileCodexChatScreenState._logger.warning(message);
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(const SnackBar(content: Text(message)));
}

@visibleForTesting
bool mobileCodexShouldLaunchExternalUri(String raw, Uri uri) =>
    const <String>{
      'http',
      'https',
      'mailto',
      'tel',
      'sms',
    }.contains(uri.scheme.toLowerCase()) &&
    !_isAbsoluteMobileCodexPath(raw.replaceAll('\\', '/'));

bool _isMobileCodexLocalLineReference(String value) {
  final normalized = value.replaceAll('\\', '/');
  if (_isAbsoluteMobileCodexPath(normalized)) return true;
  if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(value)) {
    return false;
  }
  if (RegExp(r'^(?:mailto|tel|sms):', caseSensitive: false).hasMatch(value)) {
    return false;
  }
  return RegExp(r':\d+(?::\d+)?(?:#.*)?$').hasMatch(normalized);
}

@visibleForTesting
MobileCodexWorkspaceLinkTarget mobileCodexPathTarget(
  String raw, {
  required bool parseLineReferences,
}) {
  if (parseLineReferences) return parseMobileCodexWorkspaceLink(raw);
  return MobileCodexWorkspaceLinkTarget(path: raw.replaceAll('\\', '/'));
}

void _reportMobileCodexLinkFailure(
  BuildContext context,
  Object target, [
  Object? error,
  StackTrace? stackTrace,
]) {
  const message = 'Could not open link.';
  if (error == null) {
    _MobileCodexChatScreenState._logger.warning('$message Target: $target');
  } else {
    _MobileCodexChatScreenState._logger.warning(
      '$message Target: $target',
      error,
      stackTrace,
    );
  }
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(const SnackBar(content: Text(message)));
}

bool _isAbsoluteMobileCodexPath(String value) =>
    value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value);

@visibleForTesting
Rect mobileCodexSharePositionOrigin(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    final bounds = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    if (!bounds.isEmpty) return bounds;
  }
  return Offset.zero & MediaQuery.sizeOf(context);
}

@visibleForTesting
String? mobileCodexWorkspaceRelativePath({
  required String path,
  required String? cwd,
}) {
  final normalizedPath = path.replaceAll('\\', '/');
  if (!_isAbsoluteMobileCodexPath(normalizedPath)) return normalizedPath;
  final rawCwd = cwd?.trim().replaceAll('\\', '/');
  final normalizedCwd = switch (rawCwd) {
    '/' => '/',
    final value? when RegExp(r'^[A-Za-z]:/+$').hasMatch(value) =>
      '${value.substring(0, 2)}/',
    final value? => value.replaceAll(RegExp(r'/+$'), ''),
    null => null,
  };
  if (normalizedCwd == null || normalizedCwd.isEmpty) return null;
  final windowsPath = RegExp(r'^[A-Za-z]:/').hasMatch(normalizedPath);
  final comparablePath = windowsPath
      ? normalizedPath.toLowerCase()
      : normalizedPath;
  final comparableCwd = windowsPath
      ? normalizedCwd.toLowerCase()
      : normalizedCwd;
  final prefix = comparableCwd.endsWith('/')
      ? comparableCwd
      : '$comparableCwd/';
  if (!comparablePath.startsWith(prefix)) return null;
  return normalizedPath.substring(prefix.length);
}

@visibleForTesting
MobileCodexWorkspaceLinkTarget parseMobileCodexWorkspaceLink(String raw) {
  final rawUri = Uri.tryParse(raw.trim());
  var normalized = raw.replaceAll('\\', '/');
  if (rawUri?.scheme.toLowerCase() == 'file') {
    try {
      normalized = Uri.decodeComponent(rawUri!.path).replaceAll('\\', '/');
      if (RegExp(r'^/[A-Za-z]:/').hasMatch(normalized)) {
        normalized = normalized.substring(1);
      } else if (rawUri.host.isNotEmpty) {
        normalized = '//${rawUri.host}$normalized';
      }
    } on FormatException {
      normalized = rawUri!.path.replaceAll('\\', '/');
    }
    if (rawUri.fragment.isNotEmpty) normalized += '#${rawUri.fragment}';
  }
  final fragmentStart = normalized.lastIndexOf('#');
  final encodedPath = fragmentStart < 0
      ? normalized
      : normalized.substring(0, fragmentStart);
  final fragment = fragmentStart < 0
      ? ''
      : normalized.substring(fragmentStart + 1);
  String value;
  try {
    value = Uri.decodeComponent(encodedPath);
  } on FormatException {
    value = encodedPath;
  }
  if (value.startsWith('./')) value = value.substring(2);
  final suffix = RegExp(r':(\d+)(?::\d+)?$').firstMatch(value);
  var line = suffix == null ? null : int.tryParse(suffix.group(1)!);
  if (suffix != null) value = value.substring(0, suffix.start);
  final fragmentLine = RegExp(
    r'^L(\d+)(?:-L\d+)?$',
    caseSensitive: false,
  ).firstMatch(fragment);
  line ??= fragmentLine == null ? null : int.tryParse(fragmentLine.group(1)!);
  return MobileCodexWorkspaceLinkTarget(path: value, line: line);
}
