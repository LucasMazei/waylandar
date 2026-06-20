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

    property int expandedIndex: -1

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
                    text: "Upcoming Schedule"
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

            NDivider { Layout.fillWidth: true }

            // ---- Agenda list ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Error state
                Flickable {
                    anchors.fill: parent
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

                // Empty state
                NText {
                    anchors.centerIn: parent
                    visible: panelReady && mainInstance.authError.length === 0
                        && mainInstance.calendarEvents.length === 0 && !mainInstance.isSyncing
                    text: "Your schedule is clear!"
                    font.pixelSize: Style.fontSizeM
                    font.italic: true
                    color: Color.mOnSurfaceVariant
                }

                // Event list
                ListView {
                    id: list
                    anchors.fill: parent
                    visible: panelReady && mainInstance.authError.length === 0
                    model: panelReady ? mainInstance.calendarEvents : []
                    spacing: Style.marginS
                    clip: true

                    opacity: (panelReady && mainInstance.isSyncing) ? 0.3 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 250 } }

                    delegate: Components.EventCard {
                        width: ListView.view.width
                        eventData: modelData
                        pluginCore: root.mainInstance
                        isExpanded: root.expandedIndex === index
                        onToggleExpand: root.expandedIndex = (root.expandedIndex === index ? -1 : index)
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

                // Loading spinner
                NBusyIndicator {
                    anchors.centerIn: parent
                    running: panelReady && mainInstance.isSyncing
                    visible: running
                }
            }
        }
    }
}
