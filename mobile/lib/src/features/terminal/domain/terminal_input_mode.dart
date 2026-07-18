/// How keystrokes reach the terminal on the phone. Compose is the default:
/// text is written in a field and sent as one message. Direct streams every
/// keystroke to the PTY immediately, like Orca's live input mode.
enum TerminalInputMode { compose, direct }
