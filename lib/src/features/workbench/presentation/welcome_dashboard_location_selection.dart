part of 'welcome_dashboard.dart';

const String _checkoutMenuValue = 'checkout';
const String _worktreeMenuValue = 'worktree';
const String _loadingBranchesMenuValue = 'loading-branches';

extension _WelcomeDashboardLocationSelection on _WelcomeDashboardState {
  String _sourceLabel() {
    if (_loadingBranches) return 'Loading Branches';
    final branch = _sourceBranch?.trim() ?? '';
    return branch.isEmpty ? 'Select Branch' : 'From $branch';
  }

  Future<void> _pickLocation(BuildContext context) async {
    final project = _boundProject;
    if (project == null || !project.isGitRepository) return;
    final selected = await showHomeComposerMenu(
      context: context,
      choices: [
        HomeComposerMenuChoice(
          value: _checkoutMenuValue,
          label: 'Current Checkout',
          selected: _useProjectCheckout,
        ),
        HomeComposerMenuChoice(
          value: _worktreeMenuValue,
          label: 'New Worktree',
          selected: !_useProjectCheckout,
        ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == _checkoutMenuValue) {
      _branchGeneration++;
      _update(() {
        _useProjectCheckout = true;
        _loadingBranches = false;
        _branchesAwaitEnrollment = false;
        _error = null;
      });
      return;
    }
    _update(() {
      _useProjectCheckout = false;
      _error = null;
      _sourceBranch ??= pickDefaultSourceBranch(_branches);
    });
    if (_branches.isEmpty && !_loadingBranches) {
      unawaited(_loadBranches(project));
    }
  }

  Future<void> _pickSource(BuildContext context) async {
    final project = _boundProject;
    if (project == null || _useProjectCheckout || !project.isGitRepository) {
      return;
    }
    if (_branches.isEmpty && !_loadingBranches) await _loadBranches(project);
    if (!mounted || !context.mounted || _useProjectCheckout) return;
    final generation = _branchGeneration;
    final selected = await showHomeComposerMenu(
      context: context,
      choices: [
        if (_loadingBranches && _branches.isEmpty)
          const HomeComposerMenuChoice(
            value: _loadingBranchesMenuValue,
            label: 'Loading Branches',
            enabled: false,
          ),
        for (final branch in _branches)
          if (branch.isNotEmpty)
            HomeComposerMenuChoice(
              value: branch,
              label: branch,
              selected: branch == _sourceBranch,
            ),
      ],
    );
    if (!mounted ||
        generation != _branchGeneration ||
        _useProjectCheckout ||
        selected == null ||
        selected == _loadingBranchesMenuValue) {
      return;
    }
    _update(() {
      _sourceBranch = selected;
      _error = null;
    });
  }
}
