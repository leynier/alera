import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:flutter/material.dart';

/// Pause after the last keystroke before the issue is fetched.
const Duration mobileIssueUrlResolveDelay = Duration(milliseconds: 400);

/// Optional issue URL input that resolves the issue in the background. A
/// failed resolve is a warning, never a blocker: the URL is still linked.
class const MobileIssueUrlField({
  super.key,
  required final TextEditingController controller,
  required final Future<MobileIssueDetails> Function(String url) fetchIssue,
  final ValueChanged<MobileIssueDetails>? onResolved,
  final bool enabled = true,
  final bool autofocus = false,
}) extends StatefulWidget {
  @override
  State<MobileIssueUrlField> createState() => _MobileIssueUrlFieldState();
}

class _MobileIssueUrlFieldState extends State<MobileIssueUrlField> {
  Timer? _debounce;
  String _requestedUrl = '';
  bool _resolving = false;
  MobileIssueDetails? _issue;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.controller.text.trim().isNotEmpty) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (widget.controller.text.trim() != _requestedUrl) {
      _schedule();
    }
  }

  void _schedule() {
    _debounce?.cancel();
    final url = widget.controller.text.trim();
    _requestedUrl = url;
    setState(() {
      _issue = null;
      _error = null;
      _resolving = url.isNotEmpty;
    });
    if (url.isNotEmpty) {
      _debounce = Timer(
        mobileIssueUrlResolveDelay,
        () => unawaited(_resolve(url)),
      );
    }
  }

  Future<void> _resolve(String url) async {
    try {
      final issue = await widget.fetchIssue(url);
      if (!mounted || url != _requestedUrl) {
        return;
      }
      setState(() {
        _issue = issue;
        _resolving = false;
      });
      widget.onResolved?.call(issue);
    } on Object catch (error) {
      if (!mounted || url != _requestedUrl) {
        return;
      }
      setState(() {
        _error = error.toString();
        _resolving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    final helper = _resolving
        ? 'Resolving issue'
        : issue != null
        ? '#${issue.number} · ${issue.displayState} · ${issue.title}'
        : _error != null
        ? 'Could not read the issue. The link will still be saved.'
        : 'GitHub, GitLab, Azure DevOps, or any tracker URL';
    return TextField(
      key: const ValueKey<String>('mobile-issue-url-field'),
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.url,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'Issue URL (Optional)',
        helperText: helper,
        helperMaxLines: 2,
        helperStyle: _error != null && issue == null && !_resolving
            ? const TextStyle(color: AleraTokens.warning)
            : null,
      ),
    );
  }
}
