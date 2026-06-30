import QtQuick
import qs.Commons
import qs.Widgets

// A full circular progress ring with an icon centered inside. Fills clockwise
// from the top; reaches a full ring (and a "complete" accent) at ratio === 1.
Item {
    id: root

    property real ratio: 0                 // 0..1
    property string icon: "calendar-month"
    property real diameter: 46 * Style.uiScaleRatio
    property real lineWidth: 4 * Style.uiScaleRatio
    readonly property bool complete: ratio >= 0.999
    readonly property color fillColor: complete ? Color.mTertiary : Color.mPrimary

    implicitWidth: diameter
    implicitHeight: diameter

    property real animatedRatio: ratio
    Behavior on animatedRatio {
        enabled: !Settings.data.general.animationDisabled
        NumberAnimation { duration: Style.animationNormal; easing.type: Easing.OutCubic }
    }
    onAnimatedRatioChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        renderTarget: Canvas.FramebufferObject
        layer.enabled: true
        layer.smooth: true

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height
            const cx = w / 2, cy = h / 2
            const r = Math.min(w, h) / 2 - root.lineWidth / 2 - 1

            ctx.reset()
            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"

            // Track
            ctx.strokeStyle = Color.mOutline
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, 2 * Math.PI)
            ctx.stroke()

            // Value arc (clockwise from top)
            const rr = Math.max(0, Math.min(1, root.animatedRatio))
            if (rr > 0.005) {
                const start = -Math.PI / 2
                ctx.strokeStyle = root.fillColor
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + 2 * Math.PI * rr)
                ctx.stroke()
            }
        }
    }

    NIcon {
        anchors.centerIn: parent
        icon: root.icon
        color: root.fillColor
        pointSize: Style.fontSizeL
    }
}
