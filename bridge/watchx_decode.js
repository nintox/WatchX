// WatchX bridge (Mac) – Made by Rikerud
// Reads the WatchX code block from a screenshot. Uses JavaScript for Automation (ships with macOS).
//   osascript -l JavaScript watchx_decode.js <image> [clean.jpg]
// With a second path, a copy of the picture is written there with the code block painted over
// (and made smaller: max 1600 px), for the phone.
// Prints: OK<TAB>kind<TAB>id<TAB>subject<TAB>text   – a WatchX alert
//         NO                                        – a screenshot without a code block
//         ERR <reason>                              – the file can't be read (yet)
//
// The code block (see WatchX.lua, "instant alerts"): in the top-left corner, a black margin of one
// cell, a white border of one cell, then 48 data cells per row, MSB first:
//   "W" "X" <length> <payload> <fletcher-16 a> <b>
//   payload: <kind letter> <epoch: 4 bytes> <counter> <subject> 0x1F <text>
ObjC.import('AppKit');

var COLS = 48;
var KINDS = { S: 'SPAWN', L: 'LOOT', E: 'ENEMY', P: 'PLAYER', F: 'FRIEND', H: 'ATTACK', D: 'DEATH', T: 'TEST', A: 'AFK', O: 'LOGOUT' };

function run(argv) {
    var data = $.NSData.dataWithContentsOfFile(argv[0]);
    if (!data || data.isNil()) return 'ERR cannot read';
    var rep = $.NSBitmapImageRep.imageRepWithData(data);
    if (!rep || rep.isNil()) return 'ERR not an image';
    var W = rep.pixelsWide, H = rep.pixelsHigh;
    if (W < 200 || H < 200) return 'NO';
    var rgb = $.NSColorSpace.sRGBColorSpace;

    function lum(x, y) {
        x = Math.round(x); y = Math.round(y);
        if (x < 0 || y < 0 || x >= W || y >= H) return 0;
        var c = rep.colorAtXY(x, y);
        if (!c || c.isNil()) return 0;
        var s = c.colorUsingColorSpace(rgb);
        if (!s || s.isNil()) return 0;
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent;
    }
    function white(x, y) { return lum(x, y) > 0.5; }

    // Expected cell size: the block is drawn in screen units, and the screen is 768 units high.
    var cell0 = H * 7 / 768;
    // The white border: its top edge runs along y = 1.5 cells, its left edge along x = 1.5 cells.
    var yb = cell0 * 1.5, xb = cell0 * 1.5;
    var x0 = -1, x1 = -1, x = 0;
    var limit = Math.min(W - 1, Math.round(cell0 * (COLS + 8)));
    for (x = 0; x <= limit; x++) { if (white(x, yb)) { x0 = x; break; } }
    if (x0 < 0 || x0 > cell0 * 2.5) return 'NO';
    for (x = x0; x <= limit; x++) { if (!white(x, yb)) break; x1 = x; }
    var cell = (x1 - x0 + 1) / (COLS + 2);
    if (!(cell > cell0 * 0.7 && cell < cell0 * 1.3)) return 'NO';
    var y0 = -1, y;
    for (y = 0; y <= Math.round(cell0 * 2.5); y++) { if (white(x0 + cell * 0.5, y)) { y0 = y; break; } }
    if (y0 < 0) return 'NO';
    var gx = x0 + cell, gy = y0 + cell;   // the data grid, inside the border

    function bit(i) {
        var c = i % COLS, r = Math.floor(i / COLS);
        return white(gx + (c + 0.5) * cell, gy + (r + 0.5) * cell) ? 1 : 0;
    }
    function byteAt(n) {
        var v = 0;
        for (var k = 0; k < 8; k++) v = v * 2 + bit(n * 8 + k);
        return v;
    }
    if (byteAt(0) !== 87 || byteAt(1) !== 88) return 'NO';
    var len = byteAt(2);
    if (len < 7 || len > 120) return 'NO';
    var a = len % 255, b = len % 255, payload = [];
    for (var n = 0; n < len; n++) {
        var v = byteAt(3 + n);
        payload.push(v);
        a = (a + v) % 255;
        b = (b + a) % 255;
    }
    if (byteAt(3 + len) !== a || byteAt(4 + len) !== b) return 'NO';

    var kind = KINDS[String.fromCharCode(payload[0])] || 'TEST';
    var epoch = ((payload[1] * 256 + payload[2]) * 256 + payload[3]) * 256 + payload[4];
    var id = String(epoch) + ('00' + payload[5]).slice(-3);
    var rest = payload.slice(6);
    var sep = rest.indexOf(31);
    var subj = sep >= 0 ? rest.slice(0, sep) : rest;
    var text = sep >= 0 ? rest.slice(sep + 1) : [];
    function utf8(arr) {
        var s = '';
        for (var i = 0; i < arr.length; i++) s += '%' + ('0' + arr[i].toString(16)).slice(-2);
        try { return decodeURIComponent(s); } catch (e) { return String.fromCharCode.apply(null, arr); }
    }
    function clean(s) { return s.replace(/[\t\r\n]/g, ' '); }
    if (argv.length > 1) {
        try { writeClean(rep, W, H, x0 + (COLS + 3) * cell, y0 + (Math.ceil((len + 5) * 8 / COLS) + 3) * cell, argv[1]); }
        catch (e) {}
    }
    return ['OK', kind, id, clean(utf8(subj)), clean(utf8(text))].join('\t');
}

// The picture without the code block: drawn smaller (max 1600 px) with the block's corner painted dark.
function writeClean(rep, W, H, bw, bh, out) {
    var scale = Math.min(1, 1600 / Math.max(W, H));
    var w = Math.round(W * scale), h = Math.round(H * scale);
    var img = $.NSImage.alloc.initWithSize($.NSMakeSize(w, h));
    img.lockFocus;
    rep.drawInRect($.NSMakeRect(0, 0, w, h));
    $.NSColor.colorWithCalibratedRedGreenBlueAlpha(0.05, 0.05, 0.06, 1).setFill;
    // AppKit counts from the bottom: the block sits at the top-left
    $.NSRectFill($.NSMakeRect(0, h - Math.ceil(bh * scale) - 1, Math.ceil(bw * scale) + 1, Math.ceil(bh * scale) + 1));
    var shot = $.NSBitmapImageRep.alloc.initWithFocusedViewRect($.NSMakeRect(0, 0, w, h));
    img.unlockFocus;
    var props = $.NSDictionary.dictionaryWithObjectForKey($.NSNumber.numberWithDouble(0.75), $.NSImageCompressionFactor);
    var data = shot.representationUsingTypeProperties($.NSBitmapImageFileTypeJPEG, props);
    data.writeToFileAtomically(out, true);
}
