part of 'mobile_ai_dictation_settings_screen.dart';

class _EnableCard extends StatelessWidget {
  const _EnableCard({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Row(
          children: <Widget>[
            Container(
              width: AleraTokens.minTapTarget,
              height: AleraTokens.minTapTarget,
              decoration: BoxDecoration(
                color: enabled
                    ? AleraTokens.accentSubtle
                    : AleraTokens.surfaceElevated,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: Border.all(color: AleraTokens.border),
              ),
              child: Icon(
                AleraIcons.mic,
                color: enabled
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(width: AleraTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Enable AI Dictation',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    'Add microphone controls to composers and New Workspace From Prompt.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            Switch(value: enabled, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _LanguageField extends StatefulWidget {
  const _LanguageField({required this.language, required this.onChanged});

  final String? language;
  final ValueChanged<String?> onChanged;

  @override
  State<_LanguageField> createState() => _LanguageFieldState();
}

class _LanguageFieldState extends State<_LanguageField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.language ?? '');
    _focus = FocusNode()..addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant _LanguageField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.language ?? '';
    if (!_focus.hasFocus && _controller.text != next) {
      _controller.text = next;
    }
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focus.hasFocus) _save();
  }

  void _save() {
    final value = _controller.text.trim();
    widget.onChanged(value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: _controller,
      focusNode: _focus,
      labelText: 'Language Or Locale',
      hintText: 'en-US',
      helperText: 'Leave blank to detect the language automatically.',
      onSubmitted: (_) => _save(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AleraTokens.space4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ],
      ),
    );
  }
}

class _HelperText extends StatelessWidget {
  const _HelperText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}
