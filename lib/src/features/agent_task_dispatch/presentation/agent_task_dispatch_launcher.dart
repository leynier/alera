import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_providers.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/agent_task_dispatch/presentation/agent_task_dispatch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Picker result before injection. Watch binds this without sending until
/// checks fail; Fix Failed Checks injects immediately.
class const AgentTaskDispatchChoice({
  required final AgentTaskDispatchRequest request,
  required final AgentTaskDispatchCatalog catalog,
  required final AgentTaskDispatchSelection selection,
  required final AgentTaskDispatchBinding binding,
});

/// Shared picker: running workspace agent or a profile for a new tab.
///
/// Callers own the prompt. File and diff comments reuse this picker. It does
/// not inject; [showAgentTaskDispatchFlow] and [completeAgentTaskDispatch] are
/// the inject step.
Future<AgentTaskDispatchChoice?> chooseAgentTaskDispatchTarget(
  BuildContext context,
  WidgetRef ref, {
  required AgentTaskDispatchRequest request,
}) async {
  final prompt = request.prompt.trim();
  if (prompt.isEmpty) {
    AleraToast.show(context, message: 'The prompt is empty.', tone: .error);
    return null;
  }
  final normalized = AgentTaskDispatchRequest(
    workspaceId: request.workspaceId,
    prompt: prompt,
    title: request.title,
    message: request.message,
  );
  final catalog = readAgentTaskDispatchCatalog(ref, normalized.workspaceId);
  if (catalog.isEmpty) {
    AleraToast.show(
      context,
      message: 'Add an agent profile in Settings before sending work.',
      tone: .error,
    );
    return null;
  }
  final selection = await showAgentTaskDispatchPicker(
    context,
    request: normalized,
    catalog: catalog,
  );
  if (selection == null || !context.mounted) {
    return null;
  }
  final service = readAgentTaskDispatchService(
    ref,
    catalog: catalog,
    workspaceId: normalized.workspaceId,
  );
  return AgentTaskDispatchChoice(
    request: normalized,
    catalog: catalog,
    selection: selection,
    binding: service.bindingFor(selection),
  );
}

/// Opens the shared picker and injects [request]'s prompt into the chosen
/// running agent or a newly opened profile tab.
Future<AgentTaskDispatchResult?> showAgentTaskDispatchFlow(
  BuildContext context,
  WidgetRef ref, {
  required AgentTaskDispatchRequest request,
}) async {
  final choice = await chooseAgentTaskDispatchTarget(
    context,
    ref,
    request: request,
  );
  if (choice == null || !context.mounted) {
    return null;
  }
  return completeAgentTaskDispatch(
    ref: ref,
    request: choice.request,
    selection: choice.selection,
    catalog: choice.catalog,
  );
}

/// Shows the picker and returns the chosen target without injecting.
Future<AgentTaskDispatchSelection?> showAgentTaskDispatchPicker(
  BuildContext context, {
  required AgentTaskDispatchRequest request,
  required AgentTaskDispatchCatalog catalog,
}) {
  return showDialog<AgentTaskDispatchSelection>(
    context: context,
    builder: (_) => AgentTaskDispatchDialog(request: request, catalog: catalog),
  );
}

Future<AgentTaskDispatchResult?> completeAgentTaskDispatch({
  WidgetRef? ref,
  required AgentTaskDispatchRequest request,
  AgentTaskDispatchSelection? selection,
  AgentTaskDispatchBinding? binding,
  AgentTaskDispatchCatalog? catalog,
  AgentTaskDispatchService? service,
}) async {
  final resolved =
      service ??
      readAgentTaskDispatchService(
        ref!,
        catalog: catalog,
        workspaceId: request.workspaceId,
      );
  try {
    final result = selection != null
        ? await resolved.dispatch(request, selection)
        : await resolved.dispatchBinding(
            request,
            binding ?? const AgentTaskDispatchBinding(),
          );
    AleraToast.publish(
      message: result.openedNewTab
          ? 'Opened ${result.label}'
          : 'Sent to ${result.label}',
    );
    return result;
  } on AgentTaskDispatchException catch (error) {
    AleraToast.publish(message: error.message, tone: .error);
    return null;
  } on Object catch (error) {
    AleraToast.publish(message: error.toString(), tone: .error);
    return null;
  }
}
