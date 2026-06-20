# Waylandar plugin — TODO

## Join calls — DONE (v0.5.0)
- [x] **Click an event to join its meeting** when it has a conference link.
  - Backend `_meet_link()` extracts the Google Meet `video` entry point (fallback
    `hangoutLink`), emitted as `meetLink` on each event.
  - `EventCard` shows a "Join" pill (top-right) when `meetLink` is set →
    `Qt.openUrlExternally(meetLink)`.

## Auto-open accepted calls — DONE (v0.5.0)
- [x] **Setting to auto-open the call ~1 min before it starts**, only for meetings
      I've RSVP'd **yes** to.
  - Backend `_rsvp_status()` reads the self attendee's `responseStatus` (events with
    no attendees = my own → `accepted`), emitted as `rsvp`.
  - Setting `autoJoinAcceptedCalls` (bool, default off). The 1-min reminder ticker
    opens `meetLink` once when `rsvp === "accepted"`, the start is within ±1 min, and
    it's not all-day. Deduped via `openedCalls` (key = event id + start) so it fires
    exactly once per occurrence. Declined / needsAction are ignored.

## Ideas / backlog
- [ ] Un-RSVP'd events: surface a quick accept/decline action from the card.
- [ ] Honor `tentative` as an optional auto-join target (currently only `accepted`).
- [ ] Port the upstream full-month dashboard as a second panel mode.
