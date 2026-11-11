// SPDX-License-Identifier: GPL-2.0-only
//
// n-groups — core logic.
//
//   * A group is a set of >= 2 windows sharing one Alt+Tab entry: only the
//     last used member stays in the switcher, the rest get skipSwitcher.
//   * Auto groups: windows tiled in the same layout (Meta+T), or quick-tiled,
//     on the same screen + desktop + activity.
//   * Manual groups (Meta+Space twice) win over auto groups. Linking always
//     merges both sides' whole groups. They live in memory only.
//
// Every change just calls schedule(); reconcile() recomputes all groups from
// scratch and applies the skipSwitcher diff, so missed events can't leave
// windows hidden.
//
// Inspired by HiluaGhoest/kwin-window-groups (GPL-2.0-only).

const ICON_GROUP = "object-group";
const ICON_UNGROUP = "object-ungroup";
const ICON_INFO = "preferences-system-windows";

let api = null;
let ws = null;
let cfg = {};

const tracked = new Map();    // wid -> Window
const connected = new Set();  // wid with signal handlers (survive reloads, see init)
const origSkip = new Map();   // wid -> skipSwitcher before we touched it
const manualOf = new Map();   // wid -> manual group id
const excluded = new Set();   // wid taken out of its auto group while tiled
const lastUsed = new Map();   // group key -> wid shown in Alt+Tab
let groups = new Map();       // group key -> Window[]
let groupOf = new Map();      // wid -> group key
let nextManualId = 1;
let activeGroupKey = null;
let pending = null;           // window picked by the first Meta+Space
let busy = false;             // we are raising/minimizing ourselves
let initialized = false;
// KWin keeps this module cached for the whole session and, on reload,
// destroys the old script instance after creating the new one. Only the
// teardown() of the current generation may clear state.
let generation = 0;

// --- helpers ---------------------------------------------------------------

const wid = (w) => String(w.internalId);

function list(qlist) {
    const out = [];
    for (let i = 0; qlist && i < qlist.length; i++) out.push(qlist[i]);
    return out;
}

function alive(w) {
    try {
        return !!w && !w.deleted && tracked.has(wid(w));
    } catch (e) {
        return false;
    }
}

function label(w) {
    const cls = String(w.resourceClass || w.resourceName || w.caption || "?").split(".").pop();
    return cls.charAt(0).toUpperCase() + cls.slice(1);
}

const joinLabels = (windows) => windows.map(label).join(" + ");

function osd(icon, text) {
    if (cfg.showOsd) api.osd(icon, text);
}

function readConfig() {
    // kwinrc values may come back as bool or as the string "true"/"false".
    const bool = (key) => String(api.readConfig(key, true)) === "true";
    cfg = {
        autoGroup: bool("autoGroup"),
        includeQuickTile: bool("includeQuickTile"),
        minimizeTogether: bool("minimizeTogether"),
        showOsd: bool("showOsd"),
    };
}

// --- grouping --------------------------------------------------------------

function isCandidate(w) {
    try {
        return alive(w) && w.managed && w.normalWindow && !w.transient && !w.specialWindow
            // Already hidden from Alt+Tab by someone else (rules, Yakuake…).
            && (origSkip.has(wid(w)) || !w.skipSwitcher);
    } catch (e) {
        return false;
    }
}

function autoKey(w) {
    const tile = w.tile;
    if (!cfg.autoGroup || !tile || excluded.has(wid(w))) return null;
    let root = tile;
    while (root.parent) root = root.parent;

    // Meta+T layouts hang from Workspace.rootTile(); quick tiles don't.
    const desktops = w.onAllDesktops ? [ws.currentDesktop] : list(w.desktops);
    const custom = desktops.some((d) => ws.rootTile(w.output, d) === root);
    if (!custom && !cfg.includeQuickTile) return null;

    return [custom ? "tile" : "quick", w.output.name,
        w.onAllDesktops ? "*" : desktops.map((d) => d.id).sort().join(","),
        list(w.activities).sort().join(",")].join("|");
}

function setHidden(w, hidden) {
    const id = wid(w);
    if (!origSkip.has(id)) origSkip.set(id, !!w.skipSwitcher);
    const value = hidden || origSkip.get(id);
    if (w.skipSwitcher !== value) w.skipSwitcher = value;
}

function restoreSkip(w) {
    const id = wid(w);
    if (!origSkip.has(id)) return;
    const value = origSkip.get(id);
    origSkip.delete(id);
    try {
        if (!w.deleted && w.skipSwitcher !== value) w.skipSwitcher = value;
    } catch (e) {}
}

function representative(key, members) {
    if (members.includes(ws.activeWindow)) return ws.activeWindow;
    const last = members.find((m) => wid(m) === lastUsed.get(key));
    if (last) return last;
    const stack = list(ws.stackingOrder);
    return members.reduce((top, m) => (stack.indexOf(m) > stack.indexOf(top) ? m : top));
}

export function reconcile() {
    if (!initialized) return;
    // A manual group left with one window (others closed or unlinked) is
    // gone: release that window so it can join auto groups again.
    const manualSize = new Map();
    for (const [id, gid] of manualOf) {
        if (isCandidate(tracked.get(id))) manualSize.set(gid, (manualSize.get(gid) || 0) + 1);
    }
    for (const [id, gid] of [...manualOf]) if ((manualSize.get(gid) || 0) < 2) manualOf.delete(id);

    const buckets = new Map();
    for (const w of tracked.values()) {
        if (!isCandidate(w)) continue;
        let key = null;
        if (manualOf.has(wid(w))) key = "manual|" + manualOf.get(wid(w));
        else {
            try {
                key = autoKey(w);
            } catch (e) {
                api.warn("autoKey failed", e);
            }
            if (key) key = "auto|" + key;
        }
        if (!key) continue;
        if (!buckets.has(key)) buckets.set(key, []);
        buckets.get(key).push(w);
    }

    const next = new Map();
    const nextOf = new Map();
    for (const [key, members] of buckets) {
        if (members.length < 2) continue;
        next.set(key, members);
        const rep = representative(key, members);
        lastUsed.set(key, wid(rep));
        for (const m of members) {
            nextOf.set(wid(m), key);
            setHidden(m, m !== rep);
        }
        // Announce auto groups that appeared or changed.
        const before = groups.get(key);
        const sig = (ms) => ms.map(wid).sort().join(",");
        if (key.startsWith("auto|") && (!before || sig(before) !== sig(members))) {
            osd(ICON_GROUP, "Grouped: " + joinLabels(members));
        }
    }
    for (const w of tracked.values()) if (!nextOf.has(wid(w))) restoreSkip(w);
    for (const key of [...lastUsed.keys()]) if (!next.has(key)) lastUsed.delete(key);
    if (!next.has(activeGroupKey)) activeGroupKey = null;
    groups = next;
    groupOf = nextOf;
}

export function schedule() {
    if (initialized) api.schedule();
}

// --- windows ---------------------------------------------------------------

export function track(w) {
    let id;
    try {
        id = wid(w);
        if (tracked.has(id) || w.specialWindow || !w.managed) return;
    } catch (e) {
        return;
    }
    tracked.set(id, w);
    if (!connected.has(id)) {
        connected.add(id);
        w.tileChanged.connect(() => {
            if (!w.tile) excluded.delete(id);
            schedule();
        });
        w.desktopsChanged.connect(schedule);
        w.outputChanged.connect(schedule);
        w.activitiesChanged.connect(schedule);
        w.quickTileModeChanged.connect(schedule);
        w.minimizedChanged.connect(() => onMinimizedChanged(w));
    }
    schedule();
}

export function untrack(w) {
    let id;
    try {
        id = wid(w);
    } catch (e) {
        return;
    }
    if (pending === w) cancelPending(false);
    for (const set of [tracked, connected, origSkip, manualOf, excluded]) set.delete(id);
    schedule();
}

// Group of a window (dialogs count as their parent's).
function groupFor(w) {
    let target = w;
    try {
        while (target && target.transient && target.transientFor) target = target.transientFor;
    } catch (e) {}
    const key = target && groupOf.get(wid(target));
    return key ? { key, window: target, members: groups.get(key).filter(alive) } : null;
}

// Entering a group from outside (Alt+Tab, taskbar, click from another app)
// brings all its members forward; clicks between members don't.
export function onActivated(w) {
    if (busy || !w) return;
    const hit = groupFor(w);
    if (!hit) {
        activeGroupKey = null;
        return;
    }
    lastUsed.set(hit.key, wid(hit.window));
    if (hit.key !== activeGroupKey) {
        activeGroupKey = hit.key;
        busy = true;
        try {
            const stack = list(ws.stackingOrder);
            const others = hit.members.filter((m) => m !== hit.window)
                .sort((a, b) => stack.indexOf(a) - stack.indexOf(b));
            for (const m of others) {
                if (m.minimized) m.minimized = false;
                ws.raiseWindow(m);
            }
            ws.raiseWindow(hit.window);
        } catch (e) {
            api.warn("raise failed", e);
        } finally {
            busy = false;
        }
    }
    schedule(); // the Alt+Tab entry follows the last used member
}

function onMinimizedChanged(w) {
    if (busy || !cfg.minimizeTogether) return;
    const hit = groupFor(w);
    if (!hit) return;
    busy = true;
    try {
        for (const m of hit.members) if (m.minimized !== w.minimized) m.minimized = w.minimized;
        if (w.minimized) activeGroupKey = null;
    } catch (e) {
        api.warn("minimize sync failed", e);
    } finally {
        busy = false;
    }
}

// --- shortcuts -------------------------------------------------------------

export function cancelPending(announce) {
    if (!pending) return;
    pending = null;
    api.disarmPending();
    if (announce) osd(ICON_INFO, "Link cancelled");
}

// Meta+Space twice: link the window picked first with the focused one.
// Both sides bring their whole group, so A+B then C→B gives A+B+C.
export function linkShortcut() {
    const w = ws.activeWindow;
    if (!isCandidate(w)) {
        osd(ICON_INFO, "This window can't be linked");
        return;
    }
    if (!pending || !alive(pending)) {
        pending = w;
        api.armPending();
        osd(ICON_GROUP, label(w) + " picked · focus another window, Meta+Space again");
        return;
    }
    if (pending === w) {
        cancelPending(true);
        return;
    }
    const sideA = groupFor(pending);
    const sideB = groupFor(w);
    const source = pending;
    cancelPending(false);
    if (sideA && sideB && sideA.key === sideB.key) {
        osd(ICON_INFO, "Already linked");
        return;
    }
    const members = new Set([source, w]);
    for (const side of [sideA, sideB]) if (side) side.members.forEach((m) => members.add(m));

    const gid = nextManualId++;
    for (const m of members) {
        manualOf.set(wid(m), gid);
        excluded.delete(wid(m));
    }
    osd(ICON_GROUP, "Linked: " + joinLabels([...members]));
    reconcile();
}

// Meta+Alt+Space: take the focused window out of its group.
export function unlinkShortcut() {
    const w = ws.activeWindow;
    const hit = w && groupFor(w);
    if (!hit) {
        osd(ICON_INFO, "Not linked");
        return;
    }
    const id = wid(hit.window);
    if (manualOf.has(id)) manualOf.delete(id);
    else excluded.add(id); // auto group: until it leaves the tile
    osd(ICON_UNGROUP, label(hit.window) + " unlinked");
    reconcile();
}

// Meta+Shift+Space: dissolve the focused window's whole group.
export function dissolveShortcut() {
    const hit = groupFor(ws.activeWindow);
    if (!hit) {
        osd(ICON_INFO, "Not linked");
        return;
    }
    for (const m of hit.members) {
        const id = wid(m);
        if (manualOf.has(id)) manualOf.delete(id);
        else excluded.add(id);
    }
    osd(ICON_UNGROUP, "Ungrouped: " + joinLabels(hit.members));
    reconcile();
}

// Meta+Ctrl+Space: next member of the group, left to right.
export function nextShortcut() {
    const hit = groupFor(ws.activeWindow);
    if (!hit) return;
    const members = hit.members.slice().sort((a, b) =>
        a.frameGeometry.x - b.frameGeometry.x || a.frameGeometry.y - b.frameGeometry.y);
    ws.activeWindow = members[(members.indexOf(hit.window) + 1) % members.length];
}

// --- lifecycle -------------------------------------------------------------

export function init(qmlApi) {
    if (initialized) teardown(generation);
    generation++;
    api = qmlApi;
    ws = api.workspace;
    readConfig();
    initialized = true;
    for (const w of list(ws.stackingOrder)) track(w);
    reconcile();
    return generation;
}

export function teardown(gen) {
    if (gen !== generation || !initialized) return;
    initialized = false;
    // Never leave windows hidden from Alt+Tab after we're gone.
    for (const w of tracked.values()) restoreSkip(w);
    for (const c of [tracked, manualOf, excluded, lastUsed]) c.clear();
    groups = new Map();
    groupOf = new Map();
    pending = null;
}

// --- switcher bridge -------------------------------------------------------
//
// The n-switcher Alt+Tab layout runs in the same QQmlEngine and imports this
// file by URL, so it shares this module instance.

export function switcherGroup(windowId) {
    if (!initialized || windowId === undefined || windowId === null) return null;
    const key = groupOf.get(String(windowId));
    const members = key ? groups.get(key).filter(alive) : [];
    return members.length < 2 ? null : { members, label: joinLabels(members) };
}
