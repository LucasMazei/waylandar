# Waylandar plugin — TODO

## Join calls
- [ ] **Click an event to join its meeting** when it has a conference link.
  - Backend: in `get_upcoming_events`, extract the meeting URL — Google Meet via
    `event.conferenceData.entryPoints[].uri` (type `video`), and fall back to
    `event.hangoutLink` or a URL parsed from `location`/`description`.
  - Emit it as `meetLink` on each event object.
  - Frontend: `EventCard` shows a "Join" button when `meetLink` is set →
    `Qt.openUrlExternally(meetLink)`.

## Auto-open accepted calls
- [ ] **Setting to auto-open the call in the browser 1 min before it starts**, only
      for meetings I've RSVP'd **yes** to.
  - Backend: read the self attendee's `responseStatus`
    (`event.attendees[] where self == true`). Emit `rsvp` = `accepted` /
    `declined` / `tentative` / `needsAction`.
  - Only auto-open when `rsvp === "accepted"` AND a `meetLink` exists.
    Ignore `declined` / `needsAction`.
  - Frontend: new setting `autoJoinAcceptedCalls` (bool, default off). The 1-min
    reminder ticker in `Main.qml` already loops events every minute — when enabled,
    `Qt.openUrlExternally(meetLink)` once at T-1min (guard with a `opened_for` flag
    like the existing `notified_for`).
  - Edge cases to handle: don't re-open on every sync (dedupe by event id+start);
    skip all-day events; respect the user being away/asleep? (probably not — keep simple).
