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
  grid, computed streak. Stored in SwiftData, local only, no iCloud, at
  `~/Library/Application Support/Wave/wave.store`. App only: no CLI for habits until
  someone asks Claude to check a habit (a second process writing the store needs
  change notifications the app does not have yet).
- Finances: read-only mirror of Banco MCP REST API (`api.mcp.ai/api/openfinance`, all
  POST with JSON bodies; `GET /_endpoints` lists them). Accounts with balances and the last
  30 days of transactions, cached in `~/Library/Application Support/Wave/finance.json`.
  No manual entry. API key in the Keychain, service `pro.wavestudio.wave`, account
  `bancomcp`, set from Settings (⌘,). App only, no CLI, same reasoning as habits.
- CLI `wave` ships inside the `.app` at `Contents/Helpers/wave` (not `MacOS/`: APFS is
  case-insensitive and `wave` would overwrite the app binary `Wave`). Target is `WaveCLI`,
  module `WaveCLI`, product `wave`, for the same reason.
- Any CLI command that touches a privacy-protected API (Reminders, Calendar, Apple Events)
  must run after the responsibility-disclaim re-spawn at the top of `CLI/main.swift`.
  Otherwise macOS attributes the request to the launching app (Terminal, Cursor, Claude
  Code) and hosts without the matching usage string are denied silently, no prompt.
- CLI `wave` shares code and store with the app. `task add|list|done`,
  `note add`, one set of commands per module, `--json` output for agents.
- Menu bar panel: compact "Today" plus today's habits.
- UI: a port of wavestudio.pro, not a native macOS look. Light only (the site has no dark
  mode): paper canvas, ink text, violet accent, green support, Instrument Sans (bundled, OFL).
  Hidden title bar; the site's navbar on top (brand left, page links centered, ink button
  right). Each page opens with the site's eyebrow + 36px two-tone heading. Vocabulary in
  `Wave/Theme.swift`: experience rows (`rounded-btn bg-ink/4%`, violet when current),
  nested cards (`rounded-3xl p-1.5` frame with `rounded-[18px]` paper blocks, ink + violet when
  highlighted), dark section (`rounded-[40px] bg-black` + grain, `#121212` cards), chips,
  long shadows, fade-and-rise on appear with the site's easing. Tokens from the wiki page
  `marca-visual` and `repos/site/src`. Icons are SF Symbols (bold/fill), not Phosphor.
- Everything in English. Localization only when someone asks.
- No work/personal split yet. Reminders lists separate them for now.
- Gmail: not in v1.

- Home: the dashboard and landing page of the app, modeled on the site's Home: hero with
  greeting and summary, the three social-proof cards (today's events, money in the dark card,
  habits as the stats deck with the brand pill), a month calendar with the selected day's
  events, tasks due in the next 7 days, recent notes. Reads through the same stores; no state
  of its own beyond the selected month and day.

## Build order

One module at a time, in daily use before the next starts:
tasks, agenda (inside Today), habits, notes, finances, menu bar.

## Build

Always pass `-derivedDataPath` outside the repo (for example `/tmp/wave-build`). The repo
lives in an iCloud-synced folder; Finder metadata on build output makes codesign fail with
"resource fork, Finder information, or similar detritus not allowed".

## Boundaries

Not part of the Wave Studio wiki. The wiki ingests only what is exported to `raw/`.
