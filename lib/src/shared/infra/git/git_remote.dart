/// A single configured git remote, mirroring one record of `git remote -v`.
/// [url] is the remote's fetch URL, or null when the remote has no URL set.
/// Used to detect the git hosting provider from the remote identity.
class GitRemote {
  const GitRemote({required this.name, this.url});

  final String name;
  final String? url;
}
