import QtQuick
import qs.Commons

Rectangle {
    id: card

    property var eventData: null
    property var pluginCore: null
    property bool isExpanded: false
    signal toggleExpand()

    readonly property bool hasMeet: eventData && eventData.meetLink && eventData.meetLink.length > 0

    height: isExpanded ? Math.max(110, 80 + expandedDetails.height) : 55
    Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }

    color: cardMouseArea.containsMouse ? Color.mSurfaceVariant : Color.mSurface
    radius: Style.radiusM
    clip: true
    Behavior on color { ColorAnimation { duration: Style.animationFast } }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.toggleExpand()
    }

    Row {
        id: topRow
        width: parent.width
        height: 55
        anchors.top: parent.top
        spacing: Style.marginM

        Item { width: Style.marginXS; height: 1 }

        Rectangle {
            width: 4
            height: 34
            anchors.verticalCenter: parent.verticalCenter
            radius: 2
            color: Color.mTertiary
        }

        Column {
            spacing: Style.marginXXS
            width: parent.width - 45 - (card.hasMeet ? 66 : 0)
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: eventData ? eventData.title : ""
                font.pixelSize: Style.fontSizeM
                font.weight: Style.fontWeightBold
                color: Color.mOnSurface
                elide: Text.ElideRight
                width: parent.width
            }

            Text {
                text: {
                    if (!eventData) return ""
                    var d = new Date(eventData.start)
                    var t = card.pluginCore ? card.pluginCore.formatTime(d)
                        : Qt.locale().toString(d, "HH:mm")
                    return Qt.locale().toString(d, "ddd MMM d") + " · " + t
                }
                font.pixelSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
            }
        }
    }

    // Join the meeting (visible only when the event has a video link)
    Rectangle {
        id: joinButton
        visible: card.hasMeet
        width: 56
        height: 28
        radius: Style.radiusS
        anchors.right: parent.right
        anchors.rightMargin: Style.marginM
        y: 13   // vertically centered in the 55px top row
        color: joinMouseArea.containsMouse ? Color.mSecondary : Color.mPrimary
        Behavior on color { ColorAnimation { duration: Style.animationFast } }

        Text {
            anchors.centerIn: parent
            text: "Join"
            font.pixelSize: Style.fontSizeS
            font.weight: Style.fontWeightBold
            color: Color.mOnPrimary
        }

        MouseArea {
            id: joinMouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (card.hasMeet)
                    Qt.openUrlExternally(card.eventData.meetLink)
            }
        }
    }

    Item {
        id: expandedDetails
        width: parent.width - 45
        anchors.top: topRow.bottom
        anchors.left: parent.left
        anchors.leftMargin: 35

        opacity: isExpanded ? 1.0 : 0.0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }

        height: detailCol.height + Style.marginM

        Column {
            id: detailCol
            width: parent.width
            spacing: Style.marginM

            Text {
                text: eventData && eventData.description ? eventData.description : "No additional description."
                font.pixelSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Rectangle {
                width: 150
                height: 32
                radius: Style.radiusS
                visible: eventData && eventData.link
                color: linkMouseArea.containsMouse ? Color.mSecondary : Color.mPrimary
                Behavior on color { ColorAnimation { duration: Style.animationFast } }

                Text {
                    anchors.centerIn: parent
                    text: "Open in Browser"
                    font.pixelSize: Style.fontSizeS
                    font.weight: Style.fontWeightBold
                    color: Color.mOnPrimary
                }

                MouseArea {
                    id: linkMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (eventData && eventData.link)
                            Qt.openUrlExternally(eventData.link)
                    }
                }
            }
        }
    }
}
