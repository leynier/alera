/// The three parts of Activity, in the order the segmented control shows them.
enum ActivitySection {
  runs('Runs'),
  questions('Questions'),
  automations('Automations');

  ActivitySection(this.label);

  final String label;
}
