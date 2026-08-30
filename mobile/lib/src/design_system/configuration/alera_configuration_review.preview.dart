import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/configuration/alera_configuration_review.dart';
import 'package:alera_configuration/alera_configuration.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Configuration Review', group: 'Configuration')
Widget configurationReviewPreview() => AleraConfigurationReview(
  target: 'This Device',
  state: const ConfigurationScreenState(),
  onRefresh: () {},
  onHistory: () {},
  onRestore: (_) {},
  onChoice: (_, _) {},
  onRename: (_, _) {},
  onChooseAll: (_) {},
  onApply: (_) {},
  onRetry: () {},
);
