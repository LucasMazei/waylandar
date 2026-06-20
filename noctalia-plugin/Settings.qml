import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    property int syncIntervalMinutes: 60
    property bool use12hourFormat: false
    property bool notifyReminders: true
    property int completedTaskDays: 1
    property int eventDaysBack: 1

    spacing: Style.marginL

    Component.onCompleted: {
        if (pluginApi?.pluginSettings) {
            syncIntervalMinutes = pluginApi.pluginSettings.syncIntervalMinutes ?? 60
            use12hourFormat = pluginApi.pluginSettings.use12hourFormat ?? false
            notifyReminders = pluginApi.pluginSettings.notifyReminders ?? true
            completedTaskDays = pluginApi.pluginSettings.completedTaskDays ?? 1
            eventDaysBack = pluginApi.pluginSettings.eventDaysBack ?? 1
        }
    }

    NToggle {
        label: "12-hour clock"
        description: "Show event times as 1:30 PM instead of 13:30."
        checked: root.use12hourFormat
        onToggled: checked => root.use12hourFormat = checked
    }

    NToggle {
        label: "Reminder notifications"
        description: "Fire notify-send alerts based on each event's Google Calendar reminders."
        checked: root.notifyReminders
        onToggled: checked => root.notifyReminders = checked
    }

    NDivider {
        Layout.fillWidth: true
        Layout.topMargin: Style.marginM
        Layout.bottomMargin: Style.marginM
    }

    NComboBox {
        Layout.fillWidth: true
        label: "Sync interval"
        description: "How often to poll Google Calendar in the background."
        model: [
            { "key": "15", "name": "Every 15 minutes" },
            { "key": "30", "name": "Every 30 minutes" },
            { "key": "60", "name": "Every hour" },
            { "key": "120", "name": "Every 2 hours" }
        ]
        currentKey: String(root.syncIntervalMinutes)
        onSelected: key => root.syncIntervalMinutes = parseInt(key)
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Completed tasks shown (days)"
        description: "How many days back of completed tasks to show. 0 = today only, 1 = since yesterday."
        from: 0
        to: 30
        stepSize: 1
        value: root.completedTaskDays
        onValueChanged: if (value !== root.completedTaskDays) root.completedTaskDays = value
    }

    NSpinBox {
        Layout.fillWidth: true
        label: "Past events shown (days)"
        description: "How many days back of events to keep in the collapsible \"Earlier\" section. 0 = today only, 1 = since yesterday."
        from: 0
        to: 30
        stepSize: 1
        value: root.eventDaysBack
        onValueChanged: if (value !== root.eventDaysBack) root.eventDaysBack = value
    }

    function saveSettings() {
        if (!pluginApi) {
            Logger.e("Waylandar", "Cannot save settings: pluginApi is null")
            return
        }
        if (!pluginApi.pluginSettings)
            pluginApi.pluginSettings = {}
        pluginApi.pluginSettings.syncIntervalMinutes = syncIntervalMinutes
        pluginApi.pluginSettings.use12hourFormat = use12hourFormat
        pluginApi.pluginSettings.notifyReminders = notifyReminders
        pluginApi.pluginSettings.completedTaskDays = completedTaskDays
        pluginApi.pluginSettings.eventDaysBack = eventDaysBack
        pluginApi.saveSettings()

        if (pluginApi.mainInstance && pluginApi.mainInstance.reloadSettings)
            pluginApi.mainInstance.reloadSettings()
    }
}
