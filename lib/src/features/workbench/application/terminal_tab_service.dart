// ignore_for_file: prefer_initializing_formals

import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:uuid/uuid.dart';

class TerminalTabService {
  TerminalTabService({
    required WorkbenchRepository repository,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _repository = repository,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? _defaultNow;

  final WorkbenchRepository _repository;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Future<List<TerminalTabRecord>> listTabs(String workspaceId) {
    return _repository.listTerminalTabs(workspaceId);
  }

  Future<TerminalTabRecord> ensureInitialTab(String workspaceId) async {
    final tabs = await _repository.listTerminalTabs(workspaceId);
    if (tabs.isNotEmpty) {
      return tabs.first;
    }
    return createTab(workspaceId);
  }

  Future<TerminalTabRecord> createTab(String workspaceId) async {
    final existing = await _repository.listTerminalTabs(workspaceId);
    final tab = TerminalTabRecord(
      id: _uuid.v4(),
      workspaceId: workspaceId,
      title: 'Terminal ${_nextOrdinal(existing)}',
      createdAt: _now(),
      updatedAt: _now(),
    );
    await _repository.upsertTerminalTab(tab);
    return tab;
  }

  Future<void> closeTab(String tabId) {
    return _repository.removeTerminalTab(tabId);
  }

  int _nextOrdinal(List<TerminalTabRecord> tabs) {
    final used = <int>{};
    for (final tab in tabs) {
      final match = RegExp(r'^Terminal (\d+)$').firstMatch(tab.title);
      if (match == null) {
        continue;
      }
      used.add(int.parse(match.group(1)!));
    }
    var ordinal = 1;
    while (used.contains(ordinal)) {
      ordinal += 1;
    }
    return ordinal;
  }
}
