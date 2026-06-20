import QtQuick
import qs.Commons
import qs.Widgets

Rectangle {
    id: card

    property var taskData: null
    property var pluginCore: null
    property bool isExpanded: false
    signal toggleExpand()

    readonly property bool hasNotes: taskData && taskData.notes && taskData.notes.length > 0
    readonly property bool completed: taskData && taskData.status === "completed"
    readonly property bool overdue: !completed && pluginCore && taskData ? pluginCore.dueIsOverdue(taskData.due) : false

    height: (isExpanded && hasNotes) ? 55 + notesText.height + Style.marginM : 55
    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

    color: cardMouseArea.containsMouse ? Color.mSurfaceVariant : Color.mSurface
    radius: Style.radiusM
    clip: true
    opacity: completed ? 0.6 : 1.0
    Behavior on color { ColorAnimation { duration: Style.animationFast } }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: hasNotes ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (hasNotes) card.toggleExpand()
    }

    Row {
        id: topRow
        width: parent.width
        height: 55
        anchors.top: parent.top
        spacing: Style.marginM

        Item { width: Style.marginXS; height: 1 }

        // Checkbox — click to complete (read-only once completed)
        Item {
            width: 22; height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 18; height: 18
                radius: 9
                color: card.completed ? Color.mPrimary : "transparent"
                border.width: 2
                border.color: card.completed ? Color.mPrimary
                    : (card.overdue ? Color.mError : Color.mPrimary)

                NIcon {
                    anchors.centerIn: parent
                    visible: card.completed
                    icon: "check"
                    pointSize: Style.fontSizeXS
                    color: Color.mOnPrimary
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (card.pluginCore && card.taskData)
                        card.pluginCore.toggleTask(card.taskData.listId, card.taskData.id, card.taskData.status)
                }
            }
        }

        Column {
            spacing: Style.marginXXS
            width: parent.width - 60
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: taskData ? taskData.title : ""
                font.pixelSize: Style.fontSizeM
                font.weight: Style.fontWeightMedium
                font.strikeout: card.completed
                color: Color.mOnSurface
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                visible: text.length > 0
                text: {
                    if (!taskData) return ""
                    var list = taskData.list || ""
                    if (card.completed && card.pluginCore) {
                        var done = card.pluginCore.formatCompleted(taskData.completed)
                        return done ? "✓ " + done + "  ·  " + list : list
                    }
                    return list
                }
                font.pixelSize: Style.fontSizeXS
                color: Color.mOnSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
            }
        }
    }

    Text {
        id: notesText
        width: parent.width - 60
        anchors.top: topRow.bottom
        anchors.left: parent.left
        anchors.leftMargin: 40
        text: hasNotes ? taskData.notes : ""
        font.pixelSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        wrapMode: Text.WordWrap
        opacity: isExpanded ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }
}
