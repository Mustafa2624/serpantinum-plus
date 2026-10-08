.pragma library

// Source aspect ratio of a window (falls back to 16:10 if unknown).
function aspectOf(win) {
    var ipc = win && win.lastIpcObject ? win.lastIpcObject : null;
    var size = ipc && ipc.size ? ipc.size : null;
    return size && size.length >= 2 && size[0] > 0 && size[1] > 0
        ? size[0] / size[1]
        : 16 / 10;
}

// Choose the grid that gives the current windows the most total preview area
// while keeping each thumbnail within its source aspect ratio.
// labelHeight is the space reserved under each thumbnail for its title row.
function fit(windows, availableWidth, availableHeight, gap, labelHeight) {
    var count = windows ? windows.length : 0;
    if (count < 1) return { columns: 1, rows: 1, cardWidth: 0, cardHeight: 0 };

    var width = Math.max(1, availableWidth);
    var height = Math.max(1, availableHeight);
    var spacing = Math.max(0, gap || 0);
    var label = Math.max(0, labelHeight || 0);

    // Aspects don't depend on the grid shape, so read them once.
    var aspects = new Array(count);
    for (var i = 0; i < count; i++) aspects[i] = aspectOf(windows[i]);

    var best = null;

    for (var columns = 1; columns <= count; columns++) {
        var rows = Math.ceil(count / columns);
        var cardWidth = Math.max(1, (width - spacing * (columns - 1)) / columns);
        var cardHeight = Math.max(1, (height - spacing * (rows - 1)) / rows);
        var thumbHeight = Math.max(1, cardHeight - label);
        var area = 0;

        for (var j = 0; j < count; j++) {
            var fittedWidth = Math.min(cardWidth, thumbHeight * aspects[j]);
            area += fittedWidth * (fittedWidth / aspects[j]);
        }

        // Prefer fewer rows when two layouts use essentially the same image area.
        var score = area - rows * width * height * 0.00001;
        if (!best || score > best.score) {
            best = { columns: columns, rows: rows, cardWidth: cardWidth, cardHeight: cardHeight, score: score };
        }
    }

    return best;
}
