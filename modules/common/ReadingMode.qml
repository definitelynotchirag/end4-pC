pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Hyprland reading mode (~/.config/hypr/custom/reading_mode.lua) writes "dark"
// or "light" to ~/.cache/reading_mode while on. While it is on the shell
// overrides a few bar/dock options without touching the saved config.
Singleton {
    id: root

    // Polled: the file comes and goes, and a watch can't see it appear.
    property bool active: false
    readonly property bool barAutoHide: Config.options.bar.autoHide.enable || active
    readonly property int barCornerStyle: active ? 0 : Config.options.bar.cornerStyle // 0 = Hug

    FileView {
        id: stateFile
        path: `${Directories.home}/.cache/reading_mode`
        printErrors: false
        onLoaded: root.active = text().trim().length > 0
        onLoadFailed: root.active = false
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: stateFile.reload()
    }
}
