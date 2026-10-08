// Snake for Serpantinum's Quickactions panel.
// Game logic adapted from jhgundersen/omarchy-snake-plugin
// (MIT License, Copyright (c) jhgundersen). UI, theme and persistence rewritten.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../reusables"
import "../../"

Item {
    id: root

    property var scaleFn: null
    property string storageDir: ""
    property bool active: false

    function s(v) { return scaleFn ? scaleFn(v) : v }

    readonly property int cols: 20
    readonly property int rows: 14
    readonly property real cell: Math.max(4, Math.floor(Math.min(width / cols, (height - s(64)) / rows)))

    property var snake: []
    property var direction: ({ x: 1, y: 0 })
    property var directionQueue: []
    property var food: null
    property int score: 0
    property int best: 0
    property bool started: false
    property bool running: false
    property bool gameOver: false
    property bool newBest: false
    property string gameOverLine: ""
    property bool levelTransition: false
    property int completedLevel: 0
    property int displayedLevel: 1
    property var obstacleCells: []
    property var obstacleSet: ({})

    readonly property int pointsPerLevel: 12
    readonly property int layoutsPerCycle: 8

    function levelCycle(lvl) { return lvl <= 1 ? 0 : Math.floor((lvl - 2) / layoutsPerCycle) }
    function pointsForLevel(lvl) { return pointsPerLevel + levelCycle(lvl) }
    function scoreForLevel(lvl) {
        var total = 0
        for (var c = 1; c < lvl; c++) total += pointsForLevel(c)
        return total
    }
    function levelForScore(sc) {
        var lvl = 1
        var rem = sc
        while (rem >= pointsForLevel(lvl)) { rem -= pointsForLevel(lvl); lvl += 1 }
        return lvl
    }

    readonly property int level: levelForScore(score)
    readonly property int tickInterval: Math.max(55, 140 - levelCycle(level) * 7)
    readonly property real levelProgress: Math.max(0, Math.min(1, (score - scoreForLevel(level)) / pointsForLevel(level)))

    function obstaclesForLevel(lvl) {
        if (lvl <= 1) return []
        var cx = Math.floor(cols / 2)
        var cy = Math.floor(rows / 2)
        var tier = levelCycle(lvl)
        var gap = Math.max(2, 4 - tier)
        var kind = (lvl - 2) % layoutsPerCycle
        var cells = []

        function hbar(y, gapX, x0, x1) {
            for (var x = x0; x <= x1; x++) {
                if (x >= gapX && x < gapX + gap) continue
                cells.push({ x: x, y: y })
            }
        }
        function vbar(x, gapY, y0, y1) {
            for (var y = y0; y <= y1; y++) {
                if (y >= gapY && y < gapY + gap) continue
                cells.push({ x: x, y: y })
            }
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
            var ry0 = 2, ry1 = rows - 3, rx0 = 3, rx1 = cols - 4
            for (var x = rx0; x <= rx1; x++) { cells.push({ x: x, y: ry0 }); cells.push({ x: x, y: ry1 }) }
            for (var y = ry0 + 1; y < ry1; y++) {
                cells.push({ x: rx0, y: y })
                if (y < ry1 - gap) cells.push({ x: rx1, y: y })
            }
        } else if (kind === 5) {
            for (var i = 0; i < 6; i++) cells.push({ x: 3 + i, y: 3 + i })
            for (var j = 0; j < 6; j++) cells.push({ x: cols - 4 - j, y: rows - 4 - j })
        } else if (kind === 6) {
            for (var px = 3; px <= cols - 4; px += 3)
                for (var py = 2; py <= rows - 3; py += 3)
                    if ((px + py) % 2 === 0) cells.push({ x: px, y: py })
        } else {
            hbar(4, 2, 2, 8)
            hbar(rows - 5, cols - 9, 7, cols - 3)
        }
        return cells
    }

    function applyLevel(lvl) {
        displayedLevel = lvl
        var cells = obstaclesForLevel(lvl)
        var set = {}
        for (var i = 0; i < cells.length; i++) set[cells[i].x + "," + cells[i].y] = true
        obstacleCells = cells
        obstacleSet = set
    }

    function isObstacle(x, y) { return obstacleSet[x + "," + y] === true }

    function findClearRun(runLen) {
        var preferredY = Math.floor(rows / 2)
        for (var offset = 0; offset < rows; offset++) {
            var y = preferredY + (offset % 2 === 0 ? offset / 2 : -(offset + 1) / 2)
            if (y < 0 || y >= rows) continue
            for (var x = 2; x <= cols - runLen - 1; x++) {
                var clear = true
                for (var k = 0; k < runLen; k++) {
                    if (isObstacle(x + k, y)) { clear = false; break }
                }
                if (clear) return { x: x, y: y }
            }
        }
        return null
    }

    function findSpawnRow() {
        for (var runLen = 10; runLen >= 4; runLen -= 2) {
            var spot = findClearRun(runLen)
            if (spot) return spot
        }
        return { x: 2, y: Math.floor(rows / 2) }
    }

    function respawnSnake() {
        var spot = findSpawnRow()
        snake = [
            { x: spot.x + 2, y: spot.y },
            { x: spot.x + 1, y: spot.y },
            { x: spot.x, y: spot.y }
        ]
        direction = { x: 1, y: 0 }
        directionQueue = []
        spawnFood()
    }

    function spawnFood() {
        var free = []
        for (var x = 0; x < cols; x++) {
            for (var y = 0; y < rows; y++) {
                if (isObstacle(x, y)) continue
                var occupied = false
                for (var i = 0; i < snake.length; i++) {
                    if (snake[i].x === x && snake[i].y === y) { occupied = true; break }
                }
                if (!occupied) free.push({ x: x, y: y })
            }
        }
        if (free.length === 0) { endGame(); return }
        food = free[Math.floor(Math.random() * free.length)]
    }

    function resetGame() {
        running = false
        transitionTimer.stop()
        levelTransition = false
        completedLevel = 0
        gameOver = false
        newBest = false
        score = 0
        applyLevel(1)
        running = true
        respawnSnake()
    }

    function endGame() {
        gameOver = true
        running = false
        newBest = score > best
        if (newBest) { best = score; saveBest() }
        var lines = [
            "The wall wins again.",
            "So close. Probably.",
            "The timer is still running, you know.",
            "Respawning is free.",
            "That wall was there the whole time."
        ]
        gameOverLine = lines[Math.floor(Math.random() * lines.length)]
    }

    function tick() {
        if (directionQueue.length > 0) direction = directionQueue.shift()
        var head = snake[0]
        var nh = { x: head.x + direction.x, y: head.y + direction.y }

        if (nh.x < 0 || nh.x >= cols || nh.y < 0 || nh.y >= rows) { endGame(); return }
        if (isObstacle(nh.x, nh.y)) { endGame(); return }
        for (var i = 0; i < snake.length; i++) {
            if (snake[i].x === nh.x && snake[i].y === nh.y) { endGame(); return }
        }

        var ate = !!food && nh.x === food.x && nh.y === food.y
        var ns = [nh].concat(snake)
        if (!ate) ns.pop()
        snake = ns

        if (ate) {
            score += 1
            if (!levelTransition) spawnFood()
        }
    }

    function turn(dx, dy) {
        if (!running || gameOver || levelTransition) return
        var last = directionQueue.length > 0 ? directionQueue[directionQueue.length - 1] : direction
        if (dx === -last.x && dy === -last.y) return
        if (dx === last.x && dy === last.y) return
        if (directionQueue.length >= 2) return
        var q = directionQueue.slice()
        q.push({ x: dx, y: dy })
        directionQueue = q
    }

    function togglePause() {
        if (levelTransition) return
        started = true
        if (gameOver) { resetGame(); return }
        running = !running
    }

    function saveBest() {
        if (storageDir === "") return
        stateFile.setText(JSON.stringify({ best: best }))
    }

    onLevelChanged: {
        if (!running) return
        completedLevel = level - 1
        levelTransition = true
        transitionTimer.restart()
    }

    onActiveChanged: { if (!active && running) running = false }

    onStorageDirChanged: {
        if (storageDir === "") return
        mkdirProc.command = ["mkdir", "-p", storageDir]
        mkdirProc.running = true
    }

    Component.onCompleted: { resetGame(); running = false }

    Process { id: mkdirProc }

    FileView {
        id: stateFile
        path: root.storageDir !== "" ? root.storageDir + "/snake.json" : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                var d = JSON.parse(text())
                if (typeof d.best === "number" && d.best > root.best) root.best = d.best
            } catch (e) {}
        }
    }

    Timer {
        interval: root.tickInterval
        repeat: true
        running: root.active && root.running && !root.gameOver && !root.levelTransition
        onTriggered: root.tick()
    }

    Timer {
        id: transitionTimer
        interval: 1600
        onTriggered: {
            root.applyLevel(root.level)
            root.respawnSnake()
            root.levelTransition = false
        }
    }

    Shortcut { enabled: root.active; sequence: "Up"; onActivated: root.turn(0, -1) }
    Shortcut { enabled: root.active; sequence: "Down"; onActivated: root.turn(0, 1) }
    Shortcut { enabled: root.active; sequence: "Left"; onActivated: root.turn(-1, 0) }
    Shortcut { enabled: root.active; sequence: "Right"; onActivated: root.turn(1, 0) }
    Shortcut { enabled: root.active; sequence: "W"; onActivated: root.turn(0, -1) }
    Shortcut { enabled: root.active; sequence: "S"; onActivated: root.turn(0, 1) }
    Shortcut { enabled: root.active; sequence: "A"; onActivated: root.turn(-1, 0) }
    Shortcut { enabled: root.active; sequence: "D"; onActivated: root.turn(1, 0) }

    Column {
        anchors.centerIn: parent
        width: root.cols * root.cell
        spacing: root.s(6)

        Item {
            width: parent.width
            height: root.s(22)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Level " + root.level
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.s(14)
                font.weight: Font.Black
                font.bold: true
                color: ThemeBackend.mauve
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Score " + root.score + (root.best > 0 ? "   Best " + root.best : "")
                font.family: ThemeBackend.fontFamily
                font.pixelSize: root.s(11)
                font.bold: true
                color: ThemeBackend.subtext0
            }
        }

        Rectangle {
            width: parent.width
            height: root.s(5)
            radius: height / 2
            color: ThemeBackend.surface1

            Rectangle {
                width: parent.width * root.levelProgress
                height: parent.height
                radius: height / 2
                color: ThemeBackend.mauve
                Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }
        }

        Rectangle {
            id: board
            width: root.cols * root.cell
            height: root.rows * root.cell
            radius: ThemeBackend.borderRadius / 2
            color: ThemeBackend.surface0
            border.width: 1
            border.color: ThemeBackend.surface1
            clip: true

            Item {
                anchors.fill: parent
                opacity: root.levelTransition ? 0.25 : 1.0
                Behavior on opacity { NumberAnimation { duration: 300 } }

                Repeater {
                    model: root.obstacleCells
                    Rectangle {
                        required property var modelData
                        x: modelData.x * root.cell + 1
                        y: modelData.y * root.cell + 1
                        width: root.cell - 2
                        height: root.cell - 2
                        radius: 2
                        color: ThemeBackend.surface2
                    }
                }

                Repeater {
                    model: root.snake
                    Rectangle {
                        required property var modelData
                        required property int index
                        x: modelData.x * root.cell + 1
                        y: modelData.y * root.cell + 1
                        width: root.cell - 2
                        height: root.cell - 2
                        radius: 3
                        color: index === 0 ? ThemeBackend.text : ThemeBackend.mauve
                    }
                }

                Rectangle {
                    visible: !!root.food
                    x: root.food ? root.food.x * root.cell + root.cell * 0.15 : 0
                    y: root.food ? root.food.y * root.cell + root.cell * 0.15 : 0
                    width: root.cell * 0.7
                    height: root.cell * 0.7
                    radius: width / 2
                    color: ThemeBackend.peach
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.togglePause()
            }

            Rectangle {
                anchors.fill: parent
                visible: root.gameOver || !root.running || root.levelTransition
                color: Qt.rgba(0, 0, 0, 0.55)

                Column {
                    anchors.centerIn: parent
                    spacing: root.s(4)

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.levelTransition ? ("LEVEL " + root.completedLevel + " CLEARED")
                            : (root.gameOver ? "GAME OVER" : (root.started ? "PAUSED" : "SNAKE"))
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(18)
                        font.weight: Font.Black
                        font.bold: true
                        color: ThemeBackend.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.levelTransition ? ("Level " + root.level + " incoming")
                            : (root.gameOver ? (root.newBest ? "New best: " + root.score : "Score " + root.score + "  ·  Enter to restart")
                                             : (root.started ? "Enter to resume" : "Enter to play"))
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(11)
                        color: ThemeBackend.subtext0
                    }
                    Text {
                        visible: root.gameOver
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.gameOverLine
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: root.s(10)
                        color: ThemeBackend.subtext0
                        opacity: 0.8
                    }
                }
            }
        }

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "arrows / wasd to steer  ·  Enter to pause"
            font.family: ThemeBackend.fontFamily
            font.pixelSize: root.s(10)
            color: ThemeBackend.subtext0
        }
    }
}
