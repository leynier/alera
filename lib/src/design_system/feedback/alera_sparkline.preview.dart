import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/feedback/alera_sparkline.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Rising', group: 'Sparkline')
Widget aleraSparklineRisingPreview() =>
    const AleraSparkline(samples: <int>[10, 14, 12, 22, 30, 28, 44, 60]);

@AleraPreview(name: 'Flat', group: 'Sparkline')
Widget aleraSparklineFlatPreview() =>
    const AleraSparkline(samples: <int>[30, 30, 30, 30, 30]);

@AleraPreview(name: 'Single Sample', group: 'Sparkline')
Widget aleraSparklineSingleSamplePreview() =>
    const AleraSparkline(samples: <int>[30]);

@AleraPreview(name: 'Empty', group: 'Sparkline')
Widget aleraSparklineEmptyPreview() => const AleraSparkline(samples: <int>[]);
