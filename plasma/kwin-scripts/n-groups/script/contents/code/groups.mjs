// SPDX-License-Identifier: GPL-2.0-only
//
// n-groups — core logic.
//
//   * A group is a set of >= 2 windows sharing one Alt+Tab entry: only the
//     last used member stays in the switcher, the rest get skipSwitcher.
//   * Groups are only made by hand: Meta+Space opens pick mode (main.qml),
//     or links two windows with the keyboard when pick mode is off. Linking
//     merges the whole groups of every picked window. Groups live in memory.
//
// Every change just calls schedule(); reconcile() rebuilds all groups from
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
const groupIdOf = new Map();  // wid -> group id
const lastUsed = new Map();   // group id -> wid shown in Alt+Tab
let groups = new Map();       // group id -> Window[]
let nextGroupId = 1;
let activeGroupId = null;
let pending = null;           // keyboard linking: window of the first Meta+Space
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

export const joinLabels = (windows) => windows.map(label).join(" + ");

function osd(icon, text) {
    if (cfg.showOsd) api.osd(icon, text);
}

function readConfig() {
    // kwinrc values may come back as bool or as the string "true"/"false".
    const bool = (key) => String(api.readConfig(key, true)) === "true";
    cfg = {
        pickWithMouse: bool("pickWithMouse"),
        minimizeTogether: bool("minimizeTogether"),
        showOsd: bool("showOsd"),
    };
}

export function pickWithMouse() {
    return cfg.pickWithMouse;
}

// --- grouping --------------------------------------------------------------

export function isCandidate(w) {
    try {
        return alive(w) && w.managed && w.normalWindow && !w.transient && !w.specialWindow
            // Already hidden from Alt+Tab by someone else (rules, Yakuake…).
            && (origSkip.has(wid(w)) || !w.skipSwitcher);
    } catch (e) {
        return false;
    }
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

function representative(gid, members) {
    if (members.includes(ws.activeWindow)) return ws.activeWindow;
    const last = members.find((m) => wid(m) === lastUsed.get(gid));
    if (last) return last;
    const stack = list(ws.stackingOrder);
    return members.reduce((top, m) => (stack.indexOf(m) > stack.indexOf(top) ? m : top));
}

export function reconcile() {
    if (!initialized) return;
    const buckets = new Map();
    for (const [id, gid] of groupIdOf) {
        const w = tracked.get(id);
        if (!isCandidate(w)) continue;
        if (!buckets.has(gid)) buckets.set(gid, []);
        buckets.get(gid).push(w);
    }

    const next = new Map();
    for (const [gid, members] of buckets) {
        if (members.length < 2) continue;
        next.set(gid, members);
        const rep = representative(gid, members);
        lastUsed.set(gid, wid(rep));
        for (const m of members) setHidden(m, m !== rep);
    }
    // A group left with one window (the rest closed or unlinked) is gone.
    for (const [id, gid] of [...groupIdOf]) if (!next.has(gid)) groupIdOf.delete(id);
    for (const w of tracked.values()) if (!groupIdOf.has(wid(w))) restoreSkip(w);
    for (const gid of [...lastUsed.keys()]) if (!next.has(gid)) lastUsed.delete(gid);
    if (!next.has(activeGroupId)) activeGroupId = null;
    groups = next;
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
        w.desktopsChanged.connect(schedule);
        w.activitiesChanged.connect(schedule);
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
    for (const set of [tracked, connected, origSkip, groupIdOf]) set.delete(id);
    schedule();
}

// Group of a window (dialogs count as their parent's).
function groupFor(w) {
    let target = w;
    try {
        while (target && target.transient && target.transientFor) target = target.transientFor;
    } catch (e) {}
    const gid = target && groupIdOf.get(wid(target));
    const members = gid !== undefined && groups.has(gid) ? groups.get(gid).filter(alive) : [];
    return members.length ? { gid, window: target, members } : null;
}

// Entering a group from outside (Alt+Tab, taskbar, click from another app)
// brings all its members forward; clicks between members don't.
export function onActivated(w) {
    if (busy || !w) return;
    const hit = groupFor(w);
    if (!hit) {
        activeGroupId = null;
        return;
    }
    lastUsed.set(hit.gid, wid(hit.window));
    if (hit.gid !== activeGroupId) {
        activeGroupId = hit.gid;
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
        if (w.minimized) activeGroupId = null;
    } catch (e) {
        api.warn("minimize sync failed", e);
    } finally {
        busy = false;
    }
}

// --- linking ---------------------------------------------------------------

// Every window that ends up in the group if `windows` are linked: each one
// brings its whole current group along.
export function linkPreview(windows) {
    const out = [];
    for (const w of windows) {
        const hit = groupFor(w);
        for (const m of hit ? hit.members : [w]) if (!out.includes(m)) out.push(m);
    }
    return out;
}

// Links `windows` (and their groups) into one group. Returns its members,
// or null if there was nothing to link.
export function linkWindows(windows) {
    const picked = windows.filter(isCandidate);
    const members = linkPreview(picked);
    if (members.length < 2) {
        osd(ICON_INFO, "Pick at least two windows");
        return null;
    }
    const groupIds = new Set(members.map((m) => groupIdOf.get(wid(m))));
    if (groupIds.size === 1 && !groupIds.has(undefined)) {
        osd(ICON_INFO, "Already linked");
        return null;
    }
    const gid = nextGroupId++;
    for (const m of members) groupIdOf.set(wid(m), gid);
    reconcile();
    osd(ICON_GROUP, "Linked: " + joinLabels(members));
    api.flash(members.map(wid));
    return members;
}

// Pick mode: the top-most window under global point (x, y) that can be
// linked, on the current desktop and activity. `ignore` is a caption to skip
// (the pick overlay itself).
export function windowAt(x, y, ignore) {
    const stack = list(ws.stackingOrder);
    for (let i = stack.length - 1; i >= 0; i--) {
        const w = stack[i];
        try {
            if (w.caption === ignore || w.minimized || !isCandidate(w)) continue;
            const desktops = list(w.desktops);
            if (!w.onAllDesktops && !desktops.includes(ws.currentDesktop)) continue;
            const acts = list(w.activities);
            if (acts.length && !acts.includes(ws.currentActivity)) continue;
            const g = w.frameGeometry;
            if (x >= g.x && x < g.x + g.width && y >= g.y && y < g.y + g.height) return w;
        } catch (e) {}
    }
    return null;
}

// --- shortcuts -------------------------------------------------------------

export function cancelPending(announce) {
    if (!pending) return;
    pending = null;
    api.disarmPending();
    if (announce) osd(ICON_INFO, "Link cancelled");
}

// Keyboard linking (pick mode off): Meta+Space on one window, then on another.
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
    const first = pending;
    cancelPending(false);
    linkWindows([first, w]);
}

// Meta+Shift+Space: take the focused window out of its group.
export function unlinkShortcut() {
    const hit = groupFor(ws.activeWindow);
    if (!hit) {
        osd(ICON_INFO, "Not linked");
        return;
    }
    groupIdOf.delete(wid(hit.window));
    osd(ICON_UNGROUP, label(hit.window) + " unlinked");
    reconcile();
}

// No default key: dissolve the focused window's whole group.
export function dissolveShortcut() {
    const hit = groupFor(ws.activeWindow);
    if (!hit) {
        osd(ICON_INFO, "Not linked");
        return;
    }
    for (const m of hit.members) groupIdOf.delete(wid(m));
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
    for (const c of [tracked, groupIdOf, lastUsed]) c.clear();
    groups = new Map();
    pending = null;
}

// --- switcher bridge -------------------------------------------------------
//
// The n-switcher Alt+Tab layout runs in the same QQmlEngine and imports this
// file by URL, so it shares this module instance.

export function switcherGroup(windowId) {
    if (!initialized || windowId === undefined || windowId === null) return null;
    const gid = groupIdOf.get(String(windowId));
    const members = gid !== undefined && groups.has(gid) ? groups.get(gid).filter(alive) : [];
    return members.length < 2 ? null : { members, label: joinLabels(members) };
}
