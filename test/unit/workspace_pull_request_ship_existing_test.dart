import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/pull_requests/application/workspace_pull_request_controller.dart';
import 'package:alera/src/features/pull_requests/domain/create_review_result.dart';
import 'package:alera/src/features/pull_requests/domain/pull_request_ship_scope.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_forge_provider.dart';
import 'fake_git_backend.dart';
import 'workspace_pull_request_ship_support.dart';

part 'workspace_pull_request_ship_existing_success_test_cases.dart';
part 'workspace_pull_request_ship_existing_blocking_test_cases.dart';

void main() {
  _registerWorkspacePullRequestShipExistingSuccessTests();
  _registerWorkspacePullRequestShipExistingBlockingTests();
}
