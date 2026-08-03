import 'package:flutter/material.dart';

class AutomationRunNowChoiceDialog extends StatefulWidget {
  const AutomationRunNowChoiceDialog({super.key});

  @override
  State<AutomationRunNowChoiceDialog> createState() =>
      _AutomationRunNowChoiceDialogState();
}

class _AutomationRunNowChoiceDialogState
    extends State<AutomationRunNowChoiceDialog> {
  bool _precheck = true;
  bool _draftTest = false;
  bool _exactRevision = false;
  String _overlap = 'skip';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Run Now'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SwitchListTile.adaptive(
            title: const Text('Run Precheck'),
            value: _precheck,
            onChanged: (value) => setState(() => _precheck = value),
          ),
          SwitchListTile.adaptive(
            title: const Text('Audited Draft Test'),
            value: _draftTest,
            onChanged: (value) => setState(() {
              _draftTest = value;
              if (value) _exactRevision = false;
            }),
          ),
          SwitchListTile.adaptive(
            title: const Text('Approve Exact Revision'),
            value: _exactRevision,
            onChanged: (value) => setState(() {
              _exactRevision = value;
              if (value) _draftTest = false;
            }),
          ),
          DropdownButtonFormField<String>(
            initialValue: _overlap,
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
            onChanged: (value) => setState(() => _overlap = value!),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop((_precheck, _overlap, _draftTest, _exactRevision)),
          child: const Text('Run'),
        ),
      ],
    );
  }
}

class AutomationPauseChoiceDialog extends StatelessWidget {
  const AutomationPauseChoiceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pause Automation'),
      content: const Text('Choose what to do with active runs.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop('continue-active'),
          child: const Text('Continue Active'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('cancel-active'),
          child: const Text('Cancel Active'),
        ),
      ],
    );
  }
}
