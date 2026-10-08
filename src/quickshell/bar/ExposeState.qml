pragma Singleton
import Quickshell

// Shared open/closed state so the workspace pill button can drive the
// overview that lives in faces/expose/ExposeFace.qml.
Singleton {
    property bool open: false
}
