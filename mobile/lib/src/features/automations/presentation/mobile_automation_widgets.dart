import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/automations/domain/mobile_automation.dart';
import 'package:alera_mobile/src/features/automations/infra/mobile_runtime_automation_repository.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter/material.dart';

class MobileAutomationCard extends StatelessWidget {
  const MobileAutomationCard({
    required this.clientFuture,
    required this.automation,
    required this.onChanged,
    required this.onOpen,
    super.key,
  });

  final Future<MobileRuntimeClient> clientFuture;
  final MobileAutomation automation;
  final VoidCallback onChanged;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: AleraTokens.contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      automation.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(label: Text(automation.state)),
                ],
              ),
              Text(automation.slug, style: AleraTokens.monoStyle),
              const SizedBox(height: AleraTokens.spaceSm),
              Text(
                automation.description.isEmpty
                    ? 'No description'
                    : automation.description,
              ),
              const SizedBox(height: AleraTokens.spaceMd),
              Wrap(
                spacing: AleraTokens.spaceSm,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => unawaited(_run(context)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Run Now'),
                  ),
                  if (automation.state == 'active')
                    OutlinedButton(
                      onPressed: () => unawaited(_pause(context)),
                      child: const Text('Pause'),
                    )
                  else if (automation.state == 'paused')
                    OutlinedButton(
                      onPressed: () => unawaited(_resume(context)),
                      child: const Text('Resume'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context) async {
    final choice = await showDialog<(bool, String, bool, bool)>(
      context: context,
      builder: (_) => const MobileRunChoiceDialog(),
    );
    if (choice == null) return;
    try {
      await MobileRuntimeAutomationRepository(await clientFuture).runNow(
        automation.id,
        precheck: choice.$1,
        overlap: choice.$2,
        draftTest: choice.$3,
        revision: choice.$4 ? automation.revision : null,
      );
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  Future<void> _pause(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => const MobilePauseChoiceDialog(),
    );
    if (choice == null) return;
    try {
      await MobileRuntimeAutomationRepository(await clientFuture)
          .pause(automation.id, activeRuns: choice);
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  Future<void> _resume(BuildContext context) async {
    try {
      await (await clientFuture).request('automation.resume', <String, Object?>{
        'id': automation.id,
      });
      onChanged();
    } on Object catch (error) {
      if (context.mounted) _show(context, error.toString(), error: true);
    }
  }

  static void _show(
    BuildContext context,
    String message, {
    bool error = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }
}

class MobilePolicyDialog extends StatefulWidget {
  const MobilePolicyDialog({
    required this.profile,
    required this.project,
    super.key,
  });

  final Map<String, Object?> profile;
  final Map<String, Object?> project;

  @override
  State<MobilePolicyDialog> createState() => _MobilePolicyDialogState();
}

class _MobilePolicyDialogState extends State<MobilePolicyDialog> {
  late bool _activate;
  late bool _execute;
  late bool _restrictive;
  late bool _local;

  @override
  void initState() {
    super.initState();
    _activate = widget.profile['mayActivateOrEditActive'] == true;
    _execute = widget.profile['mayExecute'] == true;
    _restrictive = widget.project['restrictive'] == true;
    _local = widget.project['localApproved'] == true;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Effective Automation Policy'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('May Activate Or Edit Active'),
            value: _activate,
            onChanged: (value) => setState(() => _activate = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('May Execute'),
            value: _execute,
            onChanged: (value) => setState(() => _execute = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Restrictive Local Approval'),
            value: _restrictive,
            onChanged: (value) => setState(() => _restrictive = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Local Approval Granted'),
            value: _local,
            onChanged: (value) => setState(() => _local = value),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, (
          activate: _activate,
          execute: _execute,
          restrictive: _restrictive,
          local: _local,
        )),
        child: const Text('Save Policy'),
      ),
    ],
  );
}

class MobileRunChoiceDialog extends StatefulWidget {
  const MobileRunChoiceDialog({super.key});

  @override
  State<MobileRunChoiceDialog> createState() => _MobileRunChoiceDialogState();
}

class _MobileRunChoiceDialogState extends State<MobileRunChoiceDialog> {
  bool precheck = true;
  bool draft = false;
  bool exactRevision = false;
  String overlap = 'skip';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Run Now'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SwitchListTile.adaptive(
          title: const Text('Run Precheck'),
          value: precheck,
          onChanged: (value) => setState(() => precheck = value),
        ),
        SwitchListTile.adaptive(
          title: const Text('Audited Draft Test'),
          value: draft,
          onChanged: (value) => setState(() {
            draft = value;
            if (value) exactRevision = false;
          }),
        ),
        SwitchListTile.adaptive(
          title: const Text('Approve Exact Revision'),
          value: exactRevision,
          onChanged: (value) => setState(() {
            exactRevision = value;
            if (value) draft = false;
          }),
        ),
        DropdownButtonFormField<String>(
          initialValue: overlap,
          decoration: const InputDecoration(labelText: 'Overlap'),
          items: const <DropdownMenuItem<String>>[
            DropdownMenuItem(value: 'skip', child: Text('Skip')),
            DropdownMenuItem(value: 'queue', child: Text('Queue')),
            DropdownMenuItem(
              value: 'runLatestOnce',
              child: Text('Run Latest Once'),
            ),
            DropdownMenuItem(
              value: 'forceParallel',
              child: Text('Force Parallel'),
            ),
          ],
          onChanged: (value) => setState(() => overlap = value!),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () =>
            Navigator.pop(context, (precheck, overlap, draft, exactRevision)),
        child: const Text('Run'),
      ),
    ],
  );
}

class MobilePauseChoiceDialog extends StatelessWidget {
  const MobilePauseChoiceDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pause Automation'),
    content: const Text('Choose what to do with active runs.'),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context, 'continue-active'),
        child: const Text('Continue Active'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, 'cancel-active'),
        child: const Text('Cancel Active'),
      ),
    ],
  );
}
