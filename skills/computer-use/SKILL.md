---
name: computer-use
description: Use when reading or operating local desktop application windows through Alera: listing apps and windows, reading a window's accessibility tree, clicking controls, writing values, or invoking accessibility actions. Also covers browser windows and webviews as desktop apps.
metadata:
  version: 1
---

# Alera Computer Use

Use the `alera computer` commands to inspect and operate desktop application windows. When the target is a website, operate the desktop browser window that shows the page: app selectors name desktop applications, not websites.

## Check What This Session Supports First

```bash
alera computer --json capabilities
```

It answers on every machine, including a server with no desktop, so one call tells you whether to continue. Read `supported`, and when it is false read `unsupportedReason` and stop. Read `supports.actions` before planning: what is available differs by machine, and a verb reported unavailable will not start working on retry.

Note that `--json` belongs to the command group, before the subcommand:

```bash
alera computer --json get-app-state --app krunner
```

## The Loop

```bash
alera computer --json list-apps
alera computer --json get-app-state --app krunner
alera computer --json click --app krunner --element-index 5
```

Every action returns a fresh observation, so you never need a separate read between steps. Take the next element index from the reply you just got.

## Element Indexes Are Short-Lived And Sparse

The number at the start of each tree line is how you address an element. Three rules, and breaking any of them is the most common way an agent operates the wrong control:

- **Never infer an index.** `elementCount` is a count, not a bound. Noise reduction drops elements after they are numbered, so the surviving numbers have gaps.
- **Never carry an index across a change.** Navigation, scrolling, a focus change, or a re-render invalidate them. Re-read instead.
- **Never carry an index between apps or windows.** Each observation belongs to one window.

Alera re-checks the element's identity before acting and refuses with `element_not_found` when it changed. That refusal is protection, not a glitch: act on it by re-reading.

## Reading A Window

```bash
alera computer --json get-app-state --app <name|pid:N> [--window-index N] [--no-screenshot]
```

Defaults to the active window. Use `list-windows --app <app>` first when an app has several, and pass `--window-index`. On Linux there is no window handle to pass: `--window-id` is refused, because AT-SPI exposes no stable one.

Concealed fields report `[redacted]` and `concealed` with no value. That is deliberate; do not try to read them another way.

## Acting

```bash
alera computer --json click --app <app> --element-index N
alera computer --json set-value --app <app> --element-index N --value "text"
alera computer --json perform-secondary-action --app <app> --element-index N --action <name>
```

- **Prefer `set-value` for text fields.** It needs no keyboard focus, so it cannot deliver text to a window that took focus in between, and it is the only action whose effect can be confirmed.
- **Use `click` for controls.** It invokes the element's own action, so it works on an unfocused window.
- **Use `perform-secondary-action` only with a name the tree lists** for that element.
- For sensitive text use `--value-stdin` so it stays out of shell history.

### Read The Verification Before Assuming It Worked

Every action reports `verification`:

- `state: "verified"` means the value was read back and matched.
- `state: "unverified"` means the action was accepted but its effect was not confirmed. `reason: "action_invoked"` is the normal case for `click` and for action invocation.

An action reported unverified may well have worked. Do not assume it did: read the returned tree and confirm the change you expected is there before building on it.

## What Is Not Available On Linux

Synthetic keyboard and pointer input (`type-text`, `press-key`, `hotkey`, `paste-text`, `scroll`, `drag`) and screen capture are not offered. Under Wayland a client cannot inject input or capture the screen without the desktop portal, which Alera does not use yet. `capabilities` reports this, and the accessibility tree is the surface to work with instead.

Some applications expose little or nothing to the accessibility layer. Electron and Chromium windows in particular often report only the window with no children unless they were started with accessibility enabled. An empty tree is that situation, not a failure to retry; tell the user rather than looping.

## Errors

Every failure carries a `code` and `nextSteps`. Follow the steps rather than repeating the call.

| Code | What to do |
|---|---|
| `app_not_found` | Run `list-apps` and use the name it reports. For a web app, target the browser window. |
| `app_blocked` | Stop. Password managers are refused and retrying cannot succeed. |
| `window_not_found` | Run `list-windows` and pass a selector it reports. |
| `element_not_found` | The index is stale or was never handed out. Re-read and use a fresh index. |
| `element_not_clickable` | Use a parent or child element that exposes an action. |
| `action_not_supported` | Use one of the action names the tree lists for that element. |
| `value_not_settable` | The element has no editable text. Do not assume a write happened. |
| `unsupported_capability` | Run `capabilities`; use a supported alternative. |
| `permission_denied` | Run `permissions` to see the missing grant. |
| `accessibility_error` | Run `capabilities`; the bus may be unreachable. |
| `action_timeout` | Re-read the state before retrying, then use a simpler action. |
| `screenshot_failed` | Pass `--no-screenshot` if the tree is enough. |
| `invalid_argument` | Fix the flags. Do not repeat the command unchanged. |

## Boundaries

Reading a window the user asked about is ordinary work. These are not:

- Do not submit forms, send messages, post, buy, delete data, or change account settings unless the user asked for that specific action.
- Do not read more of an app than the user asked about, and do not repeat sensitive content you encounter into your output.
- Password managers are blocked outright. Do not look for a way around it.

If an action would do something outward-facing or hard to undo, say what you are about to do and confirm first.
