import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:flutter/material.dart';

class const QuotaStatusPill({super.key, required final String status})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (status) {
      'ok' => ('Live', AleraBadgeTone.success),
      'stale' => ('Stale', AleraBadgeTone.attention),
      _ => ('Unavailable', AleraBadgeTone.error),
    };
    return AleraBadge(label: label, tone: tone);
  }
}
