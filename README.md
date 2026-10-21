# Wave

One native macOS app for your tasks, agenda, habits, notes and personal finances.

Wave is an interface over what your Mac already has: Reminders and Calendar
(via EventKit), plus a local store for notes, habits and clients
(in `~/Library/Application Support/Wave/`) and a read-only mirror of your bank
through Banco MCP. Your data stays where
it is and syncs to your iPhone through Apple's own apps.

Ships with a `wave` command-line tool so agents like Claude can create tasks
and notes for you.

## Requirements

- macOS 15 or newer
- Xcode 16 or newer

## Build

1. Clone this repo.
2. Open `Wave.xcodeproj` in Xcode.
3. Press Run.

## Install

```
xcodebuild -scheme Wave -configuration Release -derivedDataPath /tmp/wave-build
rm -rf /Applications/Wave.app && cp -R /tmp/wave-build/Build/Products/Release/Wave.app /Applications/
ln -sf /Applications/Wave.app/Contents/Helpers/wave /opt/homebrew/bin/wave
```

First launch asks for Reminders access. The `wave` command asks once more, for itself.
For bank data, create a read-only key at https://app.mcp.ai/settings/api-keys and paste it in
Settings (⌘,). It lives in your Keychain; the last fetch is cached in
`~/Library/Application Support/Wave/finance.json`.

## What it does

- **Home**: greeting, today's events, bank balance, habits to tap, month calendar, tasks due this week, recent notes.
- **Today**: tasks from Reminders (date, time, alert, repeat, list, priority, URL), today's events, unread Gmail with "make a task".
- **Calendar**: week and month views, create and edit events in your Mac calendars.
- **Habits**: HabitKit-style cards with a half-year grid and streaks, stored locally.
- **Notes**: written and kept in Wave, list and editor side by side, saved as you type. One-click import from Apple Notes.
- **Finances**: accounts and transactions from Banco MCP, spending by category against last month, Stripe revenue.
- **Clients**: everything that carries a client's name, in one place.
- **Review**: the week in three cards.
- Habits widget for the desktop (Notification Center > Edit Widgets > Wave), tap to check today.
- Menu bar panel, ⌘⇧Space quick add from any app, 8:00 morning summary, Siri ("Add a task in Wave"), ⌘K search.

Gmail needs your own OAuth client: in Google Cloud enable the Gmail API, create an OAuth client of
type Desktop app, paste its ID and secret in Settings (⌘,) and connect. Stripe takes a restricted
key with read access to Balance and Charges.

## Command line

```
wave today                # today's events and tasks
wave task add "Buy milk" --list Personal --due "2026-10-20 09:00"
wave task list            # today
wave task list Personal
wave task done <id>
```

Add `--json` to any command for machine-readable output. Point an agent like
Claude at these commands and it can manage your tasks.

## Status

Home dashboard, tasks, agenda, habits, notes and finances are in. Menu bar panel is next.

## License

MIT. Instrument Sans is bundled under the SIL Open Font License (`Wave/Fonts/OFL.txt`).
