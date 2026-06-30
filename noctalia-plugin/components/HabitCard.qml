import QtQuick
import qs.Commons
import qs.Widgets

Rectangle {
    id: card

    property var habitData: null      // { id, name, icon }
    property var pluginCore: null

    readonly property bool done: pluginCore && habitData ? pluginCore.isHabitDone(habitData.id) : false
    readonly property int streak: pluginCore && habitData ? pluginCore.habitStreak(habitData.id) : 0

    height: 52
    radius: Style.radiusM
    color: cardMouseArea.containsMouse ? Color.mSurfaceVariant : Color.mSurface
    Behavior on color { ColorAnimation { duration: Style.animationFast } }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (card.pluginCore && card.habitData) card.pluginCore.toggleHabit(card.habitData.id)
    }

    Row {
        anchors.fill: parent
        anchors.leftMargin: Style.marginM
        anchors.rightMargin: Style.marginM
        spacing: Style.marginM

        // Circular check toggle (mirrors TaskCard)
        Item {
            width: 22; height: 22
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.centerIn: parent
                width: 18; height: 18
                radius: 9
                color: card.done ? Color.mPrimary : "transparent"
                border.width: 2
                border.color: Color.mPrimary
                Behavior on color { ColorAnimation { duration: Style.animationFast } }

                NIcon {
                    anchors.centerIn: parent
                    visible: card.done
                    icon: "check"
                    pointSize: Style.fontSizeS
                    color: Color.mOnPrimary
                }
            }
        }

        // Habit icon
        NIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: card.habitData ? (card.habitData.icon || "circle") : "circle"
            pointSize: Style.fontSizeL
            color: card.done ? Color.mOnSurfaceVariant : Color.mOnSurface
        }

        // Name
        NText {
            anchors.verticalCenter: parent.verticalCenter
            width: card.width - 22 - Style.fontSizeL - streakRow.width - Style.marginM * 5
            text: card.habitData ? card.habitData.name : ""
            font.pixelSize: Style.fontSizeM
            font.strikeout: card.done
            color: card.done ? Color.mOnSurfaceVariant : Color.mOnSurface
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Streak badge (right-aligned)
    Row {
        id: streakRow
        anchors.right: parent.right
        anchors.rightMargin: Style.marginM
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.marginXS
        visible: card.streak > 0

        NIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: "flame"
            pointSize: Style.fontSizeS
            color: Color.mPrimary
        }
        NText {
            anchors.verticalCenter: parent.verticalCenter
            text: card.streak
            font.pixelSize: Style.fontSizeS
            font.weight: Style.fontWeightBold
            color: Color.mPrimary
        }
    }
}
