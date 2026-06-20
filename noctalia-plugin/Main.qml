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
    property var calendarEvents: []        // upcoming events, with .sectionTitle and .notified_for
    property bool isSyncing: false
    property string authError: ""
    property int minutesUntilSync: syncIntervalMinutes
    property var lastSync: null

    // ---- Settings (mirrored from pluginApi.pluginSettings) ----
    property int syncIntervalMinutes: pluginApi?.pluginSettings?.syncIntervalMinutes ?? 60
    property bool use12hourFormat: pluginApi?.pluginSettings?.use12hourFormat ?? false
    property bool notifyReminders: pluginApi?.pluginSettings?.notifyReminders ?? true

    signal eventsUpdated()

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
                notifyReminders: true
            }
            pluginApi.saveSettings()
        }
        syncIntervalMinutes = pluginApi.pluginSettings.syncIntervalMinutes ?? 60
        use12hourFormat = pluginApi.pluginSettings.use12hourFormat ?? false
        notifyReminders = pluginApi.pluginSettings.notifyReminders ?? true
        minutesUntilSync = syncIntervalMinutes
    }

    // Re-read settings when changed via the Settings UI
    function reloadSettings() {
        if (!pluginApi?.pluginSettings) return
        syncIntervalMinutes = pluginApi.pluginSettings.syncIntervalMinutes ?? 60
        use12hourFormat = pluginApi.pluginSettings.use12hourFormat ?? false
        notifyReminders = pluginApi.pluginSettings.notifyReminders ?? true
    }

    function sync() {
        if (fetchProcess.running) return
        minutesUntilSync = syncIntervalMinutes
        isSyncing = true
        fetchProcess.running = true
    }

    // ---- Backend fetch (Google Calendar via the waylandar-auth wrapper) ----
    Process {
        id: fetchProcess
        command: ["waylandar-auth", "--background"]
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
                        root.eventsUpdated()
                        return
                    }

                    authError = ""
                    lastSync = new Date()

                    var now = new Date()
                    var todayStr = now.toDateString()
                    var tomorrow = new Date(now)
                    tomorrow.setDate(tomorrow.getDate() + 1)
                    var tomorrowStr = tomorrow.toDateString()

                    var filtered = []
                    for (var i = 0; i < parsed.length; i++) {
                        var d = new Date(parsed[i].start)
                        // Backend returns the whole month; the agenda only shows upcoming.
                        if (d < now && parsed[i].end && new Date(parsed[i].end) < now)
                            continue

                        var dStr = d.toDateString()
                        if (dStr === todayStr)
                            parsed[i].sectionTitle = "Today"
                        else if (dStr === tomorrowStr)
                            parsed[i].sectionTitle = "Tomorrow"
                        else
                            parsed[i].sectionTitle = d.toLocaleDateString(Qt.locale(), "dddd, MMM d")

                        parsed[i].notified_for = []
                        filtered.push(parsed[i])
                    }
                    calendarEvents = filtered
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

    function nextEvent() {
        var now = new Date()
        for (var i = 0; i < calendarEvents.length; i++) {
            if (new Date(calendarEvents[i].start) > now)
                return calendarEvents[i]
        }
        return null
    }
}
