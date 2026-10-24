import qs
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Voxtype dictation pill. Drops out of the top bar while Voxtype is recording or
// transcribing, in the bar's own glass (WindowGlass + colUiBackground), with
// live mic bars from cava. Driven by AltGr through ~/.local/bin/altgr-dictation:
// a quick tap toggles, a hold is push-to-talk.
Scope {
    id: root

    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    property string voxState: "idle"      // idle | recording | transcribing
    property string keyState: ""          // altgr-dictation.state first word
    readonly property bool active: voxState === "recording" || voxState === "transcribing"
    readonly property bool recording: voxState === "recording"
    readonly property bool toggleMode: keyState === "toggled"
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    readonly property int barCount: 16
    property var levels: flatLevels()
    property real lastLevelMs: 0

    function flatLevels() {
        let a = [];
        for (let i = 0; i < barCount; i++) a.push(0);
        return a;
    }

    FileView {
        id: stateFile
        path: root.runtimeDir + "/voxtype/state"
        onLoaded: root.voxState = text().trim() || "idle"
        onLoadFailed: root.voxState = "idle"
    }
    FileView {
        id: keyFile
        path: root.runtimeDir + "/altgr-dictation.state"
        onLoaded: root.keyState = (text().trim().split(" ")[0]) || ""
        onLoadFailed: root.keyState = ""
    }
    // Voxtype rewrites its state file by rename, which an inotify watch on the
    // old inode misses; polling two tiny files is cheaper than being wrong.
    Timer {
        interval: 120
        running: true
        repeat: true
        onTriggered: {
            stateFile.reload();
            keyFile.reload();
        }
    }

    // Mic spectrum: cava on the default input while recording.
    Process {
        id: cava
        running: root.recording
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1 || exit 0; src=$(pactl get-default-source 2>/dev/null); cfg=\"${XDG_RUNTIME_DIR:-/tmp}/end4-voxtype-cava.conf\"; printf '%s\\n' '[general]' 'framerate = 60' 'bars = " + root.barCount + "' '' '[input]' 'method = pulse' \"source = $src\" '' '[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' 'mono_option = average' '' '[smoothing]' 'noise_reduction = 55' > \"$cfg\"; exec cava -p \"$cfg\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                const parts = line.trim().split(/[;\s]+/);
                if (parts.length < root.barCount) return;
                let a = [];
                for (let i = 0; i < root.barCount; i++) {
                    const f = Math.max(0, Math.min(1, (parseInt(parts[i]) || 0) / 100));
                    a.push(f < 0.05 ? 0 : f);
                }
                root.levels = a;
                root.lastLevelMs = Date.now();
            }
        }
    }
    // cava goes quiet on silence; settle the bars instead of freezing a peak.
    Timer {
        interval: 120
        running: root.recording
        repeat: true
        onTriggered: if (Date.now() - root.lastLevelMs > 200) root.levels = root.flatLevels()
    }
    onRecordingChanged: if (!recording) levels = flatLevels()

    PanelWindow {
        id: win
        screen: root.focusedScreen
        visible: root.active || hideAnim.running
        color: "transparent"

        WlrLayershell.namespace: "quickshell:voxtype"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        anchors.top: true
        margins.top: Appearance.sizes.barHeight
        mask: Region { item: card }

        implicitWidth: card.width + Appearance.sizes.elevationMargin * 2
        implicitHeight: card.height + Appearance.sizes.elevationMargin * 2 + 12

        StyledRectangularShadow {
            target: card
            opacity: card.opacity
        }

        Rectangle {
            id: card
            x: Appearance.sizes.elevationMargin
            y: Appearance.sizes.elevationMargin
            width: 330
            height: 56
            radius: Appearance.rounding.full
            // Same as the bar islands (BarContent.qml): with glass on, the card is
            // transparent and WindowGlass draws the tint over Hyprland's blur.
            property color fill: Appearance.colors.colUiBackground
            color: Config.options.background.widgets.glass.enable && fill.a > 0 ? "transparent" : fill
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            opacity: 0

            WindowGlass {
                anchors.fill: parent
                glassEnabled: (parent?.fill.a ?? 0) > 0
                cardRadius: parent?.radius ?? 0
                tint: parent?.fill ?? "transparent"
            }

            // Grows down out of the bar: scale from the top edge plus a short drop.
            transform: [
                Scale {
                    id: cardScale
                    origin.x: card.width / 2
                    origin.y: 0
                    xScale: 0.85
                    yScale: 0.3
                },
                Translate {
                    id: cardDrop
                    y: -18
                }
            ]

            RowLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 8
                anchors.rightMargin: 18
                spacing: 12
                opacity: 0

                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: height
                    radius: height / 2
                    color: root.recording ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    // Breathes with the voice while recording.
                    scale: root.recording ? 1 + 0.08 * Math.max(...root.levels) : 1
                    Behavior on scale { NumberAnimation { duration: 90 } }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.recording ? "mic" : "graphic_eq"
                        iconSize: 22
                        fill: 1
                        color: root.recording ? Appearance.colors.colOnPrimary : Appearance.colors.colOnSecondaryContainer
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Row {
                        anchors.centerIn: parent
                        spacing: 3
                        Repeater {
                            model: root.barCount
                            Rectangle {
                                required property int index
                                // Mirror the spectrum so it peaks in the middle.
                                readonly property real level: root.levels[index < root.barCount / 2 ? root.barCount / 2 - 1 - index : index - root.barCount / 2] ?? 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4
                                radius: 2
                                height: root.recording ? 4 + level * 30 : 4
                                color: Appearance.colors.colPrimary
                                opacity: root.recording ? 0.55 + level * 0.45 : 0.35
                                Behavior on height { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }
                            }
                        }
                    }

                    // Transcribing: a soft sweep across the resting bars.
                    Rectangle {
                        visible: root.voxState === "transcribing"
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 4
                        radius: 2
                        color: Appearance.colors.colPrimary
                        SequentialAnimation on x {
                            running: root.voxState === "transcribing"
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: Math.max(0, parent.width - 40); duration: 650; easing.type: Easing.InOutSine }
                            NumberAnimation { from: Math.max(0, parent.width - 40); to: 0; duration: 650; easing.type: Easing.InOutSine }
                        }
                    }
                }

                ColumnLayout {
                    spacing: -2
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: root.recording ? "Listening" : "Transcribing"
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignRight
                        text: !root.recording ? "Typing soon" : root.toggleMode ? "Tap AltGr to finish" : "Release to finish"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    onActiveChanged: {
        if (active) {
            hideAnim.stop();
            showAnim.restart();
        } else {
            showAnim.stop();
            hideAnim.restart();
        }
    }

    ParallelAnimation {
        id: showAnim
        NumberAnimation {
            target: cardScale; property: "yScale"; to: 1
            duration: 500
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: cardScale; property: "xScale"; to: 1
            duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial
        }
        NumberAnimation {
            target: cardDrop; property: "y"; to: 0
            duration: Appearance.animationCurves.expressiveDefaultSpatialDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
        NumberAnimation {
            target: card; property: "opacity"; to: 1
            duration: Appearance.animationCurves.expressiveEffectsDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation {
                target: content; property: "opacity"; to: 1
                duration: Appearance.animationCurves.expressiveEffectsDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }

    ParallelAnimation {
        id: hideAnim
        NumberAnimation {
            target: cardScale; property: "yScale"; to: 0.3
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: cardScale; property: "xScale"; to: 0.85
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: cardDrop; property: "y"; to: -18
            duration: 220
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation {
            target: card; property: "opacity"; to: 0
            duration: 200
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 120 }
    }
}
