import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/codex_chat/application/codex_chat_controller.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/infra/codex_chat_host_client.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

part 'codex_chat_controller_test_support.dart';
part 'codex_chat_controller_catalogue_test_cases.dart';
part 'codex_chat_controller_history_test_cases.dart';
part 'codex_chat_controller_input_test_cases.dart';
part 'codex_chat_controller_queue_test_cases.dart';
part 'codex_chat_controller_request_test_cases.dart';
part 'codex_chat_controller_session_test_cases.dart';

void main() {
  registerCodexChatControllerSessionTests();
  registerCodexChatControllerHistoryTests();
  registerCodexChatControllerCatalogueTests();
  registerCodexChatControllerQueueTests();
  registerCodexChatControllerInputTests();
  registerCodexChatControllerRequestTests();
}
