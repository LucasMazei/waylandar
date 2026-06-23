# Waylandar — Noctalia plugin

A Google Calendar agenda for the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) bar,
wrapping [Waylandar](https://github.com/samjoshuadud/waylandar)'s Python OAuth backend.

- **Bar pill** — shows your next event in the tooltip; click to open the panel.
- **Events tab** — upcoming schedule grouped by day (Today / Tomorrow / weekday); past & ongoing events tucked into a collapsible "Earlier" section. Expandable cards with description + "Open in Browser", plus a **Join** button for events with a Google Meet link. RSVP-aware styling: personal (no-guest) events are muted grey, **declined** events are dimmed + struck through in the error colour, attending events keep the accent.
- **Tasks tab** — open Google Tasks grouped by due day; tick the circle to complete or un-complete; completed items shown with their completion time (configurable days back).
- **Reminders** — `notify-send` alerts based on each event's Google Calendar reminder offsets.
- **Auto-join** — optionally open accepted calls in the browser ~1 min before they start (RSVP'd-yes only).
- Themes automatically with Noctalia (uses `Color`/`Style` tokens).

## How it works

The plugin shells out to `waylandar-auth` (a wrapper at `~/.local/bin/waylandar-auth`,
copy in this dir) which runs `backend/fetch_calendar.py` via `uv`. That script talks to
the Google Calendar/Tasks API and prints JSON, which `Main.qml` parses.

`Main.qml` invokes the wrapper by **absolute path** (`$HOME/.local/bin/waylandar-auth`)
and the wrapper **prepends `~/.local/bin` to its own `PATH`** — because Hypr can launch
quickshell with a minimal `PATH` that lacks `~/.local/bin` (where `uv` lives). Without
both, the plugin fails silently with an empty panel.

## Setup

1. **Dependencies:** `quickshell`, `uv`, `notify-send` (libnotify).
2. **Wrapper:** copy `waylandar-auth` (in this dir) to `~/.local/bin/waylandar-auth`,
   `chmod +x` it. It self-heals `PATH` and points at this repo's `backend/`.
3. **Google OAuth credentials** (one-time):
   - [Google Cloud Console](https://console.cloud.google.com/) → new project → enable **Google Calendar API**.
   - **Credentials** → create **OAuth 2.0 Client ID** (type: Desktop app) → download JSON.
   - Save it to `~/.config/waylandar/credentials.json`.
   - **Publish** the OAuth consent screen (Testing mode expires the token every 7 days).
4. **Authenticate** (one-time, opens a browser):
   ```bash
   waylandar-auth
   ```
5. **Enable** the plugin in Noctalia → Settings → Plugins → Waylandar.

## Optional keybind (Hyprland)

```conf
bind = $mainMod, K, exec, qs -c noctalia-shell ipc call plugin:waylandar toggle
```

## Settings

- **12-hour clock** — `1:30 PM` vs `13:30`.
- **Reminder notifications** — toggle the `notify-send` alerts.
- **Auto-open accepted calls** — open RSVP'd-yes meetings ~1 min before start.
- **Sync interval** — background poll cadence (15m / 30m / 1h / 2h).
- **Completed tasks shown (days)** — how far back to show completed tasks (default 1).
- **Past events shown (days)** — days of past/ongoing events in the "Earlier" section (default 1).

## Status

v0.5 — events + tasks tabs, join links, auto-join, configurable windows.
Full-month dashboard (upstream's second mode) not yet ported (see `TODO.md`).
