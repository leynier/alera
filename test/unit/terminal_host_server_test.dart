import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_history_store.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

part 'terminal_host_server_lifecycle_test_cases.dart';
part 'terminal_host_server_configuration_test_cases.dart';
part 'terminal_host_server_test_harness.dart';

void main() {
  _registerTerminalHostServerLifecycleTests();
  _registerTerminalHostServerConfigurationTests();
}
