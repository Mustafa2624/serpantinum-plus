#!/usr/bin/env python3
"""Relay between stdin/stdout (Quickshell Process) and mpv's IPC unix socket."""
import json
import os
import socket
import sys
import threading
import time

path = sys.argv[1]
out = sys.stdout.buffer


def emit(obj):
    out.write((json.dumps(obj) + "\n").encode())
    out.flush()


s = None
deadline = time.time() + 10
while time.time() < deadline:
    try:
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        c.connect(path)
        s = c
        break
    except OSError:
        c.close()
        time.sleep(0.1)

if s is None:
    emit({"bridge": "error", "msg": "cannot connect to " + path})
    sys.exit(1)

emit({"bridge": "connected"})


def pump_in():
    try:
        while True:
            data = os.read(0, 65536)
            if not data:
                break
            s.sendall(data)
    except OSError:
        pass
    finally:
        try:
            s.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass


threading.Thread(target=pump_in, daemon=True).start()

try:
    while True:
        data = s.recv(65536)
        if not data:
            break
        out.write(data)
        out.flush()
except OSError:
    pass
