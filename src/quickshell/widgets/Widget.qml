import QtQuick
import Quickshell
import Quickshell.Wayland
import "../"

PanelWindow {
    id: root
    color: "transparent"

    property string wId: Quickshell.env("QS_WIDGET_ID") || "preview"
    property string wType: "time"
    property string wVariant: ""
    property string wImagePath: ""
    property real wX: 0
    property real wY: 0
    property real wWidth: 250
    property real wHeight: 120
    property real wOpacity: 1.0
    property real wRotation: 0

    property var customProps: ({})

    readonly property real auraMargin: 8

    readonly property bool isSelected: typeof DesktopMenuController !== "undefined"
        && DesktopMenuController.isVisible
        && DesktopMenuController.mode === "widget"
        && DesktopMenuController.targetWidgetId === String(root.wId)
        && (!DesktopMenuController.screen || !root.screen || !DesktopMenuController.screen.name || !root.screen.name || DesktopMenuController.screen.name === root.screen.name)

    function applyCustomProps() {
        let it = faceLoader.item;
        if (!it || !customProps) return;
        let ignoredProps = [
            "objectName", "destroyed", "deleteLater", "parent", "data",
            "resources", "children", "visible", "enabled", "x", "y", "z",
            "width", "height", "opacity", "rotation", "scale"
        ];
        for (let k in customProps) {
            if (!k || typeof k !== "string") continue;
            if (k.endsWith("Changed") || k.startsWith("on") || typeof customProps[k] === "function" || customProps[k] === undefined) continue;
            if (ignoredProps.includes(k)) continue;
            try {
                if (it[k] !== undefined && it[k] !== customProps[k]) {
                    it[k] = customProps[k];
                }
            } catch (e) {}
        }
    }

    onCustomPropsChanged: applyCustomProps()

    property bool isRedacting: false
    property bool initialized: false

    property bool wantsKeyboardFocus: false
    readonly property bool effectiveKeyboardFocus: wantsKeyboardFocus || (faceLoader.item && (faceLoader.item.wantsKeyboardFocus || faceLoader.item.keyboardFocus || faceLoader.item.isEditingUser)) || false

    property real animX: wX
    property real animY: wY
    Behavior on animX {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }
    Behavior on animY {
        enabled: root.initialized && !root.isRedacting
        NumberAnimation {
            duration: 400
            easing.type: Easing.OutCubic
        }
    }

    property real effectiveWidth: wWidth
    property real effectiveHeight: wHeight

    onWWidthChanged: updateEffectiveSize()
    onWHeightChanged: updateEffectiveSize()
    onWVariantChanged: updateEffectiveSize()
    onWTypeChanged: updateEffectiveSize()

    WlrLayershell.namespace: "qs-widget-" + wType + "-" + wId
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: effectiveKeyboardFocus ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    exclusionMode: ExclusionMode.Ignore
    focusable: effectiveKeyboardFocus

    onEffectiveKeyboardFocusChanged: {
        if (effectiveKeyboardFocus && typeof root.requestActivate === "function") {
            root.requestActivate();
        }
    }

    anchors.top: true
    anchors.left: true
    margins.left: animX - root.auraMargin
    margins.top: animY - root.auraMargin

    implicitWidth: ((Math.round(wRotation || 0) % 180 === 0) ? effectiveWidth : effectiveHeight) + (root.auraMargin * 2)
    implicitHeight: ((Math.round(wRotation || 0) % 180 === 0) ? effectiveHeight : effectiveWidth) + (root.auraMargin * 2)

    Component.onCompleted: {
        Qt.callLater(() => {
            root.initialized = true;
        });
    }

    Component.onDestruction: visible = false

    function updateEffectiveSize() {
        if (!faceLoader.item) {
            root.effectiveWidth = root.wWidth;
            root.effectiveHeight = root.wHeight;
            return;
        }
        let item = faceLoader.item;
        let c = {
            minW: item.minWidth !== undefined ? item.minWidth : 10,
            minH: item.minHeight !== undefined ? item.minHeight : 10,
            maxW: item.maxWidth !== undefined ? item.maxWidth : 9999,
            maxH: item.maxHeight !== undefined ? item.maxHeight : 9999,
            minA: item.minAspect !== undefined ? item.minAspect : 0,
            maxA: item.maxAspect !== undefined ? item.maxAspect : 9999
        };
        let w = Math.max(c.minW, Math.min(c.maxW, root.wWidth));
        let h = Math.max(c.minH, Math.min(c.maxH, root.wHeight));

        let ratio = w / h;
        if (ratio < c.minA && c.minA > 0) {
            let mA = c.minA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        } else if (ratio > c.maxA && c.maxA > 0) {
            let mA = c.maxA;
            let hProj = (w * mA + h) / (mA * mA + 1);
            let hMin = Math.max(c.minH, c.minW / mA);
            let hMax = Math.min(c.maxH, c.maxW / mA);
            h = Math.max(hMin, Math.min(hMax, hProj));
            w = h * mA;
        }

        w = Math.max(c.minW, Math.min(c.maxW, w));
        h = Math.max(c.minH, Math.min(c.maxH, h));

        root.effectiveWidth = w;
        root.effectiveHeight = h;
    }

    Loader {
        id: faceLoader
        property string wImagePath: root.wImagePath
        property string imagePath: root.wImagePath
        property string path: root.wImagePath
        source: WidgetRegistry.faceFile(root.wType, root.wVariant)
        width: root.effectiveWidth
        height: root.effectiveHeight
        anchors.centerIn: parent
        rotation: root.wRotation || 0
        opacity: root.wOpacity
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
        onLoaded: {
            if (item) {
                try {
                    if (item.imagePath !== undefined) {
                        item.imagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.wImagePath !== undefined) {
                        item.wImagePath = Qt.binding(() => root.wImagePath);
                    }
                    if (item.path !== undefined) {
                        item.path = Qt.binding(() => root.wImagePath);
                    }
                    if (item.source !== undefined && typeof item.source === "string") {
                        item.source = Qt.binding(() => root.wImagePath);
                    }
                } catch (e) {}
            }
            root.applyCustomProps();
            root.updateEffectiveSize();
        }
    }

    Item {
        id: auraContainer
        width: faceLoader.width + (root.auraMargin * 2)
        height: faceLoader.height + (root.auraMargin * 2)
        anchors.centerIn: faceLoader
        rotation: faceLoader.rotation
        visible: opacity > 0.001
        opacity: root.isSelected ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
            }
        }

        Canvas {
            id: auraCanvas
            anchors.fill: parent
            antialiasing: true

            property real phase: 0.0

            NumberAnimation on phase {
                running: root.isSelected && auraContainer.opacity > 0.001
                from: 0.0
                to: Math.PI * 2
                duration: 3200
                loops: Animation.Infinite
            }

            onPhaseChanged: {
                if (auraContainer.opacity > 0.001) requestPaint();
            }

            Connections {
                target: root
                function onIsSelectedChanged() {
                    auraCanvas.requestPaint();
                }
                function onEffectiveWidthChanged() {
                    auraCanvas.requestPaint();
                }
                function onEffectiveHeightChanged() {
                    auraCanvas.requestPaint();
                }
            }

            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                if (auraContainer.opacity <= 0.001) return;

                let w = width;
                let h = height;
                if (w <= 0 || h <= 0) return;

                let baseR = 12;
                if (typeof ThemeBackend !== "undefined" && ThemeBackend.borderRadius !== undefined && ThemeBackend.borderRadius !== null) {
                    baseR = ThemeBackend.borderRadius;
                }
                let strokePad = 2.5;
                let r = Math.max(2, Math.min(baseR + 4, (w - 2 * strokePad) / 2, (h - 2 * strokePad) / 2));

                let x0 = strokePad;
                let y0 = strokePad;
                let x1 = w - strokePad;
                let y1 = h - strokePad;

                let straightX = (x1 - r) - (x0 + r);
                let straightY = (y1 - r) - (y0 + r);
                let arcLen = 0.5 * Math.PI * r;
                let totalP = 2 * (straightX + straightY) + 4 * arcLen;
                if (totalP <= 0) return;

                let cycles = Math.max(4, Math.round(totalP / 28));
                let freq = (2 * Math.PI * cycles) / totalP;
                let amp = 0.9;
                let step = 4.0;
                let ph = auraCanvas.phase;

                let dist = 0;
                ctx.beginPath();
                let started = false;

                function addPoint(x, y, nx, ny) {
                    let wOff = amp * Math.sin(freq * dist + ph);
                    let px = x + wOff * nx;
                    let py = y + wOff * ny;
                    if (!started) {
                        ctx.moveTo(px, py);
                        started = true;
                    } else {
                        ctx.lineTo(px, py);
                    }
                }

                for (let d = 0; d < straightX; d += step) {
                    dist += (d === 0 ? 0 : step);
                    addPoint(x0 + r + d, y0, 0, -1);
                }
                dist += (straightX % step === 0 ? 0 : (straightX % step));

                let arcSteps = Math.max(3, Math.ceil(arcLen / step));
                for (let i = 0; i <= arcSteps; i++) {
                    let a = -0.5 * Math.PI + (i / arcSteps) * (0.5 * Math.PI);
                    if (i > 0) dist += arcLen / arcSteps;
                    addPoint((x1 - r) + r * Math.cos(a), (y0 + r) + r * Math.sin(a), Math.cos(a), Math.sin(a));
                }

                for (let d = 0; d < straightY; d += step) {
                    dist += (d === 0 ? 0 : step);
                    addPoint(x1, y0 + r + d, 1, 0);
                }
                dist += (straightY % step === 0 ? 0 : (straightY % step));

                for (let i = 0; i <= arcSteps; i++) {
                    let a = (i / arcSteps) * (0.5 * Math.PI);
                    if (i > 0) dist += arcLen / arcSteps;
                    addPoint((x1 - r) + r * Math.cos(a), (y1 - r) + r * Math.sin(a), Math.cos(a), Math.sin(a));
                }

                for (let d = 0; d < straightX; d += step) {
                    dist += (d === 0 ? 0 : step);
                    addPoint(x1 - r - d, y1, 0, 1);
                }
                dist += (straightX % step === 0 ? 0 : (straightX % step));

                for (let i = 0; i <= arcSteps; i++) {
                    let a = 0.5 * Math.PI + (i / arcSteps) * (0.5 * Math.PI);
                    if (i > 0) dist += arcLen / arcSteps;
                    addPoint((x0 + r) + r * Math.cos(a), (y1 - r) + r * Math.sin(a), Math.cos(a), Math.sin(a));
                }

                for (let d = 0; d < straightY; d += step) {
                    dist += (d === 0 ? 0 : step);
                    addPoint(x0, y1 - r - d, -1, 0);
                }
                dist += (straightY % step === 0 ? 0 : (straightY % step));

                for (let i = 0; i <= arcSteps; i++) {
                    let a = Math.PI + (i / arcSteps) * (0.5 * Math.PI);
                    if (i > 0) dist += arcLen / arcSteps;
                    addPoint((x0 + r) + r * Math.cos(a), (y0 + r) + r * Math.sin(a), Math.cos(a), Math.sin(a));
                }

                ctx.closePath();

                let rawCol = "#89b4fa";
                if (typeof ThemeBackend !== "undefined") {
                    if (ThemeBackend.primary) rawCol = ThemeBackend.primary;
                    else if (ThemeBackend.blue) rawCol = ThemeBackend.blue;
                }
                let c = Qt.color(rawCol);

                ctx.strokeStyle = c;
                ctx.lineWidth = 2;
                ctx.stroke();
            }
        }
    }

    MouseArea {
        id: widgetMenuArea
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | (DesktopMenuController.isVisible ? Qt.LeftButton : 0)
        enabled: !root.isRedacting
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                DesktopMenuController.toggle(root.screen, (root.animX - root.auraMargin) + mouse.x, (root.animY - root.auraMargin) + mouse.y, "widget", root.wId);
            } else {
                DesktopMenuController.hide();
            }
        }
    }
}
