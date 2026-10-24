import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root

    function formatTokens(count) {
        if (count >= 1000000) return `${(count / 1000000).toFixed(1)}M`;
        if (count >= 1000) return `${Math.round(count / 1000)}k`;
        return `${count}`;
    }

    function formatReset(resetsAt) {
        if (resetsAt <= 0) return Translation.tr("No usage in this window");
        const seconds = Math.max(0, resetsAt - Date.now() / 1000);
        const d = Math.floor(seconds / 86400);
        const h = Math.floor((seconds % 86400) / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        return Translation.tr("Resets in %1").arg(d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${m}m` : `${m}m`);
    }

    function formatUpdated() {
        if (ClaudeUsage.refreshing) return Translation.tr("Refreshing...");
        if (ClaudeUsage.lastUpdated <= 0) return "";
        const seconds = Math.max(0, Date.now() / 1000 - ClaudeUsage.lastUpdated);
        const ago = seconds < 60 ? Translation.tr("just now") : Translation.tr("%1m ago").arg(Math.floor(seconds / 60));
        return Translation.tr("Updated %1 · click to refresh").arg(ago);
    }

    ColumnLayout {
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 3
            spacing: 7

            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimaryContainer

                CustomIcon {
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    source: "claude-symbolic"
                    colorize: true
                    color: Appearance.colors.colPrimary
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -3

                StyledText {
                    text: "Claude Code"
                    font {
                        weight: Font.Medium
                        pixelSize: Appearance.font.pixelSize.normal
                    }
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    text: (ClaudeUsage.live ? Translation.tr("Session") + " · " : "") + root.formatReset(ClaudeUsage.resetsAt)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                Layout.rightMargin: 8
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: `${Math.round(ClaudeUsage.percentage * 100)}%`
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            valueBarWidth: 260
            value: ClaudeUsage.percentage
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: ClaudeUsage.live

            ColumnLayout {
                spacing: -3

                StyledText {
                    text: Translation.tr("Weekly")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnSurfaceVariant
                    opacity: 0.6
                    text: root.formatReset(ClaudeUsage.weekResetsAt)
                }
            }

            Item {
                Layout.fillWidth: true
            }

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.Bold
                color: Appearance.colors.colPrimary
                text: `${Math.round(ClaudeUsage.weekPercentage * 100)}%`
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            visible: ClaudeUsage.live
            valueBarWidth: 260
            value: ClaudeUsage.weekPercentage
        }

        StyledPopupValueRow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: !ClaudeUsage.live
            icon: "token"
            label: Translation.tr("Tokens (estimate)")
            value: `${root.formatTokens(ClaudeUsage.tokens)} / ${root.formatTokens(ClaudeUsage.tokenLimit)}`
        }

        StyledPopupValueRow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: ClaudeUsage.activeSessions === 0
            icon: "bedtime"
            label: Translation.tr("No active sessions")
            value: ""
        }

        Repeater {
            model: ClaudeUsage.sessions
            delegate: StyledPopupValueRow {
                required property var modelData
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                icon: modelData.status === "busy" ? "progress_activity" : "terminal"
                label: modelData.name
                value: modelData.status === "busy" ? Translation.tr("Working") : Translation.tr("Idle")
            }
        }

        StyledPopupValueRow {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            icon: "refresh"
            label: root.formatUpdated()
            value: ""
        }
    }
}
