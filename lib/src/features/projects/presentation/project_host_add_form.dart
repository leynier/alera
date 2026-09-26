import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/presentation/project_host_enrollment_controller.dart';
import 'package:flutter/material.dart';

/// The optional existing path, the "Add to Host" action, and the progress or
/// failure of the request [controller] is running. [onAdd] is null while no
/// host is chosen.
class const ProjectHostAddForm({
  super.key,
  required final ProjectHostEnrollmentController controller,
  required final VoidCallback? onAdd,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final adding = controller.adding;
        final error = controller.error;
        final canAdd = enabled && !adding && onAdd != null;
        return Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraTextField(
              controller: controller.pathController,
              enabled: enabled && !adding,
              labelText: 'Existing Path',
              hintText: "Leave empty to clone into the host's projects folder",
              onChanged: (_) => controller.clearError(),
              onSubmitted: canAdd ? (_) => onAdd!() : null,
            ),
            const SizedBox(height: AleraTokens.space12),
            if (adding)
              Row(
                children: <Widget>[
                  const SizedBox.square(
                    dimension: AleraTokens.iconLg,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      'Adding the project to the host. A clone can take a few minutes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ],
              )
            else
              Align(
                alignment: .centerLeft,
                child: FilledButton.icon(
                  onPressed: canAdd ? onAdd : null,
                  icon: const Icon(AleraIcons.add, size: AleraTokens.iconLg),
                  label: const Text('Add to Host'),
                ),
              ),
            if (error != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.error,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
