import QtQuick
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Modules.Bar.Extras
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null
    readonly property QtObject pluginCore: pluginApi?.mainInstance

    property ShellScreen screen
    property string widgetId: ""
    property string section: ""
    property int sectionWidgetIndex: -1
    property int sectionWidgetsCount: 0

    property string tooltipContent: ""

    function updateTooltip() {
        if (!pluginCore) {
            tooltipContent = ""
            return
        }
        if (pluginCore.authError && pluginCore.authError.length > 0) {
            tooltipContent = pluginCore.authError
            return
        }
        var ev = pluginCore.nextEvent()
        if (ev) {
            tooltipContent = "Next: " + ev.title + "\n"
                + pluginCore.formatTime(new Date(ev.start))
                + "  ·  " + ev.sectionTitle
        } else {
            tooltipContent = "Your schedule is clear!"
        }
    }

    Connections {
        target: pluginCore
        function onEventsUpdated() { root.updateTooltip() }
    }

    Component.onCompleted: updateTooltip()

    implicitWidth: pill.width
    implicitHeight: pill.height

    BarPill {
        id: pill
        screen: root.screen
        oppositeDirection: BarService.getPillDirection(root)
        forceClose: true

        icon: "calendar-month"
        tooltipText: tooltipContent

        onClicked: root.pluginApi?.openPanel(root.screen)
        onRightClicked: PanelService.showContextMenu(contextMenu, pill, root.screen)
    }

    NPopupContextMenu {
        id: contextMenu
        model: [
            { "label": "Sync now", "action": "sync", "icon": "refresh", "enabled": true },
            { "label": "Settings", "action": "widget-settings", "icon": "settings", "enabled": true }
        ]
        onTriggered: action => {
            contextMenu.close()
            PanelService.closeContextMenu(root.screen)
            if (action === "sync")
                root.pluginCore?.sync()
            else if (action === "widget-settings")
                BarService.openPluginSettings(screen, pluginApi.manifest)
        }
    }
}
