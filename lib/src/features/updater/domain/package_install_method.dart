import 'package:path/path.dart' as p;

/// Which package manager, if any, owns this copy of Alera.
///
/// Alera must never install an update over an installation a package manager
/// owns: replacing the bundle behind the manager's back leaves its database
/// claiming a version that is no longer on disk, and the next `upgrade` either
/// reverts the app or fails outright.
enum PackageInstallMethod {
  homebrewCask,
  scoop,
  chocolatey,

  /// A deb or rpm install: `dpkg` or `rpm` owns `/opt/alera`.
  ///
  /// Which of the two it is comes from `/etc/os-release`, not from the path, so
  /// the distinction lives with the update rather than with the installation.
  linuxSystemPackage,

  /// A plain download, or anything Alera cannot attribute to a manager.
  unmanaged,
}

/// The package-managed installation Alera is running from.
///
/// [managerExecutable] and [relaunchExecutable] are absolute paths derived from
/// the running executable rather than looked up on `PATH`. A GUI app inherits a
/// minimal environment on macOS (`launchd` never reads `~/.zprofile`), so
/// `brew` is frequently not on `PATH` at all; deriving it from the Caskroom the
/// app is sitting in is exact where a `PATH` lookup is a guess.
class PackageManagerInstall {
  const PackageManagerInstall({
    required this.method,
    this.managerExecutable,
    this.relaunchExecutable,
  });

  static const PackageManagerInstall unmanaged = PackageManagerInstall(
    method: PackageInstallMethod.unmanaged,
  );

  final PackageInstallMethod method;
  final String? managerExecutable;
  final String? relaunchExecutable;

  bool get isPackageManaged => method != PackageInstallMethod.unmanaged;

  /// Whether Alera can run the upgrade itself.
  ///
  /// Chocolatey is excluded on purpose: it installs under `C:\ProgramData` and
  /// its upgrade needs elevation, so the UAC prompt would appear after Alera
  /// has already closed, with no window left to explain what is asking.
  bool get canRunUpgrade =>
      managerExecutable != null && relaunchExecutable != null;
}

/// Attributes [executablePath] to the package manager that installed it.
///
/// Pure on purpose: the caller passes `Platform.resolvedExecutable`, which
/// resolves symlinks, so a Homebrew cask reports its Caskroom path rather than
/// the `/Applications` symlink Homebrew leaves behind.
PackageManagerInstall packageManagerInstallFromExecutablePath({
  required String platform,
  required String executablePath,
}) {
  final context = p.Context(
    style: platform == 'windows' ? p.Style.windows : p.Style.posix,
  );
  final segments = context
      .split(context.normalize(executablePath))
      .where((segment) => segment.isNotEmpty)
      .toList();

  return switch (platform) {
    'macos' => _macosInstall(context, segments),
    'windows' => _windowsInstall(context, segments),
    'linux' => _linuxInstall(segments),
    _ => PackageManagerInstall.unmanaged,
  };
}

/// The prefix `tool/release/package_linux.sh` installs the deb and rpm payload
/// under. `/usr/bin/alera` is a symlink into it, and `Platform.resolvedExecutable`
/// resolves symlinks, so the running executable always reports this path.
const List<String> _linuxPackagePrefix = <String>['opt', 'alera'];

PackageManagerInstall _linuxInstall(List<String> segments) {
  // Anchored at the filesystem root: a tarball extracted into
  // `~/projects/opt/alera` is not a packaged installation, and treating it as
  // one would send the user to an `apt` upgrade that cannot see it.
  final root = segments.isNotEmpty && segments.first == '/' ? 1 : 0;
  final matches =
      segments.length > root + _linuxPackagePrefix.length &&
      segments[root] == _linuxPackagePrefix[0] &&
      segments[root + 1] == _linuxPackagePrefix[1];
  if (!matches) {
    return PackageManagerInstall.unmanaged;
  }
  // Deliberately without a manager or relaunch executable: the deb and rpm
  // upgrades need `sudo`, so they run in Alera's command terminal where a
  // password prompt has a PTY to appear on, not in the detached shell that
  // Homebrew and Scoop use after the app has already closed.
  return const PackageManagerInstall(
    method: PackageInstallMethod.linuxSystemPackage,
  );
}

PackageManagerInstall _macosInstall(p.Context context, List<String> segments) {
  // <prefix>/Caskroom/alera/<version>/Alera.app/Contents/MacOS/alera
  final index = _indexOfSequence(segments, const <String>['Caskroom', 'alera']);
  if (index <= 0) {
    return PackageManagerInstall.unmanaged;
  }
  final prefix = context.joinAll(segments.sublist(0, index));
  return PackageManagerInstall(
    method: PackageInstallMethod.homebrewCask,
    managerExecutable: context.join(prefix, 'bin', 'brew'),
    // The Caskroom path carries the version, so it stops existing the moment
    // the upgrade lands. `open` resolves the bundle identifier through
    // LaunchServices instead, which survives the swap.
    relaunchExecutable: '/usr/bin/open',
  );
}

PackageManagerInstall _windowsInstall(
  p.Context context,
  List<String> segments,
) {
  // <choco>\lib\alera\tools\Alera.exe
  final chocolatey = _indexOfSequence(segments, const <String>[
    'chocolatey',
    'lib',
    'alera',
  ]);
  if (chocolatey >= 0) {
    return const PackageManagerInstall(method: PackageInstallMethod.chocolatey);
  }

  // <scoop>\apps\alera\current\Alera.exe. Matching on `apps\alera` rather than
  // on a directory literally named `scoop` is deliberate: the root moves with
  // the SCOOP environment variable, and users routinely relocate it.
  final scoop = _indexOfSequence(segments, const <String>['apps', 'alera']);
  if (scoop <= 0) {
    return PackageManagerInstall.unmanaged;
  }
  final root = context.joinAll(segments.sublist(0, scoop));
  return PackageManagerInstall(
    method: PackageInstallMethod.scoop,
    managerExecutable: context.join(root, 'shims', 'scoop.cmd'),
    // `current` is a junction Scoop repoints on every upgrade, so this path
    // keeps naming the app across versions.
    relaunchExecutable: context.join(
      root,
      'apps',
      'alera',
      'current',
      'Alera.exe',
    ),
  );
}

/// Index of the first segment of [sequence] within [segments], or -1.
///
/// Case-insensitive, because Windows paths are and a macOS volume can be.
int _indexOfSequence(List<String> segments, List<String> sequence) {
  for (var index = 0; index + sequence.length <= segments.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < sequence.length; offset += 1) {
      if (segments[index + offset].toLowerCase() !=
          sequence[offset].toLowerCase()) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return index;
    }
  }
  return -1;
}

/// The user-facing label for the manager that owns the installation.
String? packageManagerLabel(PackageInstallMethod method) {
  return switch (method) {
    PackageInstallMethod.homebrewCask => 'Homebrew',
    PackageInstallMethod.scoop => 'Scoop',
    PackageInstallMethod.chocolatey => 'Chocolatey',
    // Null on purpose: the path says the install is packaged but not by which
    // manager, and naming the wrong one is worse than naming none. The Linux
    // copy comes from the update's installer kind instead.
    PackageInstallMethod.linuxSystemPackage => null,
    PackageInstallMethod.unmanaged => null,
  };
}
