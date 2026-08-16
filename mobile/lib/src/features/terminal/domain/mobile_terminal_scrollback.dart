/// How many lines a phone's terminal emulator keeps.
///
/// This is a line budget standing in for a cell budget, which is what actually
/// costs memory: a line allocates its full width whatever it holds, at 16 bytes
/// per cell. The desktop keeps `scrollbackLines` (10000 by default) at a
/// desktop width of roughly 200 columns, so about 2M cells.
///
/// A phone is roughly a quarter as wide, so holding the same history takes
/// about four times the lines at a quarter of the width: the same 2M cells, and
/// the same memory the desktop already spends. 5000 lines, which is what this
/// was, showed barely a tenth of what the desktop showed once the restored
/// history was reflowed down to the phone's width.
///
/// The peak is higher than the resting cost: history is replayed at the host's
/// width before the view reflows it, so the same lines are briefly four times
/// wider. What bounds that is the host's own `restoreSnapshotBytes` cap on how
/// much it will send.
const int mobileTerminalScrollbackLines = 40000;
