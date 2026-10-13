import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_host_label_provider.g.dart';

/// The name the UI shows for [hostId]: the host's alias, "This Device" for
/// the local host, or the raw id once the host is no longer registered.
@riverpod
String remoteHostLabel(Ref ref, String? hostId) {
  final targets = ref.watch(sshTargetsProvider).value ?? const <SshTarget>[];
  return workspaceHostLabel(targets, hostId);
}
