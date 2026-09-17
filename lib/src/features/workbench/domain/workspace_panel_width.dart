import 'dart:math' as math;

import 'package:alera/src/app/theme/alera_tokens.dart';

/// Requested width remains persisted; only the rendered width is constrained.
double workspacePanelMaximumWidth(double availableWidth) => math.max(
  0,
  availableWidth - AleraTokens.workbenchPrimaryMinWidth - AleraTokens.space6,
);

double workspacePanelWidth(double requested, double maximum) =>
    (requested.isFinite ? requested : AleraTokens.sidebarDefaultWidth).clamp(
      math.min(AleraTokens.sidebarMinWidth, maximum),
      maximum,
    );
