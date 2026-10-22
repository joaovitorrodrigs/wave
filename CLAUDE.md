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
- Notes live in Wave's own store (SwiftData `Note`: title, plain text, dates). Notes page is
  list plus editor, saved as you type. CLI and Siri write to the same store; the page re-fetches
  when the app becomes active. Settings has a one-shot "Import from Apple Notes" (AppleScript,
  read-only). Decided 2026-10-20: one environment beats iPhone sync for João.
- Habits: HabitKit-style. Name, color, icon, set of completed days, GitHub-style
  grid, computed streak. Stored in SwiftData, local only, no iCloud, at
  `~/Library/Application Support/Wave/wave.store`. No CLI for habits yet.
- Finances: read-only mirror of Banco MCP REST API (`api.mcp.ai/api/openfinance`, all
  POST with JSON bodies; `GET /_endpoints` lists them) plus Stripe. Twelve months of
  transactions, accounts, card bills, investments and the bank's 130 categories, cached in
  `~/Library/Application Support/Wave/finance-v2.json` and topped up incrementally (a week of
  overlap) on every refresh; one net-worth point per day. No manual entry. Rules (SwiftData
  `FinanceRule`: "description contains X" → rename, recategorize, ignore) and budgets
  (`Budget` per parent category) are the user's layer, applied at display time over the whole
  year. Five tabs on one page: Overview, Transactions, Cards, Investments, Rules. Charts are
  Canvas (`Charts.swift`). CLI: `wave finance summary|transactions [--month YYYY-MM]`, read-only.
  API key in the Keychain, service `pro.wavestudio.wave`, account `bancomcp`, set from Settings.
- CLI `wave` ships inside the `.app` at `Contents/Helpers/wave` (not `MacOS/`: APFS is
  case-insensitive and `wave` would overwrite the app binary `Wave`). Target is `WaveCLI`,
  module `WaveCLI`, product `wave`, for the same reason.
- Any CLI command that touches a privacy-protected API (Reminders, Calendar, Apple Events)
  must run after the responsibility-disclaim re-spawn at the top of `CLI/main.swift`.
  Otherwise macOS attributes the request to the launching app (Terminal, Cursor, Claude
  Code) and hosts without the matching usage string are denied silently, no prompt.
- CLI `wave` shares code and store with the app. `task add|list|done`,
  `note add`, one set of commands per module, `--json` output for agents.
- Menu bar: our own `NSStatusItem` and a borderless transparent panel (`MenuBar.swift`), not
  `MenuBarExtra`, so there is no system chrome. Shows today's events and tasks. Habits are not
  there: they are a widget.
- Widget (`Widget/`, target `WaveWidget`, sandboxed, ad-hoc signed): the app's habit cards on the
  desktop, tap the icon to check today. No app group (that entitlement needs a developer
  certificate), so the app writes `habits.json` into the widget's own sandbox container
  (`~/Library/Containers/pro.wavestudio.wave.widgets/Data/Library/Application Support/Wave`) and
  the widget writes `toggles.json` back; `WidgetBridge.swift` folds toggles into the store on
  activation, on every save and through a file watcher while the app runs. The widget's first run
  creates the container; until then the app has nowhere to write.
- UI: a port of wavestudio.pro, not a native macOS look. Light only (the site has no dark
  mode): paper canvas, ink text, violet accent, green support, Instrument Sans (bundled, OFL).
  Hidden title bar; the site's navbar on top (brand left, page links centered, ink button
  right). Each page opens with the site's eyebrow + 36px two-tone heading. Vocabulary in
  `Wave/Theme.swift`: experience rows (`rounded-btn bg-ink/4%`, violet when current),
  nested cards (`rounded-3xl p-1.5` frame with `rounded-[18px]` paper blocks, ink + violet when
  highlighted), dark section (`rounded-[40px] bg-black` + grain, `#121212` cards), chips,
  long shadows, fade-and-rise on appear with the site's easing. Tokens from the wiki page
  `marca-visual` and `repos/site/src`. Icons are Phosphor (fill) through the PhosphorSwift package, by kebab-case name via `Icon`.
- Nothing native in the UI. No sheets, DatePicker, Picker, Toggle, context menus, ProgressView or
  Settings scene: modals are overlays (`UI.swift`), controls live in `Controls.swift` (Switch,
  Select, DateField with the month grid, TimeRow, Spinner, MenuButton). Text inputs are styled
  TextFields. The only system chrome left is window frames, the menu bar popover and permission
  dialogs.
- Pages: Home (dashboard), Today (tasks, events, Gmail inbox), Calendar (week/month, events
  read-write), Habits, Notes (own store), Finances (accounts, Stripe, categories), Clients
  (name-matched tasks/events/notes/payments, SwiftData `Client`), Review (week: done tasks,
  habits, money). Store lives in `Shared/Database.swift` (Habit, Client, Note).
- System: menu bar panel (`MenuBar.swift`), global quick add ⌥Space via Carbon hot key and a
  non-activating panel (`QuickAdd.swift`), 8:00 summary notification (`Morning.swift`), App
  Intents for Siri/Shortcuts (`Intents.swift`), ⌘1-8 pages, ⌘N new item, ⌘K palette, ⌘, settings.
- Gmail: read-only, user-supplied OAuth client (Desktop app), PKCE + loopback listener on
  127.0.0.1, refresh token in Keychain (`Gmail.swift`). Stripe: restricted key in Keychain,
  balance and this month's charges. Keys never leave the Keychain; nothing is hardcoded.
- Dark mode: flat black canvas, ink and paper swap, `#121212` card becomes light gray, shadows
  stay black, grain only on the dark sections. Setting System/Light/Dark in `@AppStorage("theme")`.
- Navigation is the Dock (`Dock.swift`, port of skecher-ui's dock): magnification only, no hover
  highlight, violet for the active page, search and settings after a separator.
- Danger red `#DC2F3A` (not on the site) for delete, overdue, errors, rising spend.
- Everything in English. Localization only when someone asks.
- No work/personal split yet. Reminders lists separate them for now.

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
After copying the Release build to `/Applications`, delete the build products: every leftover
`Wave.app` gets registered by LaunchServices and shows up twice in Spotlight.

## Boundaries

Not part of the Wave Studio wiki. The wiki ingests only what is exported to `raw/`.
