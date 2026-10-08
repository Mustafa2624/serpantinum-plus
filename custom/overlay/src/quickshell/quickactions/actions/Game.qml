import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../"

// Snake game logic adapted from jhgundersen/omarchy-snake-plugin (MIT); see custom/THIRD_PARTY_NOTICES.md.

Item {
    id: root

    // Serpantinum quick-action module contract.
    property int requestedLayoutTemplate: 1
    property bool isActiveTab: typeof isCurrentTarget !== "undefined" ? isCurrentTarget : true
    property string safeActiveEdge: typeof activeEdge !== "undefined" ? activeEdge : "left"

    function s(v) { return typeof scaleFunc === "function" ? scaleFunc(v) : v }

    property real baseW: s(380)
    property real baseL: s(320)
    property real preferredWidth: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseL + s(50) : baseW
    property real preferredExtraLength: (safeActiveEdge === "bottom" || safeActiveEdge === "top") ? baseW : baseL

    property real counterRotation: {
        if (safeActiveEdge === "right") return 180
        if (safeActiveEdge === "bottom") return 90
        if (safeActiveEdge === "top") return -90
        return 0
    }

    readonly property int cols: 22
    readonly property int rows: 16
    readonly property real cellSize: s(15)

    property var snake: []
    property var direction: ({x: 1, y: 0})
    property var directionQueue: []
    property var food: null
    property int score: 0
    property int bestLevels: 0
    property int bestEndless: 0
    readonly property int best: endlessMode ? bestEndless : bestLevels
    property bool running: false
    property bool gameOver: false
    property bool endlessMode: false
    property bool wallsWrap: false
    property bool levelTransition: false
    property int completedLevel: 0
    property int levelSeconds: 0
    property int displayedLevel: 1
    property int elapsedSeconds: 0
    property int totalSeconds: 0
    property bool stateLoaded: false
    property var diskState: null

    readonly property int pointsPerLevel: 12
    readonly property int layoutsPerCycle: 8
    readonly property int level: endlessMode ? 1 : levelForScore(score)
    readonly property var obstacles: endlessMode ? [] : obstaclesForLevel(displayedLevel)
    readonly property int tickInterval: endlessMode ? 140 : Math.max(55, 140 - levelCycle(level) * 7)
    readonly property real levelProgress: {
        if (endlessMode) return 1.0
        let base = scoreForLevel(level)
        return Math.max(0, Math.min(1, (score - base) / pointsForLevel(level)))
    }
    readonly property string elapsedTimeText: {
        let m = Math.floor(elapsedSeconds / 60), sec = elapsedSeconds % 60
        return (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec
    }

    // Floating.qml asks active modules which global shortcuts they consume.
    readonly property var interceptedShortcuts: [
        "Up", "Down", "Left", "Right", "W", "A", "S", "D", "Space", "M", "B", "F", "R"
    ]

    readonly property var foodPalette: [
        ThemeBackend.mauve,
        ThemeBackend.teal,
        ThemeBackend.peach,
        ThemeBackend.subtext0,
        ThemeBackend.text,
        ThemeBackend.surface2
    ]
    readonly property var foodStyles: [
        {text: "🍎", color: foodPalette[0]},
        {text: "🍇", color: foodPalette[1]},
        {text: "🍓", color: foodPalette[2]},
        {text: "🍒", color: foodPalette[3]},
        {text: "🍉", color: foodPalette[4]},
        {text: "🍋", color: foodPalette[5]}
    ]
    property int foodStyleIndex: 0
    readonly property var currentFoodStyle: foodStyles[foodStyleIndex % foodStyles.length]

    property string gameOverMessage: ""
    property string levelCompleteMessage: ""

    function levelCycle(lvl) { return lvl <= 1 ? 0 : Math.floor((lvl - 2) / layoutsPerCycle) }
    function pointsForLevel(lvl) { return pointsPerLevel + levelCycle(lvl) }

    function scoreForLevel(lvl) {
        let total = 0
        for (let current = 1; current < lvl; current++) total += pointsForLevel(current)
        return total
    }

    function levelForScore(value) {
        let lvl = 1, remaining = value
        while (remaining >= pointsForLevel(lvl)) { remaining -= pointsForLevel(lvl); lvl += 1 }
        return lvl
    }

    function obstaclesForLevel(lvl) {
        if (lvl <= 1) return []
        let cx = Math.floor(cols / 2), cy = Math.floor(rows / 2)
        let gap = Math.max(2, 4 - levelCycle(lvl))
        let kind = (lvl - 2) % layoutsPerCycle
        let cells = []
        function hbar(y, gapX, x0, x1) {
            for (let x = x0; x <= x1; x++) if (!(x >= gapX && x < gapX + gap)) cells.push({x: x, y: y})
        }
        function vbar(x, gapY, y0, y1) {
            for (let y = y0; y <= y1; y++) if (!(y >= gapY && y < gapY + gap)) cells.push({x: x, y: y})
        }
        if (kind === 0) {
            hbar(cy, cx - Math.floor(gap / 2), 2, cols - 3)
        } else if (kind === 1) {
            vbar(cx, cy - Math.floor(gap / 2), 2, rows - 3)
        } else if (kind === 2) {
            hbar(Math.floor(rows / 3), 2, 2, cols - 3)
            hbar(Math.floor(rows * 2 / 3), cols - 2 - gap, 2, cols - 3)
        } else if (kind === 3) {
            hbar(cy, cx - Math.floor(gap / 2), 2, cols - 3)
            vbar(cx, cy - Math.floor(gap / 2), 2, rows - 3)
        } else if (kind === 4) {
            let y0 = 2, y1 = rows - 3, x0 = 3, x1 = cols - 4
            for (let x = x0; x <= x1; x++) { cells.push({x: x, y: y0}); cells.push({x: x, y: y1}) }
            for (let y = y0 + 1; y < y1; y++) {
                cells.push({x: x0, y: y})
                if (y < y1 - gap) cells.push({x: x1, y: y})
            }
        } else if (kind === 5) {
            for (let i = 0; i < 6; i++) cells.push({x: 3 + i, y: 3 + i})
            for (let i = 0; i < 6; i++) cells.push({x: cols - 4 - i, y: rows - 4 - i})
        } else if (kind === 6) {
            for (let x = 3; x <= cols - 4; x += 3)
                for (let y = 2; y <= rows - 3; y += 3)
                    if ((x + y) % 2 === 0) cells.push({x: x, y: y})
        } else {
            hbar(4, 2, 2, 8)
            hbar(rows - 5, cols - 9, 7, cols - 3)
        }
        return cells
    }

    function isObstacle(x, y) {
        let list = endlessMode ? [] : obstaclesForLevel(level)
        for (let i = 0; i < list.length; i++) if (list[i].x === x && list[i].y === y) return true
        return false
    }

    function findClearRun(runLen) {
        let center = Math.floor(rows / 2), order = [center]
        for (let d = 1; d < rows; d++) {
            if (center - d >= 0) order.push(center - d)
            if (center + d < rows) order.push(center + d)
        }
        for (let r = 0; r < order.length; r++) {
            let y = order[r]
            for (let x0 = 1; x0 <= cols - runLen - 1; x0++) {
                let clear = true
                for (let x = x0; x < x0 + runLen; x++) if (isObstacle(x, y)) { clear = false; break }
                if (clear) return {x: x0, y: y}
            }
        }
        return null
    }

    function findSpawnRow() {
        for (let runLen = 10; runLen >= 4; runLen -= 2) {
            let spot = findClearRun(runLen)
            if (spot) return spot
        }
        return {x: 2, y: Math.floor(rows / 2)}
    }

    function respawnSnake() {
        let spot = findSpawnRow()
        snake = [
            {x: spot.x + 2, y: spot.y},
            {x: spot.x + 1, y: spot.y},
            {x: spot.x, y: spot.y}
        ]
        direction = {x: 1, y: 0}
        directionQueue = []
        spawnFood()
    }

    function resetGame() {
        running = false
        levelTransitionTimer.stop()
        levelBoardTransition.stop()
        boardContent.opacity = 1
        score = 0
        displayedLevel = 1
        elapsedSeconds = 0
        levelSeconds = 0
        levelTransition = false
        completedLevel = 0
        levelCompleteMessage = ""
        gameOverMessage = ""
        gameOver = false
        running = true
        respawnSnake()
    }

    function spawnFood() {
        let free = []
        for (let x = 0; x < cols; x++) for (let y = 0; y < rows; y++) {
            if (isObstacle(x, y)) continue
            let occupied = false
            for (let i = 0; i < snake.length; i++) if (snake[i].x === x && snake[i].y === y) { occupied = true; break }
            if (!occupied) free.push({x: x, y: y})
        }
        if (free.length === 0) { endGame(); return }
        food = free[Math.floor(Math.random() * free.length)]
    }

    function formatDuration(total) {
        let h = Math.floor(total / 3600), m = Math.floor((total % 3600) / 60), s2 = total % 60
        if (h > 0) return h + "h" + m + "m"
        if (m > 0) return m + "m" + s2 + "s"
        return s2 + "s"
    }

    function fillTemplate(template) {
        return template.replace("{time}", formatDuration(elapsedSeconds))
            .replace("{score}", score).replace("{level}", level)
    }

    readonly property var gameOverQuips: [
        "Score: {score}. The snake has filed no complaints.",
        "You made it {time}. Your real work is still undefeated.",
        "Level {level}. The walls remain undefeated.",
        "{score} points. Somewhere, a Nokia 3310 nods respectfully.",
        "{time} spent here. The build is still compiling.",
        "You and the wall had a productive {time} together.",
        "New high score: {score}. The trophy is imaginary.",
        "You beat level {level}. Please return to pretending to work."
    ]

    function endGame() {
        gameOver = true
        running = false
        let isNewBest = score > best
        if (isNewBest) {
            if (endlessMode) bestEndless = score
            else bestLevels = score
        }
        saveState()
        let pool = isNewBest
            ? ["New high score: {score}. Nicely done.", "Personal best: {score}. History has been made, barely.", "Record broken: {score}. The snake salutes you."]
            : gameOverQuips
        gameOverMessage = fillTemplate(pool[Math.floor(Math.random() * pool.length)])
    }

    function tick() {
        if (directionQueue.length > 0) direction = directionQueue.shift()
        let head = snake[0], newHead = {x: head.x + direction.x, y: head.y + direction.y}
        if (newHead.x < 0 || newHead.x >= cols || newHead.y < 0 || newHead.y >= rows) {
            if (!wallsWrap) { endGame(); return }
            newHead.x = (newHead.x + cols) % cols
            newHead.y = (newHead.y + rows) % rows
        }
        if (isObstacle(newHead.x, newHead.y)) { endGame(); return }
        for (let i = 0; i < snake.length; i++) if (snake[i].x === newHead.x && snake[i].y === newHead.y) { endGame(); return }
        let ateFood = !!food && newHead.x === food.x && newHead.y === food.y
        let next = [newHead].concat(snake)
        if (!ateFood) next.pop()
        snake = next
        if (ateFood) { score += 1; if (!levelTransition) spawnFood() }
    }

    function turn(dx, dy) {
        if (gameOver || levelTransition) return
        let last = directionQueue.length > 0 ? directionQueue[directionQueue.length - 1] : direction
        if ((dx === -last.x && dy === -last.y) || (dx === last.x && dy === last.y)) return
        if (directionQueue.length >= 2) return
        directionQueue.push({x: dx, y: dy})
    }

    function togglePause() {
        if (levelTransition) return
        if (gameOver) { resetGame(); return }
        running = !running
    }

    function toggleMode() { running = false; endlessMode = !endlessMode; resetGame() }
    function toggleWallsWrap() { wallsWrap = !wallsWrap; saveState() }
    function cycleFoodStyle() { foodStyleIndex = (foodStyleIndex + 1) % foodStyles.length; saveState() }

    // Stored separately from Omarchy: this is a Serpantinum quick-action.
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/serpantinum/quickactions/snake"
    readonly property string statePath: stateDir + "/state.json"

    function extractState(parsed) {
        let d = parsed || {}
        return {
            bestLevels: typeof d.bestLevels === "number" ? d.bestLevels : 0,
            bestEndless: typeof d.bestEndless === "number" ? d.bestEndless : 0,
            totalSeconds: typeof d.totalSeconds === "number" ? d.totalSeconds : 0,
            foodStyleIndex: typeof d.foodStyleIndex === "number" ? Math.floor(d.foodStyleIndex) : -1,
            wallsWrap: typeof d.wallsWrap === "boolean" ? d.wallsWrap : false
        }
    }

    function recordDiskState(raw) {
        let parsed = null
        try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
        diskState = extractState(parsed)
        if (stateLoaded) return
        if (diskState.bestLevels > bestLevels) bestLevels = diskState.bestLevels
        if (diskState.bestEndless > bestEndless) bestEndless = diskState.bestEndless
        if (diskState.totalSeconds > totalSeconds) totalSeconds = diskState.totalSeconds
        if (diskState.foodStyleIndex >= 0 && diskState.foodStyleIndex < foodStyles.length) foodStyleIndex = diskState.foodStyleIndex
        wallsWrap = diskState.wallsWrap
        stateLoaded = true
    }

    function saveState() {
        if (!stateLoaded) return
        let d = diskState || extractState(null)
        bestLevels = Math.max(bestLevels, d.bestLevels)
        bestEndless = Math.max(bestEndless, d.bestEndless)
        totalSeconds = Math.max(totalSeconds, d.totalSeconds)
        let payload = {
            version: 1,
            bestLevels: bestLevels,
            bestEndless: bestEndless,
            totalSeconds: totalSeconds,
            foodStyleIndex: foodStyleIndex,
            wallsWrap: wallsWrap
        }
        diskState = extractState(payload)
        stateFile.setText(JSON.stringify(payload, null, 2) + "\n")
    }

    Process { id: stateInitProc; command: ["mkdir", "-p", root.stateDir] }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.recordDiskState(text())
        onLoadFailed: root.recordDiskState("")
    }

    Component.onCompleted: {
        stateInitProc.running = true
        Qt.callLater(function() { stateFile.reload() })
    }

    onIsActiveTabChanged: {
        if (isActiveTab) resetGame()
        else saveState()
    }

    onLevelChanged: {
        if (!running || endlessMode || level <= displayedLevel) return
        completedLevel = level - 1
        levelCompleteMessage = "Level " + completedLevel + " cleared in " + formatDuration(levelSeconds) + ". The snake requests a raise."
        levelTransition = true
        levelBoardTransition.restart()
        levelTransitionTimer.restart()
    }

    Timer {
        id: gameTimer
        interval: root.tickInterval
        repeat: true
        running: root.isActiveTab && root.running && !root.gameOver && !root.levelTransition
        onTriggered: root.tick()
    }

    Timer {
        id: secondsTimer
        interval: 1000
        repeat: true
        running: root.isActiveTab && root.running && !root.gameOver && !root.levelTransition
        onTriggered: { root.elapsedSeconds += 1; root.totalSeconds += 1; if (!root.endlessMode) root.levelSeconds += 1 }
    }

    Timer {
        id: levelTransitionTimer
        interval: 2400
        onTriggered: { root.levelTransition = false; root.levelSeconds = 0 }
    }

    SequentialAnimation {
        id: levelBoardTransition
        NumberAnimation { target: boardContent; property: "opacity"; from: 1; to: 0; duration: 400; easing.type: Easing.InOutCubic }
        ScriptAction { script: { root.displayedLevel = root.level; root.respawnSnake() } }
        NumberAnimation { target: boardContent; property: "opacity"; from: 0; to: 1; duration: 500; easing.type: Easing.OutCubic }
    }

    Shortcut { enabled: root.isActiveTab; sequence: "Up"; onActivated: root.turn(0, -1) }
    Shortcut { enabled: root.isActiveTab; sequence: "Down"; onActivated: root.turn(0, 1) }
    Shortcut { enabled: root.isActiveTab; sequence: "Left"; onActivated: root.turn(-1, 0) }
    Shortcut { enabled: root.isActiveTab; sequence: "Right"; onActivated: root.turn(1, 0) }
    Shortcut { enabled: root.isActiveTab; sequence: "W"; onActivated: root.turn(0, -1) }
    Shortcut { enabled: root.isActiveTab; sequence: "A"; onActivated: root.turn(-1, 0) }
    Shortcut { enabled: root.isActiveTab; sequence: "S"; onActivated: root.turn(0, 1) }
    Shortcut { enabled: root.isActiveTab; sequence: "D"; onActivated: root.turn(1, 0) }
    Shortcut { enabled: root.isActiveTab; sequence: "Space"; onActivated: root.togglePause() }
    Shortcut { enabled: root.isActiveTab; sequence: "M"; onActivated: root.toggleMode() }
    Shortcut { enabled: root.isActiveTab; sequence: "B"; onActivated: root.toggleWallsWrap() }
    Shortcut { enabled: root.isActiveTab; sequence: "F"; onActivated: root.cycleFoodStyle() }
    Shortcut { enabled: root.isActiveTab; sequence: "R"; onActivated: root.resetGame() }

    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredExtraLength

    Item {
        id: orientedRoot
        anchors.centerIn: parent
        width: (root.counterRotation % 180 !== 0) ? parent.height : parent.width
        height: (root.counterRotation % 180 !== 0) ? parent.width : parent.height
        rotation: root.counterRotation
        clip: true

        Rectangle {
            anchors.fill: parent
            color: ThemeBackend.mantle
            radius: ThemeBackend.borderRadius
            border.width: 1
            border.color: ThemeBackend.surface1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.s(12)
            spacing: root.s(8)

            Item {
                Layout.fillWidth: true
                implicitHeight: titleText.implicitHeight
                Text {
                    id: titleText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.endlessMode ? "Endless" : ("Level " + root.level)
                    color: ThemeBackend.text
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(18)
                    font.weight: Font.Black
                    font.bold: true
                }
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Score " + root.score + (root.best > 0 ? "  ·  Best " + root.best : "")
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(10)
                    font.bold: true
                }
            }

            Item {
                Layout.fillWidth: true
                height: root.s(18)
                Rectangle {
                    width: parent.width
                    height: root.s(5)
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.endlessMode
                    color: ThemeBackend.surface1
                    Rectangle { width: parent.width * root.levelProgress; height: parent.height; radius: height / 2; color: ThemeBackend.mauve }
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.endlessMode
                    text: root.elapsedTimeText
                    color: ThemeBackend.subtext0
                    font.family: ThemeBackend.fontFamily
                    font.pixelSize: root.s(10)
                    font.bold: true
                }
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.cols * root.cellSize
                Layout.preferredHeight: root.rows * root.cellSize

                Rectangle {
                    id: board
                    anchors.fill: parent
                    color: ThemeBackend.base
                    border.color: ThemeBackend.surface1
                    border.width: 1
                    radius: root.s(4)
                    clip: true

                    Item {
                        id: boardContent
                        anchors.fill: parent
                        Repeater {
                            model: root.obstacles
                            delegate: Rectangle {
                                required property var modelData
                                x: modelData.x * root.cellSize + 1
                                y: modelData.y * root.cellSize + 1
                                width: root.cellSize - 2
                                height: root.cellSize - 2
                                radius: root.s(1)
                                color: ThemeBackend.surface2
                            }
                        }
                        Repeater {
                            model: root.snake
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                x: modelData.x * root.cellSize + 1
                                y: modelData.y * root.cellSize + 1
                                width: root.cellSize - 2
                                height: root.cellSize - 2
                                radius: root.s(3)
                                color: index === 0 ? ThemeBackend.text : ThemeBackend.mauve
                            }
                        }
                        Text {
                            visible: !!root.food
                            x: root.food ? root.food.x * root.cellSize : 0
                            y: root.food ? root.food.y * root.cellSize : 0
                            width: root.cellSize
                            height: root.cellSize
                            text: root.currentFoodStyle.text
                            color: root.currentFoodStyle.color
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: root.s(14)
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea { anchors.fill: parent; onClicked: root.cycleFoodStyle() }

                    Rectangle {
                        anchors.fill: parent
                        visible: root.gameOver || !root.running || root.levelTransition
                        color: Qt.rgba(0, 0, 0, 0.55)
                        Column {
                            anchors.centerIn: parent
                            width: parent.width - root.s(24)
                            spacing: root.s(4)
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.levelTransition ? ("LEVEL " + root.completedLevel + " CLEARED") : (root.gameOver ? "GAME OVER" : "PAUSED")
                                color: ThemeBackend.text
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(18)
                                font.weight: Font.Black
                                font.bold: true
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.levelTransition ? ("Level " + root.level + " incoming") : (root.gameOver ? "Space to restart" : "Space to resume")
                                color: ThemeBackend.text
                                opacity: 0.9
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(10)
                            }
                            Text {
                                visible: root.gameOver || root.levelTransition
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width
                                text: root.levelTransition ? root.levelCompleteMessage : root.gameOverMessage
                                color: ThemeBackend.text
                                opacity: 0.7
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: root.s(9)
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Arrows / WASD / Space · M mode · B borders · F food · R restart"
                color: ThemeBackend.subtext0
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.s(8)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: root.s(12)
                HintLabel { text: "mode: " + (root.endlessMode ? "Endless" : "Levels"); onClicked: root.toggleMode() }
                HintLabel { text: "borders: " + (root.wallsWrap ? "Wrap" : "Solid"); onClicked: root.toggleWallsWrap() }
                HintLabel { text: "food: " + root.currentFoodStyle.text; onClicked: root.cycleFoodStyle() }
            }
        }
    }

    component HintLabel: Item {
        id: hintLabel
        required property string text
        signal clicked()
        implicitWidth: label.implicitWidth
        implicitHeight: label.implicitHeight
        Text {
            id: label
            text: hintLabel.text
            color: mouseArea.containsMouse ? ThemeBackend.text : ThemeBackend.subtext0
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(9)
        }
        MouseArea {
            id: mouseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hintLabel.clicked()
        }
    }
}
