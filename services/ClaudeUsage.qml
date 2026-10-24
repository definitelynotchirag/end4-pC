pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var sessions: []
    property int tokens: 0
    property int estimateResetsAt: 0
    // live: real limits from Anthropic; otherwise the local token estimate
    property bool live: false
    property real sessionPercent: 0
    property int sessionResetsAt: 0
    property real weekPercent: 0
    property int weekResetsAt: 0
    property real lastUpdated: 0
    readonly property bool refreshing: usageProc.running
    readonly property int tokenLimit: Config.options.bar.aiUsage.tokenLimit
    readonly property real estimate: root.tokenLimit > 0 ? Math.min(root.tokens / root.tokenLimit, 1) : 0
    readonly property real percentage: root.live ? Math.min(root.sessionPercent / 100, 1) : root.estimate
    readonly property real weekPercentage: Math.min(root.weekPercent / 100, 1)
    readonly property int resetsAt: root.live ? root.sessionResetsAt : root.estimateResetsAt
    readonly property int activeSessions: root.sessions.length

    function refresh() {
        if (!usageProc.running) usageProc.running = true;
    }

    Timer {
        interval: Config.options.bar.aiUsage.updateInterval * 1000
        repeat: true
        running: Config.ready
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: usageProc
        command: ["python3", Quickshell.shellPath("scripts/ai/claude-usage.py")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.sessions = data.sessions;
                    root.tokens = data.tokens;
                    root.estimateResetsAt = data.resetsAt;
                    root.live = data.live;
                    if (data.live) {
                        root.sessionPercent = data.sessionPercent;
                        root.sessionResetsAt = data.sessionResetsAt;
                        root.weekPercent = data.weekPercent;
                        root.weekResetsAt = data.weekResetsAt;
                    }
                    root.lastUpdated = Date.now() / 1000;
                } catch (e) {}
            }
        }
    }
}
