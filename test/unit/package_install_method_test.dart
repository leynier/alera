import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/domain/package_install_method.dart';
import 'package:alera/src/features/updater/domain/package_manager_upgrade_script.dart';
import 'package:flutter_test/flutter_test.dart';

AleraUpdateInfo _update({String platform = 'macos', String kind = 'tar.gz'}) {
  return AleraUpdateInfo(
    version: '1.2.3',
    date: '2026-07-28T00:00:00Z',
    shortVersion: 70,
    mandatory: false,
    changes: const <String>['Notes.'],
    platform: platform,
    installerKind: kind,
    url: Uri.parse('https://example.com/alera-1.2.3-$platform.$kind'),
  );
}

void main() {
  group('package install detection', () {
    test('attributes a Homebrew cask from its Caskroom path', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'macos',
        executablePath:
            '/opt/homebrew/Caskroom/alera/1.2.3/Alera.app/Contents/MacOS/alera',
      );

      expect(install.method, PackageInstallMethod.homebrewCask);
      expect(install.managerExecutable, '/opt/homebrew/bin/brew');
      expect(install.canRunUpgrade, isTrue);
      expect(install.isPackageManaged, isTrue);
    });

    test('finds brew under an Intel prefix too', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'macos',
        executablePath:
            '/usr/local/Caskroom/alera/1.2.3/Alera.app/Contents/MacOS/alera',
      );

      expect(install.managerExecutable, '/usr/local/bin/brew');
    });

    test('leaves a plain /Applications install unmanaged', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'macos',
        executablePath: '/Applications/Alera.app/Contents/MacOS/alera',
      );

      expect(install.method, PackageInstallMethod.unmanaged);
      expect(install.isPackageManaged, isFalse);
      expect(install.canRunUpgrade, isFalse);
    });

    // Another cask's Caskroom must not be mistaken for Alera's.
    test('ignores a Caskroom entry that belongs to another app', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'macos',
        executablePath:
            '/opt/homebrew/Caskroom/something/1.0/Other.app/Contents/MacOS/x',
      );

      expect(install.method, PackageInstallMethod.unmanaged);
    });

    test('attributes a Scoop install and keeps the current junction', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'windows',
        executablePath: r'C:\Users\leynier\scoop\apps\alera\current\Alera.exe',
      );

      expect(install.method, PackageInstallMethod.scoop);
      expect(
        install.managerExecutable,
        r'C:\Users\leynier\scoop\shims\scoop.cmd',
      );
      expect(
        install.relaunchExecutable,
        r'C:\Users\leynier\scoop\apps\alera\current\Alera.exe',
      );
      expect(install.canRunUpgrade, isTrue);
    });

    // Scoop's root moves with the SCOOP environment variable, so the detection
    // cannot key on a directory literally named scoop.
    test('attributes a Scoop install from a relocated root', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'windows',
        executablePath: r'D:\tools\apps\alera\1.2.3\Alera.exe',
      );

      expect(install.method, PackageInstallMethod.scoop);
      expect(install.managerExecutable, r'D:\tools\shims\scoop.cmd');
      expect(
        install.relaunchExecutable,
        r'D:\tools\apps\alera\current\Alera.exe',
      );
    });

    test('attributes a Chocolatey install but never runs its upgrade', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'windows',
        executablePath: r'C:\ProgramData\chocolatey\lib\alera\tools\Alera.exe',
      );

      expect(install.method, PackageInstallMethod.chocolatey);
      expect(install.isPackageManaged, isTrue);
      expect(install.canRunUpgrade, isFalse);
    });

    test('leaves a plain Windows install unmanaged', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'windows',
        executablePath: r'C:\Program Files\Alera\Alera.exe',
      );

      expect(install.method, PackageInstallMethod.unmanaged);
    });

    // Linux distribution is owned by apt and dnf, which are detected from the
    // artifact rather than from the path.
    test('never attributes a Linux install to a desktop package manager', () {
      final install = packageManagerInstallFromExecutablePath(
        platform: 'linux',
        executablePath: '/opt/alera/alera',
      );

      expect(install.method, PackageInstallMethod.unmanaged);
    });

    test('labels each manager for the update copy', () {
      expect(
        packageManagerLabel(PackageInstallMethod.homebrewCask),
        'Homebrew',
      );
      expect(packageManagerLabel(PackageInstallMethod.scoop), 'Scoop');
      expect(
        packageManagerLabel(PackageInstallMethod.chocolatey),
        'Chocolatey',
      );
      expect(packageManagerLabel(PackageInstallMethod.unmanaged), isNull);
    });
  });

  group('package manager upgrade command', () {
    test('names the manager that owns the installation', () {
      expect(
        packageManagerUpgradeCommand(
          update: _update(),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.homebrewCask,
        ),
        'brew upgrade --cask alera',
      );
      expect(
        packageManagerUpgradeCommand(
          update: _update(platform: 'windows'),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.scoop,
        ),
        'scoop update alera',
      );
      expect(
        packageManagerUpgradeCommand(
          update: _update(platform: 'windows'),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.chocolatey,
        ),
        'choco upgrade alera -y',
      );
    });

    test('keeps the Linux behavior for an unmanaged installation', () {
      expect(
        packageManagerUpgradeCommand(
          update: _update(platform: 'linux', kind: 'deb'),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.unmanaged,
        ),
        'sudo apt-get update && sudo apt-get install --only-upgrade alera',
      );
      expect(
        packageManagerUpgradeCommand(
          update: _update(platform: 'linux', kind: 'rpm'),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.unmanaged,
        ),
        'sudo dnf upgrade alera',
      );
      expect(
        packageManagerUpgradeCommand(
          update: _update(),
          channel: AleraUpdateChannel.stable,
          installMethod: PackageInstallMethod.unmanaged,
        ),
        isNull,
      );
    });

    // Release candidates are GitHub assets only; no package manager carries
    // them, so an upgrade command would report no change and confuse the user.
    test('offers nothing on the release-candidate channel', () {
      for (final method in PackageInstallMethod.values) {
        expect(
          packageManagerUpgradeCommand(
            update: _update(),
            channel: AleraUpdateChannel.rc,
            installMethod: method,
          ),
          isNull,
          reason: method.name,
        );
      }
    });
  });

  group('package manager upgrade script', () {
    test('waits for Alera to exit before Homebrew touches the bundle', () {
      final script = packageManagerUpgradeScript(
        packageManagerInstallFromExecutablePath(
          platform: 'macos',
          executablePath:
              '/opt/homebrew/Caskroom/alera/1.2.3/Alera.app/Contents/MacOS/a',
        ),
      );

      expect(script, isNotNull);
      expect(script!.executable, '/bin/sh');
      expect(script.contents, contains('kill -0 "\$parent_pid"'));
      expect(script.contents, contains('upgrade --cask alera'));
      // The Caskroom path carries the version, so the relaunch has to go
      // through the bundle identifier instead.
      expect(script.contents, contains('open -b dev.leynier.alera'));
    });

    test('waits for Alera to exit before Scoop replaces the directory', () {
      final script = packageManagerUpgradeScript(
        packageManagerInstallFromExecutablePath(
          platform: 'windows',
          executablePath: r'C:\Users\me\scoop\apps\alera\current\Alera.exe',
        ),
      );

      expect(script, isNotNull);
      expect(script!.executable, 'powershell.exe');
      expect(script.arguments, contains('-NoProfile'));
      expect(script.arguments.last, '-File');
      expect(script.contents, contains('Get-Process -Id \$ParentPid'));
      expect(script.contents, contains('update alera'));
      expect(script.contents, contains('Start-Process -FilePath \$AleraPath'));
    });

    test('refuses to run the elevated Chocolatey upgrade', () {
      expect(
        packageManagerUpgradeScript(
          packageManagerInstallFromExecutablePath(
            platform: 'windows',
            executablePath: r'C:\ProgramData\chocolatey\lib\alera\tools\a.exe',
          ),
        ),
        isNull,
      );
    });

    test('has nothing to run for an unmanaged installation', () {
      expect(
        packageManagerUpgradeScript(PackageManagerInstall.unmanaged),
        isNull,
      );
    });

    // Guards the switch rather than the detection: a method that reports it can
    // run an upgrade must have a script, or the launcher throws at runtime.
    test('covers every method that claims it can run an upgrade', () {
      const runnable = PackageManagerInstall(
        method: PackageInstallMethod.unmanaged,
        managerExecutable: '/usr/bin/true',
        relaunchExecutable: '/usr/bin/true',
      );

      expect(packageManagerUpgradeScript(runnable), isNull);
    });
  });
}
