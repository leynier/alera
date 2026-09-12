import 'package:alera_mobile/src/design_system/alera_preview.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_refresh_progress.dart';
import 'package:flutter/widgets.dart';

@AleraPreview(name: 'Refresh Progress', group: 'Feedback')
Widget aleraRefreshProgressPreview() =>
    const AleraRefreshProgress(refreshing: true);
