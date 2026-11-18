import QtQuick
import IslandBackend

Item {
    id: root

    property bool isPlaying: false
    property bool active: true
    property real barWidth: 4
    property real barSpacing: 4
    property real barRadius: barWidth / 2
    property real minHeight: 6
    property real maxHeight: 22
    property color activeColor: StyleTokens.accent
    property color pausedColor: StyleTokens.accentSoft

    readonly property bool running: root.active && root.isPlaying

    implicitWidth: 5 * barWidth + 4 * barSpacing
    implicitHeight: maxHeight
    width: implicitWidth
    height: implicitHeight

    readonly property var barConfigs: [
        {
            k1: 0.85, d1: 150,
            k2: 0.28, d2: 130,
            k3: 0.68, d3: 160,
            k4: 0.22, d4: 180,
            paused: 0.35
        },
        {
            k1: 0.38, d1: 120,
            k2: 0.95, d2: 170,
            k3: 0.25, d3: 140,
            k4: 0.78, d4: 160,
            paused: 0.60
        },
        {
            k1: 1.00, d1: 190,
            k2: 0.45, d2: 160,
            k3: 0.90, d3: 180,
            k4: 0.35, d4: 210,
            paused: 0.85
        },
        {
            k1: 0.28, d1: 140,
            k2: 0.85, d2: 170,
            k3: 0.38, d3: 130,
            k4: 0.92, d4: 160,
            paused: 0.60
        },
        {
            k1: 0.72, d1: 160,
            k2: 0.20, d2: 130,
            k3: 0.58, d3: 150,
            k4: 0.28, d4: 180,
            paused: 0.35
        }
    ]

    Row {
        anchors.centerIn: parent
        spacing: root.barSpacing

        Repeater {
            model: root.barConfigs

            Rectangle {
                id: barRect
                required property int index
                required property var modelData

                readonly property real targetK1: modelData.k1
                readonly property real targetK2: modelData.k2
                readonly property real targetK3: modelData.k3
                readonly property real targetK4: modelData.k4
                readonly property int durD1: modelData.d1
                readonly property int durD2: modelData.d2
                readonly property int durD3: modelData.d3
                readonly property int durD4: modelData.d4
                readonly property real pausedLevel: modelData.paused

                width: root.barWidth
                radius: root.barRadius
                anchors.verticalCenter: parent.verticalCenter

                color: root.isPlaying ? root.activeColor : root.pausedColor

                Behavior on color {
                    ColorAnimation { duration: 180; easing.type: Easing.InOutQuad }
                }

                property real dynamicLevel: pausedLevel

                height: Math.round(root.minHeight + (root.maxHeight - root.minHeight) * (root.isPlaying ? dynamicLevel : pausedLevel))

                Behavior on height {
                    enabled: !root.running
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }

                SequentialAnimation {
                    running: root.running
                    loops: Animation.Infinite

                    NumberAnimation {
                        target: barRect
                        property: "dynamicLevel"
                        to: barRect.targetK1
                        duration: barRect.durD1
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: barRect
                        property: "dynamicLevel"
                        to: barRect.targetK2
                        duration: barRect.durD2
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: barRect
                        property: "dynamicLevel"
                        to: barRect.targetK3
                        duration: barRect.durD3
                        easing.type: Easing.InOutQuad
                    }
                    NumberAnimation {
                        target: barRect
                        property: "dynamicLevel"
                        to: barRect.targetK4
                        duration: barRect.durD4
                        easing.type: Easing.InOutQuad
                    }
                }
            }
        }
    }
}
