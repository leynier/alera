import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/shared/git_hosting/application/hosting_provider_resolver.dart';
import 'package:alera/src/shared/git_hosting/application/repository_web_url.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_remote.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';

/// Outcome of attempting to open a repository's web page in the system browser.
enum OpenRepositoryOutcome {
  /// The browser was launched for the resolved repository URL.
  opened,

  /// The repository has no remote with a URL (or is not a git repository).
  noRemote,

  /// A remote URL exists but no supported hosting provider could be resolved.
  undetectable,

  /// The browser could not be launched.
  openFailed,
}

/// Resolves a repository's hosting provider from its remotes and opens its web
/// home page in the system browser. Mirrors the hosting detection used by the
/// pull-request feature but produces the repo home URL instead of a PR URL.
/// Honors an optional project-level [override] (e.g. for GitHub Enterprise
/// hosts that are not auto-detectable).
///
/// Opening falls back to the native `xdg-open` / `open` / `explorer.exe`
/// command when [ExternalUriLauncher] (url_launcher) cannot handle the URL,
/// which keeps the feature working on Linux setups where url_launcher is
/// misconfigured. Mirrors the fallback chain already used by
/// [WorkspaceFolderOpener] for folders.
class RepositoryBrowserOpener {
  RepositoryBrowserOpener({
    required this._gitBackend,
    required this._launcher,
    required this._processRunner,
    WorkspaceFolderPlatform? platform,
  }) : _platform = platform ?? currentWorkspaceFolderPlatform();

  final GitBackend _gitBackend;
  final ExternalUriLauncher _launcher;
  final ProcessRunner _processRunner;
  final WorkspaceFolderPlatform _platform;

  /// Opens [repoPath]'s repository home page. Never throws: callers branch on
  /// the returned [OpenRepositoryOutcome] to surface a toast on failure.
  Future<OpenRepositoryOutcome> open({
    required String repoPath,
    GitHostingProvider? override,
  }) async {
    final List<GitRemote> remotes;
    try {
      remotes = await _gitBackend.listRemotes(repoPath);
    } on GitException {
      return OpenRepositoryOutcome.noRemote;
    }

    final resolution = resolveHostingProvider(
      remotes: remotes,
      override: override,
    );

    final GitRemoteIdentity identity;
    if (resolution is HostingProviderResolved) {
      identity = resolution.identity;
    } else if (resolution is HostingProviderNoRemote) {
      return OpenRepositoryOutcome.noRemote;
    } else {
      return OpenRepositoryOutcome.undetectable;
    }

    final url = repositoryWebUrl(identity);
    if (url == null) {
      return OpenRepositoryOutcome.undetectable;
    }
    try {
      await _launcher.open(Uri.parse(url));
      return OpenRepositoryOutcome.opened;
    } catch (_) {
      // url_launcher can be missing or misconfigured (notably some Linux
      // setups); retry through the native open command before giving up.
      if (await _openNative(url)) {
        return OpenRepositoryOutcome.opened;
      }
      return OpenRepositoryOutcome.openFailed;
    }
  }

  /// Tries the platform's native "open" commands in order, returning true once
  /// one exits successfully. Mirrors [WorkspaceFolderOpener]'s command table.
  Future<bool> _openNative(String url) async {
    for (final command in _nativeOpenCommands(_platform, url)) {
      try {
        final result = await _processRunner.run(command.$1, command.$2);
        if (result.exitCode == 0) {
          return true;
        }
      } catch (_) {
        // Try the next fallback command.
        continue;
      }
    }
    return false;
  }
}

/// Per-platform native open commands for a URL. First success wins.
List<(String, List<String>)> _nativeOpenCommands(
  WorkspaceFolderPlatform platform,
  String url,
) {
  switch (platform) {
    case WorkspaceFolderPlatform.macos:
      return <(String, List<String>)>[
        ('open', <String>[url]),
      ];
    case WorkspaceFolderPlatform.windows:
      return <(String, List<String>)>[
        ('explorer.exe', <String>[url]),
      ];
    case WorkspaceFolderPlatform.linux:
    case WorkspaceFolderPlatform.other:
      return <(String, List<String>)>[
        ('xdg-open', <String>[url]),
        ('gio', <String>['open', url]),
      ];
  }
}
