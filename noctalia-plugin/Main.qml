import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.System
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

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

    signal eventsUpdated()
    signal tasksUpdated()

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
        command: ["waylandar-auth", "--days-back", String(eventDaysBack), "--background"]
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
        command: ["waylandar-auth", "--tasks", "--completed-days", String(completedTaskDays), "--background"]
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
            if (notifyReminders) {
                var now = new Date()
                for (var i = 0; i < calendarEvents.length; i++) {
                    var ev = calendarEvents[i]
                    if (!ev.reminders) continue
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
        statusProcess.command = ["waylandar-auth", "--set-status", listId, taskId, status]
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

    function nextEvent() {
        var now = new Date()
        for (var i = 0; i < calendarEvents.length; i++) {
            if (new Date(calendarEvents[i].start) > now)
                return calendarEvents[i]
        }
        return null
    }
}
