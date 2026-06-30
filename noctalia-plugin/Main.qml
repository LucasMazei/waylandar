import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    // Absolute path to the backend wrapper — quickshell may be launched (by Hypr)
    // with a minimal PATH that lacks ~/.local/bin, so we can't rely on bare lookup.
    readonly property string authCmd: (Quickshell.env("HOME") || "/home/Usuario") + "/.local/bin/waylandar-auth"

    // ---- Public state (read by Panel / BarWidget) ----
    property var calendarEvents: []        // all events (for BarWidget / reminders)
    property var upcomingEvents: []        // today + future, with .sectionTitle
    property var pastEvents: []            // within days-back window, de-emphasised
    property var tasks: []                 // open Google Tasks, soonest-due first
    property bool isSyncing: false
    property string authError: ""
    property int minutesUntilSync: syncIntervalMinutes
    property var lastSync: null

    // ---- Settings (mirrored from pluginApi.pluginSettings) ----
    property int syncIntervalMinutes: pluginApi?.pluginSettings?.syncIntervalMinutes ?? 60
    property bool use12hourFormat: pluginApi?.pluginSettings?.use12hourFormat ?? false
    property bool notifyReminders: pluginApi?.pluginSettings?.notifyReminders ?? true
    property int completedTaskDays: pluginApi?.pluginSettings?.completedTaskDays ?? 1
    property int eventDaysBack: pluginApi?.pluginSettings?.eventDaysBack ?? 1
    property bool autoJoinAcceptedCalls: pluginApi?.pluginSettings?.autoJoinAcceptedCalls ?? false

    // Meet links already auto-opened this session (key = event id+start), so the
    // 1-minute ticker fires each call exactly once.
    property var openedCalls: ({})

    // ---- Daily habits (local, vault-backed JSON; independent of Calendar/Tasks) ----
    // Source of truth is a plain JSON file in the vault, so the daily/shutdown
    // skills can read it and it syncs across machines. The panel is the writer.
    readonly property string habitsPath: (pluginApi?.pluginSettings?.habitsFilePath && pluginApi.pluginSettings.habitsFilePath.length > 0)
        ? pluginApi.pluginSettings.habitsFilePath
        : ((Quickshell.env("HOME") || "/home/Usuario") + "/Insync/mazei.lucas@gmail.com/Google Drive/Obsidian/Study/5. Daily Journal/habits.json")

    property string todayKey: ""
    readonly property var habitDefs: habitsAdapter.habits
    readonly property var habitLog: habitsAdapter.log
    readonly property var todayDone: (habitLog && habitLog[todayKey]) ? habitLog[todayKey] : []

    signal eventsUpdated()
    signal tasksUpdated()
    signal habitsUpdated()

    onPluginApiChanged: {
        if (pluginApi) {
            Logger.i("Waylandar", "pluginApi available")
            initializePluginSettings()
            sync()
        }
    }

    function initializePluginSettings() {
        if (!pluginApi) return
        if (pluginApi.pluginSettings?.syncIntervalMinutes === undefined) {
            pluginApi.pluginSettings = {
                syncIntervalMinutes: 60,
                use12hourFormat: false,
                notifyReminders: true,
                completedTaskDays: 1,
                eventDaysBack: 1,
                autoJoinAcceptedCalls: false
            }
            pluginApi.saveSettings()
        }
        reloadSettings()
        minutesUntilSync = syncIntervalMinutes
    }

    // Re-read settings when changed via the Settings UI
    function reloadSettings() {
        if (!pluginApi?.pluginSettings) return
        syncIntervalMinutes = pluginApi.pluginSettings.syncIntervalMinutes ?? 60
        use12hourFormat = pluginApi.pluginSettings.use12hourFormat ?? false
        notifyReminders = pluginApi.pluginSettings.notifyReminders ?? true
        autoJoinAcceptedCalls = pluginApi.pluginSettings.autoJoinAcceptedCalls ?? false
        var prevCompleted = completedTaskDays
        var prevBack = eventDaysBack
        completedTaskDays = pluginApi.pluginSettings.completedTaskDays ?? 1
        eventDaysBack = pluginApi.pluginSettings.eventDaysBack ?? 1
        if (completedTaskDays !== prevCompleted || eventDaysBack !== prevBack)
            Qt.callLater(sync)   // re-fetch with the new windows
    }

    function sync() {
        if (fetchProcess.running) return
        minutesUntilSync = syncIntervalMinutes
        isSyncing = true
        fetchProcess.running = true
        if (!tasksProcess.running)
            tasksProcess.running = true
    }

    // ---- Backend fetch (Google Calendar via the waylandar-auth wrapper) ----
    Process {
        id: fetchProcess
        command: [authCmd, "--days-back", String(eventDaysBack), "--background"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                isSyncing = false
                try {
                    var parsed = JSON.parse(text)

                    if (parsed.error) {
                        authError = parsed.error
                        calendarEvents = []
                        upcomingEvents = []
                        pastEvents = []
                        root.eventsUpdated()
                        return
                    }

                    authError = ""
                    lastSync = new Date()

                    var today = new Date(); today.setHours(0, 0, 0, 0)
                    var past = [], upcoming = []
                    for (var i = 0; i < parsed.length; i++) {
                        var ev = parsed[i]
                        var sd = eventStartDate(ev.start)
                        var diff = Math.round((sd.getTime() - today.getTime()) / 86400000)
                        ev.isPast = diff < 0
                        if (diff === 0) ev.sectionTitle = "Today"
                        else if (diff === 1) ev.sectionTitle = "Tomorrow"
                        else ev.sectionTitle = Qt.locale().toString(sd, "dddd, MMM d")
                        ev.notified_for = []
                        ;(ev.isPast ? past : upcoming).push(ev)
                    }
                    calendarEvents = upcoming.concat(past)  // for BarWidget / reminders
                    upcomingEvents = upcoming
                    pastEvents = past
                    root.eventsUpdated()
                } catch (e) {
                    Logger.e("Waylandar", "Failed to parse backend output: " + e)
                }
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text && text.trim().length > 0)
                    Logger.w("Waylandar", "backend stderr: " + text.trim())
            }
        }
    }

    // ---- Backend fetch (Google Tasks) ----
    Process {
        id: tasksProcess
        command: [authCmd, "--tasks", "--completed-days", String(completedTaskDays), "--background"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var parsed = JSON.parse(text)
                    if (parsed.error) {
                        // Auth/scope problem is already surfaced by the calendar fetch.
                        tasks = []
                        root.tasksUpdated()
                        return
                    }
                    tasks = processTasks(parsed)
                    root.tasksUpdated()
                } catch (e) {
                    Logger.e("Waylandar", "Failed to parse tasks output: " + e)
                }
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text && text.trim().length > 0)
                    Logger.w("Waylandar", "tasks stderr: " + text.trim())
            }
        }
    }

    // ---- System notification for per-event reminders ----
    Process {
        id: notifyProcess
        command: []
        function send(title, body) {
            command = ["notify-send", "-a", "Waylandar", "-i", "calendar", title, body]
            running = true
        }
    }

    // ---- Countdown + reminder ticker (1 min) ----
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            // Roll the habit day over at midnight so the tab tracks the right date.
            var tk = _todayKey()
            if (tk !== todayKey) todayKey = tk

            if (notifyReminders) {
                var now = new Date()
                for (var i = 0; i < calendarEvents.length; i++) {
                    var ev = calendarEvents[i]
                    if (!ev.reminders) continue
                    if (!willAttend(ev)) continue   // only events I'll attend
                    var diffMins = Math.floor((new Date(ev.start).getTime() - now.getTime()) / 60000)
                    if (ev.reminders.indexOf(diffMins) !== -1 && ev.notified_for.indexOf(diffMins) === -1) {
                        var timeStr = formatTime(new Date(ev.start))
                        notifyProcess.send("󰃭 " + ev.title, "Starts in " + diffMins + " min at " + timeStr)
                        ev.notified_for.push(diffMins)
                    }
                }
            }

            // Auto-open accepted calls ~1 min before they start (RSVP'd yes only).
            if (autoJoinAcceptedCalls) {
                var nowJ = new Date()
                for (var j = 0; j < upcomingEvents.length; j++) {
                    var e2 = upcomingEvents[j]
                    if (!e2.meetLink || e2.meetLink.length === 0) continue
                    if (e2.rsvp !== "accepted") continue
                    if (typeof e2.start === "string" && e2.start.length === 10) continue // all-day
                    var key = (e2.id || "") + "@" + e2.start
                    if (openedCalls[key]) continue
                    var dm = Math.floor((new Date(e2.start).getTime() - nowJ.getTime()) / 60000)
                    if (dm <= 1 && dm >= -1) {
                        Qt.openUrlExternally(e2.meetLink)
                        openedCalls[key] = true
                        notifyProcess.send("󰸋 " + e2.title, "Opening the call…")
                    }
                }
            }

            if (minutesUntilSync > 0)
                minutesUntilSync--
            if (minutesUntilSync <= 0) {
                minutesUntilSync = syncIntervalMinutes
                sync()
            }
        }
    }

    // ---- IPC (keybind toggle) ----
    IpcHandler {
        target: "plugin:waylandar"
        function toggle() { pluginApi?.withCurrentScreen(s => pluginApi.togglePanel(s)) }
        function refresh() { root.sync() }
    }

    // ---- Helpers shared with Panel/BarWidget ----
    function formatTime(date) {
        if (!date || isNaN(date.getTime())) return ""
        return use12hourFormat
            ? Qt.locale().toString(date, "h:mm AP")
            : Qt.locale().toString(date, "HH:mm")
    }

    // Event start → local midnight Date. All-day events arrive as "YYYY-MM-DD"
    // (no tz); parse the date parts directly to avoid a UTC->local day shift.
    function eventStartDate(s) {
        if (typeof s === "string" && s.length === 10) {
            var p = s.split("-")
            return new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]))
        }
        var d = new Date(s)
        return new Date(d.getFullYear(), d.getMonth(), d.getDate())
    }

    // Google Tasks "due" is a date-only value pinned to UTC midnight; parsing it
    // with `new Date()` shifts it a day in negative-offset zones (BRT). Parse the
    // date portion as a LOCAL date instead.
    function dueLocalDate(due) {
        if (!due) return null
        var p = ("" + due).substring(0, 10).split("-")
        if (p.length < 3) return null
        var d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2]))
        return isNaN(d.getTime()) ? null : d
    }

    function dueIsOverdue(due) {
        var d = dueLocalDate(due)
        if (!d) return false
        var today = new Date(); today.setHours(0, 0, 0, 0)
        return d.getTime() < today.getTime()
    }

    function formatDue(due) {
        var d = dueLocalDate(due)
        if (!d) return ""
        var today = new Date(); today.setHours(0, 0, 0, 0)
        var diff = Math.round((d.getTime() - today.getTime()) / 86400000)
        if (diff < 0) return "Overdue · " + Qt.locale().toString(d, "MMM d")
        if (diff === 0) return "Today"
        if (diff === 1) return "Tomorrow"
        return Qt.locale().toString(d, "ddd, MMM d")
    }

    // Completion timestamp (RFC3339, has tz) → local midnight Date.
    function completedLocalDate(c) {
        if (!c) return null
        var d = new Date(c)
        if (isNaN(d.getTime())) return null
        return new Date(d.getFullYear(), d.getMonth(), d.getDate())
    }

    function formatCompleted(c) {
        if (!c) return ""
        var d = new Date(c)
        if (isNaN(d.getTime())) return ""
        return Qt.locale().toString(d, "MMM d") + " " + formatTime(d)
    }

    function _dayDiff(d) {
        var today = new Date(); today.setHours(0, 0, 0, 0)
        return Math.round((d.getTime() - today.getTime()) / 86400000)
    }

    // The day a task belongs to: completion date if done, else due date.
    function _refDate(t) {
        return t.status === "completed" ? completedLocalDate(t.completed) : dueLocalDate(t.due)
    }

    // ---- Task grouping (mirrors the agenda's day sections) ----
    function taskSection(t) {
        var d = _refDate(t)
        if (!d) return "No date"
        var diff = _dayDiff(d)
        if (t.status === "completed") {
            // Completed items are grouped by completion day, never as "Overdue".
            if (diff === 0) return "Today"
            if (diff === -1) return "Yesterday"
            return Qt.locale().toString(d, "dddd, MMM d")
        }
        if (diff < 0) return "Overdue"
        if (diff === 0) return "Today"
        if (diff === 1) return "Tomorrow"
        return Qt.locale().toString(d, "dddd, MMM d")
    }

    // Sort by reference day (asc, undated last); open before completed within a day.
    function processTasks(arr) {
        var copy = (arr || []).slice()
        copy.sort(function (a, b) {
            var ra = _refDate(a), rb = _refDate(b)
            if (!ra && rb) return 1
            if (ra && !rb) return -1
            if (ra && rb && ra.getTime() !== rb.getTime())
                return ra.getTime() - rb.getTime()
            var ac = a.status === "completed", bc = b.status === "completed"
            if (ac !== bc) return ac ? 1 : -1
            return 0
        })
        for (var i = 0; i < copy.length; i++)
            copy[i].sectionTitle = taskSection(copy[i])
        return copy
    }

    // ---- Toggle a task's completion (write-back, both directions) ----
    function setTaskStatus(listId, taskId, status) {
        if (!listId || !taskId || statusProcess.running) return
        var copy = tasks.slice()
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].id === taskId) {
                copy[i].status = status
                copy[i].completed = (status === "completed") ? new Date().toISOString() : null
                break
            }
        }
        tasks = processTasks(copy)   // optimistic regroup
        tasksUpdated()
        statusProcess.command = [authCmd, "--set-status", listId, taskId, status]
        statusProcess.running = true
    }

    function toggleTask(listId, taskId, currentStatus) {
        setTaskStatus(listId, taskId, currentStatus === "completed" ? "needsAction" : "completed")
    }

    Process {
        id: statusProcess
        running: false
        onExited: (code, status) => Qt.callLater(root.sync)
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text && text.trim().length > 0)
                    Logger.w("Waylandar", "set-status stderr: " + text.trim())
            }
        }
    }

    // ---- Habits: local date key + read/write helpers ----
    function _pad(n) { return (n < 10 ? "0" : "") + n }
    function dateKey(d) { return d.getFullYear() + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate()) }
    function keyToDate(key) {
        var p = ("" + key).split("-")
        if (p.length < 3) return new Date(NaN)
        var d = new Date(parseInt(p[0]), parseInt(p[1]) - 1, parseInt(p[2])); d.setHours(0, 0, 0, 0)
        return d
    }
    function _todayKey() { return dateKey(new Date()) }

    // ---- Read helpers (any day) ----
    function doneOn(id, key) { return (habitLog[key] || []).indexOf(id) !== -1 }
    function doneCountOn(key) {
        var arr = habitLog[key] || [], n = 0
        for (var i = 0; i < habitDefs.length; i++)
            if (arr.indexOf(habitDefs[i].id) !== -1) n++
        return n
    }
    function isHabitDone(id) { return doneOn(id, todayKey) }   // today convenience

    // Toggle a habit's completion on a given day and persist. Reassign the whole log
    // object (JsonAdapter only notifies on property assignment, not in-place mutation).
    function toggleHabitOn(id, key) {
        if (!key || !key.length) key = _todayKey()
        var log = {}
        for (var k in habitLog) log[k] = (habitLog[k] || []).slice()
        var arr = log[key] || []
        var i = arr.indexOf(id)
        if (i === -1) arr.push(id); else arr.splice(i, 1)
        if (arr.length > 0) log[key] = arr; else delete log[key]
        habitsAdapter.log = log
        habitsFile.writeAdapter()
        habitsUpdated()
    }
    function toggleHabit(id) { toggleHabitOn(id, todayKey) }   // today convenience

    // Consecutive-day streak ending on `key`. If that day isn't done yet, count back
    // from the day before so an unfinished current day doesn't read as a broken streak.
    function habitStreakOn(id, key) {
        var d = keyToDate(key)
        if (isNaN(d.getTime())) return 0
        if ((habitLog[key] || []).indexOf(id) === -1) d.setDate(d.getDate() - 1)
        var streak = 0
        while (true) {
            var arr = habitLog[dateKey(d)] || []
            if (arr.indexOf(id) !== -1) { streak++; d.setDate(d.getDate() - 1) }
            else break
        }
        return streak
    }
    function habitStreak(id) { return habitStreakOn(id, todayKey) }   // today convenience

    // ---- Habits persistence (vault JSON via Quickshell.Io) ----
    FileView {
        id: habitsFile
        path: root.habitsPath
        printErrors: false
        watchChanges: true            // pick up edits from skills / other machines
        onFileChanged: reload()

        adapter: JsonAdapter {
            id: habitsAdapter
            property var habits: [
                { "id": "language", "name": "Language Learning", "icon": "language" },
                { "id": "reading",  "name": "Reading",           "icon": "book-2" },
                { "id": "exercise", "name": "Exercise",          "icon": "barbell" },
                { "id": "eating",   "name": "Healthy Eating",    "icon": "salad" },
                { "id": "culto",    "name": "Culto Familiar",    "icon": "cross" }
            ]
            property var log: ({})    // { "YYYY-MM-DD": ["habitId", ...] }
        }

        onLoaded: { root.todayKey = root._todayKey(); root.habitsUpdated() }
        onLoadFailed: (error) => {
            // error === 2 → file doesn't exist yet; seed it from the defaults.
            root.todayKey = root._todayKey()
            if (error === 2) writeAdapter()
            root.habitsUpdated()
        }
    }

    // "Attending" = RSVP'd yes, or a personal block with no guests.
    function willAttend(ev) {
        var r = (ev && ev.rsvp) ? ev.rsvp : "none"
        return r === "accepted" || r === "none"
    }

    function nextEvent() {
        var now = new Date()
        for (var i = 0; i < calendarEvents.length; i++) {
            if (new Date(calendarEvents[i].start) > now)
                return calendarEvents[i]
        }
        return null
    }
}
