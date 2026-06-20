# Waylandar — Noctalia plugin

A Google Calendar agenda for the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) bar,
wrapping [Waylandar](https://github.com/samjoshuadud/waylandar)'s Python OAuth backend.

- **Bar pill** — shows your next event in the tooltip; click to open the agenda panel.
- **Panel** — upcoming schedule grouped by day (Today / Tomorrow / weekday), expandable cards with description + "Open in Browser".
- **Reminders** — fires `notify-send` alerts based on each event's Google Calendar reminder offsets.
- Themes automatically with Noctalia (uses `Color`/`Style` tokens).

## How it works

The plugin shells out to `waylandar-auth` (a wrapper at `~/.local/bin/waylandar-auth`)
which runs `backend/fetch_calendar.py` via `uv`. That script talks to the Google
Calendar API and prints JSON, which `Main.qml` parses into the agenda.

## Setup

1. **Dependencies:** `quickshell`, `uv`, `notify-send` (libnotify).
2. **Wrapper:** ensure `~/.local/bin/waylandar-auth` exists and points at this repo's `backend/`.
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
- **Sync interval** — background poll cadence (15m / 30m / 1h / 2h).

## Status

v0.1 — agenda panel + bar pill. Full-month dashboard (upstream's second mode) not yet ported.
