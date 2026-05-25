import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Active', group: 'Status dot')
Widget aleraStatusDotActivePreview() => const AleraStatusDot(active: true);

@AleraPreview(name: 'Inactive', group: 'Status dot')
Widget aleraStatusDotInactivePreview() => const AleraStatusDot(active: false);
