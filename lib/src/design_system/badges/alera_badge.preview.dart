import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Neutral', group: 'Badge')
Widget aleraBadgePreview() => const AleraBadge(label: 'Primary');

@AleraPreview(name: 'Success', group: 'Badge')
Widget aleraBadgeSuccessPreview() => const AleraBadge(
  label: 'Active',
  color: AleraTokens.accentSubtle,
  foregroundColor: AleraTokens.success,
);
