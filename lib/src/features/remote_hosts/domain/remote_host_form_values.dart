import 'package:alera/src/features/remote_hosts/domain/ssh_address.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

String? emptyToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

/// The SSH port typed into the editor: 22 when the field is blank, null when
/// the text is not a valid port.
int? parseRemoteHostPort(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    return defaultSshPort;
  }
  final port = int.tryParse(value);
  return port == null || port < 1 || port > 65535 ? null : port;
}

String normalizedRemoteHostPlatform(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'darwin' || 'mac' || 'macos' => 'macos',
    'linux' => 'linux',
    'win32' || 'windows' || 'windows_nt' => 'windows',
    _ => '',
  };
}

String normalizedRemoteHostArch(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'x86_64' || 'amd64' || 'x64' => 'x64',
    'aarch64' || 'arm64' => 'arm64',
    _ => '',
  };
}

/// Identity of a host: what Add Host step 1 and Edit Connection collect.
class const RemoteHostConnectionValues({
  required final String alias,
  required final String address,
  final SshAuthKind authKind = SshAuthKind.agent,
  final String? identityFile,
}) {
  factory fromTarget(SshTarget target) => RemoteHostConnectionValues(
    alias: target.alias,
    address: sshAddressLabel(target),
    authKind: target.authKind,
    identityFile: target.identityFile,
  );

  /// The first problem with these values, as a sentence, or null when they
  /// can be saved. Aliases compare case-insensitively, like the runtime.
  String? validate({required Iterable<SshTarget> existing, String? editingId}) {
    final name = alias.trim();
    if (name.isEmpty) {
      return 'Enter a name for this host.';
    }
    final duplicate = existing.any(
      (target) =>
          target.id != editingId &&
          target.alias.trim().toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      return duplicateRemoteHostAliasMessage(name);
    }
    return sshAddressError(address);
  }

  /// A new target, or [existing] with its identity replaced. Server-owned
  /// fields are copied from [existing]; the runtime ignores them anyway.
  SshTarget toTarget({SshTarget? existing, required DateTime now}) {
    final parsed = parseSshAddress(address);
    final keyFile = authKind == SshAuthKind.key
        ? emptyToNull(identityFile ?? '')
        : null;
    return SshTarget(
      id: existing?.id ?? 'ssh-${now.microsecondsSinceEpoch}',
      alias: alias.trim(),
      host: parsed.host,
      port: parsed.port,
      username: parsed.username,
      authKind: authKind,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      platform: existing?.platform,
      arch: existing?.arch,
      lastStatus: existing?.lastStatus,
      installDir: existing?.installDir,
      projectsDir: existing?.projectsDir,
      runtimeVersion: existing?.runtimeVersion,
      runtimePlatform: existing?.runtimePlatform,
      runtimeArch: existing?.runtimeArch,
      bootstrapStatus: existing?.bootstrapStatus ?? .notInstalled,
      lastBootstrapAt: existing?.lastBootstrapAt,
      lastCheckedAt: existing?.lastCheckedAt,
      lastError: existing?.lastError,
      identityFile: keyFile,
    );
  }
}

/// The Advanced group: where the runtime goes and what it is built for. A
/// blank value means the runtime's default.
class const RemoteHostAdvancedValues({
  final String installDir = '',
  final String projectsDir = '',
  final String platform = '',
  final String arch = '',
}) {
  factory fromTarget(SshTarget target) => RemoteHostAdvancedValues(
    installDir: target.installDir ?? '',
    projectsDir: target.projectsDir ?? '',
    platform: normalizedRemoteHostPlatform(target.platform),
    arch: normalizedRemoteHostArch(target.arch),
  );

  SshTarget applyTo(SshTarget target, {required DateTime now}) {
    return SshTarget(
      id: target.id,
      alias: target.alias,
      host: target.host,
      port: target.port,
      username: target.username,
      authKind: target.authKind,
      createdAt: target.createdAt,
      updatedAt: now,
      platform: emptyToNull(platform),
      arch: emptyToNull(arch),
      lastStatus: target.lastStatus,
      installDir: emptyToNull(installDir),
      projectsDir: emptyToNull(projectsDir),
      runtimeVersion: target.runtimeVersion,
      runtimePlatform: target.runtimePlatform,
      runtimeArch: target.runtimeArch,
      bootstrapStatus: target.bootstrapStatus,
      lastBootstrapAt: target.lastBootstrapAt,
      lastCheckedAt: target.lastCheckedAt,
      lastError: target.lastError,
      identityFile: target.identityFile,
    );
  }
}

String duplicateRemoteHostAliasMessage(String alias) =>
    'A host named $alias already exists.';
