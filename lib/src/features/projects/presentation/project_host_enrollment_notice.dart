import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/features/projects/domain/project_host_enrollment.dart';
import 'package:alera/src/features/projects/presentation/project_host_add_form.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:flutter/material.dart';

/// What New Workspace shows under the host picker when the project has no
/// checkout on the selected host: the way to add it, or why it cannot be.
class const ProjectHostEnrollmentNotice({
  super.key,
  required final ProjectHostEnrollment enrollment,
  required final String projectName,
  required final String hostLabel,
  required final ProjectHostEnrollmentController controller,
  required final VoidCallback onAdd,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (enrollment) {
      .enrolled => const SizedBox.shrink(),
      .addable => AleraInlineNotice(
        message:
            '$projectName is not on $hostLabel yet. Add it to list branches and create workspaces there.',
        child: ProjectHostAddForm(
          controller: controller,
          enabled: enabled,
          onAdd: onAdd,
        ),
      ),
      .folderProject => _HelperText(
        '$projectName is a folder project, which lives on one host. Only Git projects can be added to more hosts.',
      ),
      .thisDevice => _HelperText(
        '$projectName is not on this device. Select one of its hosts.',
      ),
    };
  }
}

class const _HelperText(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}
