# Wave

One native macOS app for your tasks, agenda, habits, notes and personal finances.

Wave is an interface over what your Mac already has: Reminders and Calendar
(via EventKit), Apple Notes (via AppleScript), plus a local store for habits
and a read-only mirror of your bank through Banco MCP. Your data stays where
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

## Command line

The `.app` ships a `wave` binary. Put it on your PATH once:

```
ln -s /Applications/Wave.app/Contents/MacOS/wave /usr/local/bin/wave
```

```
wave task add "Buy milk" --list Personal --due "2026-10-20 09:00"
wave task list            # today
wave task list Personal
wave task done <id>
```

Add `--json` to any command for machine-readable output. Point an agent like
Claude at these commands and it can manage your tasks.

## Status

Early. Modules land one at a time: tasks, agenda, habits, notes, finances, menu bar.

## License

MIT.
