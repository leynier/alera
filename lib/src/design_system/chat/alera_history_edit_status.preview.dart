import 'package:flutter/material.dart';

import '../alera_preview.dart';
import 'alera_history_edit_status.dart';

@AleraPreview(name: 'Correction Recovery', group: 'Chat')
Widget historyEditStatusPreview() =>
    AleraHistoryEditStatus(phase: 'resendFailed', onRetry: () {});
