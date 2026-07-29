import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_providers.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mounts the recurring update check and announces what it finds.
///
/// The recurring check runs with nobody looking at Settings, so without this it
/// would change state no surface ever reports. Each version is announced once:
/// a toast every fifteen minutes for a release the user already declined would
/// be noise, and the Application settings pane keeps showing the status.
class UpdateAvailabilityWatch extends ConsumerStatefulWidget {
  const UpdateAvailabilityWatch({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateAvailabilityWatch> createState() =>
      _UpdateAvailabilityWatchState();
}

class _UpdateAvailabilityWatchState
    extends ConsumerState<UpdateAvailabilityWatch> {
  String? _announcedVersion;

  @override
  Widget build(BuildContext context) {
    ref.watch(aleraUpdateCheckSchedulerProvider);
    ref.listen<AleraUpdateState>(aleraUpdateControllerProvider, (
      previous,
      next,
    ) {
      _announce(next);
    });
    return widget.child;
  }

  void _announce(AleraUpdateState state) {
    if (!_isAvailable(state.status)) {
      return;
    }
    final version = state.latest?.version.trim();
    if (version == null || version.isEmpty || version == _announcedVersion) {
      return;
    }
    _announcedVersion = version;
    final message = state.message?.trim();
    if (message == null || message.isEmpty) {
      return;
    }
    AleraToast.show(context, message: message, tone: AleraToastTone.info);
  }
}

bool _isAvailable(AleraUpdateStatus status) {
  return status == AleraUpdateStatus.available ||
      status == AleraUpdateStatus.manualDownloadRequired;
}
