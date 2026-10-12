import 'package:alera/src/app/theme/alera_tokens.dart';

enum WorkspaceDetailsDensity { full, compact, essential }

WorkspaceDetailsDensity workspaceDetailsDensity(double availableHeight) =>
    availableHeight >= AleraTokens.space48 * 8
    ? .full
    : availableHeight >= AleraTokens.space48 * 6
    ? .compact
    : .essential;
