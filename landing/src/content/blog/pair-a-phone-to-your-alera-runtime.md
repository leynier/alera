---
title: "Pair A Phone To Your Alera Runtime"
description: "The mobile companion is honest about what it is: a window into your runtime host, not a phone IDE. Here is what it does today."
pubDate: 2026-07-28T10:00:00.000Z
---

Picture the usual moment: you kicked off a long agent run, stepped away, and now you are on the couch wondering whether it finished, stalled, or is waiting for a yes/no only you can give. Walking back to the desk to check feels silly. SSHing from your phone feels worse.

That is the itch the Alera mobile companion scratches. And we want to be upfront about what it is: a foundation for remote awareness and terminal access, not an attempt to squeeze a full IDE onto a phone.

## What Ships Today

The companion is a separate Flutter app under `mobile/`, targeting Android and iOS. Pairing starts from **Settings → Mobile Devices** on the desktop, or through `alera mobile ...`.

The phone stores its device tokens in platform secure storage and connects to the runtime host's mobile WebSocket gateway. Once paired, it can:

- Mirror the desktop sidebar: grouping, sorting, filters, tags, pins, activity, agent presence, terminal indicators
- Browse the host filesystem and manage projects
- Rename workspace tabs and use managed-workspace actions
- Inspect and configure agent quotas
- Stream terminals, with local Terminal Quick Keys for the keys phones lack
- Install Alera agent skills and register the host CLI, no desktop process required

Just as important is what it cannot do. Host-admin RPCs and arbitrary runtime mutations stay off the mobile allowlist, so a paired phone cannot manage other devices or rewrite unrestricted runtime state. A lost phone should be an inconvenience, not an incident.

## The Desktop Does Not Have To Stay Open

This is the part that makes the companion genuinely useful rather than a demo. Because sessions belong to the [runtime host](/blog/how-alera-keeps-terminals-alive-after-you-quit) and not to the desktop window, you can quit the desktop UI entirely, keep the host running (including `alera runtime start` on a workstation or VPS), and still attach from the phone.

Your agents keep working on a machine that is awake. You keep an eye on them from a device that is in your pocket. Each one does what it is good at.

## What Comes Later

The roadmap lists richer file review and non-terminal surfaces for mobile, and we will get there. But we would rather ship a trustworthy remote window today than promise a pocket workbench we cannot yet stand behind. If you try it, treat it as what it is: awareness and terminal access to a host you already trust.

[Download Alera](/download) on desktop, enable Mobile Devices, and pair the next time a long run would otherwise chain you to your desk.
