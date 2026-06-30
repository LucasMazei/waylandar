import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets
import "components" as Components

Item {
    id: root

    property var pluginApi: null
    readonly property var mainInstance: pluginApi?.mainInstance
    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    readonly property bool panelReady: pluginApi !== null && mainInstance !== null && mainInstance !== undefined

    property real contentPreferredWidth: 420 * Style.uiScaleRatio
    property real contentPreferredHeight: 520 * Style.uiScaleRatio

    anchors.fill: parent

    property int expandedEventIndex: -1
    property int expandedPastIndex: -1
    property int expandedTaskIndex: -1
    property bool showPastEvents: false

    // ---- Per-tab search ----
    property string eventQuery: ""
    property string taskQuery: ""

    function _matches(haystack, q) {
        if (!q || q.length === 0) return true
        if (!haystack) return false
        return ("" + haystack).toLowerCase().indexOf(q.toLowerCase()) !== -1
    }

    function filterEvents(list, q) {
        if (!q || q.length === 0) return list || []
        var out = []
        for (var i = 0; i < (list ? list.length : 0); i++) {
            var e = list[i]
            if (_matches(e.title, q) || _matches(e.description, q) || _matches(e.location, q))
                out.push(e)
        }
        return out
    }

    function filterTasks(list, q) {
        if (!q || q.length === 0) return list || []
        var out = []
        for (var i = 0; i < (list ? list.length : 0); i++) {
            var t = list[i]
            if (_matches(t.title, q) || _matches(t.notes, q) || _matches(t.list, q))
                out.push(t)
        }
        return out
    }

    readonly property var filteredUpcoming: filterEvents(panelReady ? mainInstance.upcomingEvents : [], eventQuery)
    readonly property var filteredPast: filterEvents(panelReady ? mainInstance.pastEvents : [], eventQuery)
    readonly property var filteredTasks: filterTasks(panelReady ? mainInstance.tasks : [], taskQuery)

    Item {
        id: panelContainer
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginM

            // ---- Header ----
            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                    text: "Waylandar"
                    font.pixelSize: Style.fontSizeL
                    font.weight: Style.fontWeightBold
                    color: Color.mOnSurface
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                NText {
                    visible: panelReady && !mainInstance.isSyncing
                    text: panelReady ? "Syncs in " + mainInstance.minutesUntilSync + "m" : ""
                    font.pixelSize: Style.fontSizeXS
                    font.italic: true
                    color: Color.mOnSurfaceVariant
                }

                NIconButton {
                    icon: "refresh"
                    tooltipText: "Sync now"
                    enabled: panelReady && !mainInstance.isSyncing
                    onClicked: mainInstance?.sync()
                }
            }

            // ---- Tabs ----
            NTabBar {
                id: tabBar
                Layout.fillWidth: true
                distributeEvenly: true

                NTabButton {
                    text: "Events"
                    icon: "calendar-month"
                    tabIndex: 0
                    checked: tabBar.currentIndex === 0
                }
                NTabButton {
                    text: "Tasks"
                    icon: "check-circle"
                    tabIndex: 1
                    checked: tabBar.currentIndex === 1
                }
            }

            NDivider { Layout.fillWidth: true }

            // ---- Auth error (shared) ----
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panelReady && mainInstance.authError.length > 0
                contentWidth: width
                contentHeight: errorText.implicitHeight
                clip: true
                NText {
                    id: errorText
                    width: parent.width
                    text: panelReady ? mainInstance.authError : ""
                    font.pixelSize: Style.fontSizeS
                    color: Color.mError
                    wrapMode: Text.WrapAnywhere
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // ---- Tab content ----
            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: panelReady && mainInstance.authError.length === 0
                currentIndex: tabBar.currentIndex

                // --- Events tab ---
                ColumnLayout {
                    spacing: Style.marginS

                    NTextInput {
                        Layout.fillWidth: true
                        inputIconName: "search"
                        placeholderText: "Search events…"
                        onTextChanged: root.eventQuery = text
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        NText {
                            anchors.centerIn: parent
                            visible: panelReady && mainInstance.upcomingEvents.length === 0
                                && mainInstance.pastEvents.length === 0 && !mainInstance.isSyncing
                            text: "Your schedule is clear!"
                            font.pixelSize: Style.fontSizeM
                            font.italic: true
                            color: Color.mOnSurfaceVariant
                        }

                        NText {
                            anchors.centerIn: parent
                            visible: panelReady && root.eventQuery.length > 0
                                && root.filteredUpcoming.length === 0 && root.filteredPast.length === 0
                                && (mainInstance.upcomingEvents.length > 0 || mainInstance.pastEvents.length > 0)
                            text: "No events match \"" + root.eventQuery + "\""
                            font.pixelSize: Style.fontSizeM
                            font.italic: true
                            color: Color.mOnSurfaceVariant
                            wrapMode: Text.WrapAnywhere
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width - Style.marginL * 2
                        }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Style.marginS
                        opacity: (panelReady && mainInstance.isSyncing) ? 0.3 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        // Collapsible "Earlier" — past / ongoing events, de-emphasised
                        Rectangle {
                            Layout.fillWidth: true
                            visible: panelReady && root.filteredPast.length > 0
                            implicitHeight: 30
                            radius: Style.radiusS
                            color: earlierMouse.containsMouse ? Color.mSurfaceVariant : Color.mSurface
                            Behavior on color { ColorAnimation { duration: Style.animationFast } }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: Style.marginS
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.marginXS
                                NText {
                                    text: (root.showPastEvents || root.eventQuery.length > 0) ? "▾" : "▸"
                                    font.pixelSize: Style.fontSizeS
                                    color: Color.mOnSurfaceVariant
                                }
                                NText {
                                    text: panelReady ? "Earlier (" + root.filteredPast.length + ")" : ""
                                    font.pixelSize: Style.fontSizeS
                                    font.weight: Style.fontWeightBold
                                    color: Color.mOnSurfaceVariant
                                }
                            }
                            MouseArea {
                                id: earlierMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showPastEvents = !root.showPastEvents
                            }
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: visible ? Math.min(contentHeight, 170) : 0
                            visible: (root.showPastEvents || root.eventQuery.length > 0) && panelReady && root.filteredPast.length > 0
                            model: visible ? root.filteredPast : []
                            spacing: Style.marginS
                            clip: true
                            opacity: 0.55

                            delegate: Components.EventCard {
                                width: ListView.view.width
                                eventData: modelData
                                pluginCore: root.mainInstance
                                isExpanded: root.expandedPastIndex === index
                                onToggleExpand: root.expandedPastIndex = (root.expandedPastIndex === index ? -1 : index)
                            }
                        }

                        NDivider {
                            Layout.fillWidth: true
                            visible: (root.showPastEvents || root.eventQuery.length > 0) && panelReady && root.filteredPast.length > 0
                        }

                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            model: root.filteredUpcoming
                            spacing: Style.marginS
                            clip: true

                            delegate: Components.EventCard {
                                width: ListView.view.width
                                eventData: modelData
                                pluginCore: root.mainInstance
                                isExpanded: root.expandedEventIndex === index
                                onToggleExpand: root.expandedEventIndex = (root.expandedEventIndex === index ? -1 : index)
                            }

                            section.property: "sectionTitle"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                width: ListView.view.width
                                height: 32
                                NText {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: Style.marginXS
                                    text: section
                                    font.pixelSize: Style.fontSizeS
                                    font.weight: Style.fontWeightBold
                                    color: Color.mPrimary
                                }
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: 1
                                    color: Color.mOutline
                                }
                            }
                        }
                    }
                    }
                }

                // --- Tasks tab ---
                ColumnLayout {
                    spacing: Style.marginS

                    NTextInput {
                        Layout.fillWidth: true
                        inputIconName: "search"
                        placeholderText: "Search tasks…"
                        onTextChanged: root.taskQuery = text
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                    NText {
                        anchors.centerIn: parent
                        visible: panelReady && mainInstance.tasks.length === 0 && !mainInstance.isSyncing
                        text: "No open tasks. Nice."
                        font.pixelSize: Style.fontSizeM
                        font.italic: true
                        color: Color.mOnSurfaceVariant
                    }

                    NText {
                        anchors.centerIn: parent
                        visible: panelReady && root.taskQuery.length > 0
                            && root.filteredTasks.length === 0 && mainInstance.tasks.length > 0
                        text: "No tasks match \"" + root.taskQuery + "\""
                        font.pixelSize: Style.fontSizeM
                        font.italic: true
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.WrapAnywhere
                        horizontalAlignment: Text.AlignHCenter
                        width: parent.width - Style.marginL * 2
                    }

                    ListView {
                        anchors.fill: parent
                        model: root.filteredTasks
                        spacing: Style.marginS
                        clip: true
                        opacity: (panelReady && mainInstance.isSyncing) ? 0.3 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 250 } }

                        delegate: Components.TaskCard {
                            width: ListView.view.width
                            taskData: modelData
                            pluginCore: root.mainInstance
                            isExpanded: root.expandedTaskIndex === index
                            onToggleExpand: root.expandedTaskIndex = (root.expandedTaskIndex === index ? -1 : index)
                        }

                        section.property: "sectionTitle"
                        section.criteria: ViewSection.FullString
                        section.delegate: Item {
                            width: ListView.view.width
                            height: 32
                            NText {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Style.marginXS
                                text: section
                                font.pixelSize: Style.fontSizeS
                                font.weight: Style.fontWeightBold
                                color: section === "Overdue" ? Color.mError
                                    : section === "Completed" ? Color.mOnSurfaceVariant
                                    : Color.mPrimary
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: Color.mOutline
                            }
                        }
                    }
                    }
                }
            }
        }

        NBusyIndicator {
            anchors.centerIn: parent
            running: panelReady && mainInstance.isSyncing
                && mainInstance.calendarEvents.length === 0 && mainInstance.tasks.length === 0
            visible: running
        }
    }
}
