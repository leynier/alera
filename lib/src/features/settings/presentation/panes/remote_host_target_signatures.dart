import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

String remoteHostEditorSignature(SshTarget target) {
  return Object.hashAll(<Object?>[
    target.id,
    target.alias,
    target.host,
    target.port,
    target.username,
    target.platform,
    target.arch,
    target.authKind,
    target.installDir,
  ]).toString();
}

String remoteHostStatusSignature(SshTarget target) {
  return Object.hashAll(<Object?>[
    target.id,
    target.runtimeVersion,
    target.runtimePlatform,
    target.runtimeArch,
    target.bootstrapStatus,
    target.lastBootstrapAt,
    target.lastCheckedAt,
    target.lastError,
    target.updatedAt,
  ]).toString();
}
