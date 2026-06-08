import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Info', group: 'Status indicator')
Widget aleraStatusIndicatorInfoPreview() => const AleraStatusIndicator(
  icon: AleraIcons.updateAvailable,
  color: AleraTokens.info,
);

@AleraPreview(name: 'Success', group: 'Status indicator')
Widget aleraStatusIndicatorSuccessPreview() => const AleraStatusIndicator(
  icon: AleraIcons.check,
  color: AleraTokens.success,
);

@AleraPreview(name: 'Error', group: 'Status indicator')
Widget aleraStatusIndicatorErrorPreview() => const AleraStatusIndicator(
  icon: AleraIcons.error,
  color: AleraTokens.error,
);
