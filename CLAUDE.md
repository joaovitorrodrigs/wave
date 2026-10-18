# Wave

Native macOS app: one place for tasks, agenda, habits, notes and personal finances.
Swift + SwiftUI + SwiftData. macOS 15 minimum. Public, MIT, "compile it yourself" in v1.

## Mandatory working mode

Every session that touches this repo invokes the `ponytail:ponytail` skill at `ultra`
before writing code. Smallest working diff, native framework before dependency,
no abstraction without a second use, every feature challenged before it enters.
No exceptions.

## Decisions (settled, do not reopen without the human)

- Tasks and agenda live in Apple Reminders and Calendar, read/written via EventKit.
  Wave is the interface, not the store.
- Notes live in Apple Notes, accessed via AppleScript: list, search, create.
  Editing opens Notes.app.
- Habits: HabitKit-style. Name, color, icon, set of completed days, GitHub-style
  grid, computed streak. Stored in SwiftData, local only, no iCloud.
- Finances: read-only mirror of Banco MCP REST API (`api.mcp.ai/api/openfinance`).
  Balances and transactions, cached locally. No manual entry. API key in Keychain.
- CLI `wave` ships inside the `.app`, shares code and store. `task add|list|done`,
  `note add`, one set of commands per module, `--json` output for agents.
- Menu bar panel: compact "Today" plus today's habits.
- UI native macOS look in v1. Brand identity applied later.
- Everything in English. Localization only when someone asks.
- No work/personal split yet. Reminders lists separate them for now.
- Gmail: not in v1.

## Build order

One module at a time, in daily use before the next starts:
tasks, agenda (inside Today), habits, notes, finances, menu bar.

## Boundaries

Not part of the Wave Studio wiki. The wiki ingests only what is exported to `raw/`.
