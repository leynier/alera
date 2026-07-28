import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_remote_identity.dart';

/// Pure parsing of git remote URLs into a [GitRemoteIdentity]. No I/O - the
/// caller reads the remote URL through `GitBackend.listRemotes` and passes the
/// string here. Detection is a single host/path parse per remote, avoiding
/// Orca's per-provider subprocess probing.
///
/// Two entry points:
/// - [parseGitRemoteIdentity] auto-detects the provider from the host.
/// - [parseRemoteAsProvider] forces interpretation as a specific provider by
///   path shape, so a user override works for self-hosted hosts (e.g. GitHub
///   Enterprise) whose host is not the canonical one.

/// Auto-detects the provider and coordinates from [url], or null when the
/// remote is not a recognized provider.
GitRemoteIdentity? parseGitRemoteIdentity(String url) {
  final parsed = _parseRemoteUrl(url);
  if (parsed == null) {
    return null;
  }
  final host = parsed.hostname;
  if (host == 'github.com') {
    return _asGitHub(parsed.host, parsed.segments);
  }
  if (host == 'gitlab.com') {
    return _asGitLab(parsed.host, parsed.segments);
  }
  if (host == 'dev.azure.com' || host == 'ssh.dev.azure.com') {
    return _asAzureDevOps(parsed.host, parsed.segments);
  }
  if (host == 'vs-ssh.visualstudio.com') {
    return _asAzureVisualStudioSsh(parsed.host, parsed.segments);
  }
  if (host.endsWith('.visualstudio.com')) {
    return _asAzureVisualStudioHttps(parsed.host, parsed.segments);
  }
  return null;
}

/// Interprets [url] as [provider] regardless of host, used when the project
/// overrides the provider. Returns null when the path shape cannot yield the
/// coordinates that provider needs.
GitRemoteIdentity? parseRemoteAsProvider(
  String url,
  GitHostingProvider provider,
) {
  final parsed = _parseRemoteUrl(url);
  if (parsed == null) {
    return null;
  }
  return switch (provider) {
    GitHostingProvider.github => _asGitHub(parsed.host, parsed.segments),
    GitHostingProvider.azureDevops => _asAnyAzure(parsed.host, parsed.segments),
    GitHostingProvider.gitlab => _asGitLab(parsed.host, parsed.segments),
  };
}

class _ParsedRemoteUrl {
  const _ParsedRemoteUrl({
    required this.host,
    required this.hostname,
    required this.segments,
  });

  final String host;
  final String hostname;
  final List<String> segments;
}

/// Splits a git remote URL into a lowercased host and its `.git`-stripped,
/// non-empty path segments. Handles `scheme://[user@]host[:port]/path`,
/// scp-like `user@host:path`, and bare `host:path`.
_ParsedRemoteUrl? _parseRemoteUrl(String raw) {
  final url = raw.trim();
  if (url.isEmpty) {
    return null;
  }

  String host;
  String hostname;
  String path;
  if (url.contains('://')) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    hostname = uri.host;
    final preservesApiPort = uri.scheme == 'http' || uri.scheme == 'https';
    host = preservesApiPort && uri.hasPort
        ? '${uri.host}:${uri.port}'
        : uri.host;
    path = uri.path;
  } else {
    // scp-like: [user@]host:path - the first ':' separates host from path.
    final colon = url.indexOf(':');
    if (colon <= 0) {
      return null;
    }
    var authority = url.substring(0, colon);
    path = url.substring(colon + 1);
    final at = authority.lastIndexOf('@');
    if (at >= 0) {
      authority = authority.substring(at + 1);
    }
    host = authority;
    hostname = authority;
  }

  final segments = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty) {
      continue;
    }
    segments.add(segment);
  }
  if (segments.isEmpty) {
    return null;
  }
  final last = segments.length - 1;
  if (segments[last].endsWith('.git')) {
    segments[last] = segments[last].substring(0, segments[last].length - 4);
  }
  if (segments[last].isEmpty) {
    return null;
  }
  return _ParsedRemoteUrl(
    host: host.toLowerCase(),
    hostname: hostname.toLowerCase(),
    segments: segments,
  );
}

GitRemoteIdentity? _asGitHub(String host, List<String> segments) {
  if (segments.length < 2) {
    return null;
  }
  return GitRemoteIdentity(
    provider: GitHostingProvider.github,
    host: host,
    owner: segments[0],
    repo: segments[1],
  );
}

GitRemoteIdentity? _asGitLab(String host, List<String> segments) {
  if (segments.length < 2) {
    return null;
  }
  return GitRemoteIdentity(
    provider: GitHostingProvider.gitlab,
    host: host,
    owner: segments.sublist(0, segments.length - 1).join('/'),
    repo: segments.last,
  );
}

/// Azure `dev.azure.com` (HTTPS: `org/project/_git/repo`) and
/// `ssh.dev.azure.com` (SSH: `v3/org/project/repo`).
GitRemoteIdentity? _asAzureDevOps(String host, List<String> segments) {
  if (host == 'ssh.dev.azure.com') {
    return _azureFromSshSegments(host, segments);
  }
  return _azureFromGitSegments(host, segments);
}

/// Forces Azure interpretation for any host, trying every known shape.
GitRemoteIdentity? _asAnyAzure(String host, List<String> segments) {
  return _azureFromGitSegments(host, segments) ??
      _azureFromSshSegments(host, segments) ??
      _asAzureVisualStudioHttps(host, segments);
}

/// HTTPS shape containing a `_git` marker: `[collection/]org/project/_git/repo`
/// on dev.azure.com, or `[collection/]project/_git/repo` on `org.visualstudio.com`.
GitRemoteIdentity? _azureFromGitSegments(String host, List<String> segments) {
  final gitIndex = segments.indexOf('_git');
  if (gitIndex < 1 || gitIndex + 1 >= segments.length) {
    return null;
  }
  final repo = segments[gitIndex + 1];
  final before = segments.sublist(0, gitIndex);
  // before = [..., org, project] (dev.azure.com) or [..., project] (VSTS host).
  if (host.endsWith('.visualstudio.com')) {
    final org = host.substring(0, host.length - '.visualstudio.com'.length);
    final project = before.last;
    return GitRemoteIdentity(
      provider: GitHostingProvider.azureDevops,
      host: host,
      owner: org,
      repo: repo,
      project: project,
    );
  }
  if (before.length < 2) {
    return null;
  }
  final org = before[before.length - 2];
  final project = before[before.length - 1];
  return GitRemoteIdentity(
    provider: GitHostingProvider.azureDevops,
    host: host,
    owner: org,
    repo: repo,
    project: project,
  );
}

/// SSH shape `v3/org/project/repo`.
GitRemoteIdentity? _azureFromSshSegments(String host, List<String> segments) {
  final base = segments.first == 'v3' ? segments.sublist(1) : segments;
  if (base.length < 3) {
    return null;
  }
  return GitRemoteIdentity(
    provider: GitHostingProvider.azureDevops,
    host: host,
    owner: base[0],
    repo: base[2],
    project: base[1],
  );
}

GitRemoteIdentity? _asAzureVisualStudioSsh(String host, List<String> segments) {
  return _azureFromSshSegments(host, segments);
}

GitRemoteIdentity? _asAzureVisualStudioHttps(
  String host,
  List<String> segments,
) {
  return _azureFromGitSegments(host, segments);
}
