#!/usr/bin/env python3
import os, sys, shutil

data_home = os.environ.get("XDG_DATA_HOME", os.path.join(os.path.expanduser("~"), ".local", "share"))
install_root = os.environ.get("SERPANTINUM_INSTALL_DIR", os.path.join(data_home, "serpantinum"))
QS = os.path.join(install_root, "src", "quickshell", "quickactions", "actions")
TIMER = os.path.join(QS, "Timer.qml")
SRC = os.path.dirname(os.path.abspath(__file__))

if not os.path.isfile(TIMER):
    sys.exit("ERROR: %s not found, upstream layout changed" % TIMER)

shutil.copy(os.path.join(SRC, "SnakeGame.qml"), os.path.join(QS, "SnakeGame.qml"))

s = open(TIMER).read()
if "snakeLoader" in s:
    print("Timer.qml already patched; SnakeGame.qml refreshed")
    sys.exit(0)

edits = [
    ("anchors.topMargin: root.s(12)\n            width: root.s(270)",
     "anchors.topMargin: root.s(12)\n            width: root.s(320)"),
    ("property real stepSize: (parent.width - root.s(4)) / 3",
     "property real stepSize: (parent.width - root.s(4)) / 4"),
    ('I18n.t("quickactions.timer.tabs.pomodoro")\n                    ]',
     'I18n.t("quickactions.timer.tabs.pomodoro"),\n                        "Snake"\n                    ]'),
    ("width: (tabBar.width - root.s(4)) / 3",
     "width: (tabBar.width - root.s(4)) / 4"),
    ("text: modelData\n                            font.family: ThemeBackend.fontFamily\n                            font.bold: true\n                            font.pixelSize: root.s(12)",
     "text: modelData\n                            font.family: ThemeBackend.fontFamily\n                            font.bold: true\n                            font.pixelSize: root.s(11)"),
    ('else if (stateCache.activeMode === 0 && isTimerIdle) {\n            arr.push("Left", "Right", "Up", "Down");\n        }',
     'else if (stateCache.activeMode === 0 && isTimerIdle) {\n            arr.push("Left", "Right", "Up", "Down");\n        } else if (stateCache.activeMode === 3) {\n            arr.push("Left", "Right", "Up", "Down");\n        }'),
    ("stateCache.pomoTargetEpoch = now + stateCache.pomoRemainingMs;\n            }\n        }\n",
     "stateCache.pomoTargetEpoch = now + stateCache.pomoRemainingMs;\n            }\n        } else if (stateCache.activeMode === 3) {\n            if (snakeLoader.item) snakeLoader.item.togglePause();\n            return;\n        }\n"),
]

for old, _ in edits:
    n = s.count(old)
    if n != 1:
        sys.exit("ERROR: anchor found %d times (expected 1); upstream Timer.qml changed. Not patched.\n---\n%s" % (n, old))

tail = "            }\n        }\n    }\n}"
body = s.rstrip()
if not body.endswith(tail):
    sys.exit("ERROR: end of Timer.qml has an unexpected shape. Not patched.")

snake_block = (
    "            Loader {\n"
    "                id: snakeLoader\n"
    "                anchors.fill: parent\n"
    "                active: stateCache.activeMode === 3\n"
    "                source: Qt.resolvedUrl(\"SnakeGame.qml\")\n"
    "                onLoaded: {\n"
    "                    item.scaleFn = root.s\n"
    "                    item.storageDir = root.getStorageDir()\n"
    "                    item.active = Qt.binding(function() { return root.isActiveTab && stateCache.activeMode === 3 })\n"
    "                }\n"
    "            }\n"
)

shutil.copy(TIMER, TIMER + ".pre-snake")
for old, new in edits:
    s = s.replace(old, new, 1)
body = s.rstrip()
body = body[:-len(tail)] + "            }\n" + snake_block + "        }\n    }\n}\n"
open(TIMER, "w").write(body)
print("patched Timer.qml (backup: Timer.qml.pre-snake) and installed SnakeGame.qml")
