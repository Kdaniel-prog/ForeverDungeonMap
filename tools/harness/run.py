"""Headless test harness for the ForeverDungeonMap WoW addon.

Runs the addon inside an embedded Lua 5.1 (lupa) with a WoW API mock
(wowmock.lua), then runs one or more scenario files and prints a report:
Lua errors with tracebacks, protected-call (taint) violations, reads of
undefined globals, unknown widget methods, layout checks.

Usage (from the repo root):
    python -I tools/harness/run.py [options] [scenario.lua ...]

Options:
    --legacy            also provide the deprecated globals GetItemInfo, GetItemInfoInstant,
                        GetItemQualityColor, IsQuestFlaggedCompleted, GetQuestLogIndexByID.
                        Default is the WoW Forever 1.60.1 profile: they are absent (the client's
                        Logs/General.log shows "Canvas.lua:152: attempt to call a nil value
                        [C]: in function 'GetItemInfo'"); only C_Item / C_QuestLog exist.
    --combat            run the scenario in combat (InCombatLockdown() == true)
    --forbid-passthrough  treat SetPassThroughButtons as forbidden for insecure code
    --no-cleu           COMBAT_LOG_EVENT_UNFILTERED is not a valid event on this client
    --missing-font NAME pretend a font object does not exist (repeatable)
    --addon DIR         addon folder (default ForeverDungeonMap)
    --verbose           print full tracebacks and the mock log
    --json FILE         also write the report as JSON

The lupa package is looked up in $FDM_PYLIB (or the scratchpad pylib dir
used during development) in addition to the normal sys.path.
Exit code: 0 = no errors and all checks passed, 1 otherwise.
"""
import argparse
import json
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))

for extra in (os.environ.get("FDM_PYLIB"),
              r"C:\Users\danie\AppData\Local\Temp\claude\ae3436fc44b8d2fc\31185359-c043-41ff-8559-d7f6c79cfb0e\scratchpad\pylib"):
    if extra and os.path.isdir(extra) and extra not in sys.path:
        sys.path.insert(0, extra)

try:
    import lupa.lua51 as lupa_mod  # WoW runs Lua 5.1
except ImportError:  # pragma: no cover
    sys.exit("lupa not found: python -m pip install --target <dir> lupa ; set FDM_PYLIB=<dir>")


# ---------------------------------------------------------------------------
# Python -> Lua literal
# ---------------------------------------------------------------------------

def lua_literal(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return "\"" + v.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\""
    if isinstance(v, (list, tuple)):
        return "{" + ", ".join(lua_literal(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join("[%s] = %s" % (lua_literal(k), lua_literal(x)) for k, x in v.items()) + "}"
    raise TypeError(type(v))


# ---------------------------------------------------------------------------
# XML (FrameXML subset)
# ---------------------------------------------------------------------------

def _tag(e):
    return e.tag.split("}")[-1]


def _bool(s):
    return str(s).lower() == "true"


def _num(s, default=0):
    try:
        return float(s)
    except (TypeError, ValueError):
        return default


def _size(e):
    for c in e:
        if _tag(c) == "Size":
            d = {"x": _num(c.get("x")), "y": _num(c.get("y"))}
            for a in c:
                if _tag(a) == "AbsDimension":
                    d = {"x": _num(a.get("x")), "y": _num(a.get("y"))}
            return d
    return None


def _anchors(e):
    out = []
    for c in e:
        if _tag(c) == "Anchors":
            for a in c:
                if _tag(a) != "Anchor":
                    continue
                d = {"point": a.get("point"), "relativePoint": a.get("relativePoint"),
                     "x": _num(a.get("x")), "y": _num(a.get("y")), "relativeKey": a.get("relativeKey"),
                     "relativeTo": a.get("relativeTo")}
                for off in a:
                    if _tag(off) == "Offset":
                        for ad in off:
                            if _tag(ad) == "AbsDimension":
                                d["x"], d["y"] = _num(ad.get("x")), _num(ad.get("y"))
                out.append({k: v for k, v in d.items() if v is not None})
    return out


def parse_frame(e):
    d = {"name": e.get("name"), "type": _tag(e), "mixin": e.get("mixin"), "inherits": e.get("inherits"),
         "virtual": _bool(e.get("virtual")), "enableMouse": _bool(e.get("enableMouse")),
         "parent": e.get("parent"), "hidden": _bool(e.get("hidden")),
         "size": _size(e), "anchors": _anchors(e), "regions": [], "scripts": {}}
    for c in e:
        t = _tag(c)
        if t == "Layers":
            for layer in c:
                lvl = layer.get("level", "ARTWORK")
                for r in layer:
                    rt = _tag(r)
                    if rt not in ("Texture", "FontString", "MaskTexture"):
                        continue
                    rd = {"kind": "Texture" if rt != "FontString" else "FontString", "layer": lvl,
                          "sublevel": int(layer.get("textureSubLevel")) if layer.get("textureSubLevel") else None,
                          "name": r.get("name"), "parentKey": r.get("parentKey"), "file": r.get("file"),
                          "atlas": r.get("atlas"), "alphaMode": r.get("alphaMode"), "hidden": _bool(r.get("hidden")),
                          "setAllPoints": _bool(r.get("setAllPoints")), "inherits": r.get("inherits"),
                          "text": r.get("text"), "size": _size(r), "anchors": _anchors(r)}
                    for rc in r:
                        if _tag(rc) == "Color":
                            rd["color"] = {k: _num(rc.get(k), 1) for k in ("r", "g", "b", "a")}
                    d["regions"].append({k: v for k, v in rd.items() if v is not None})
        elif t == "Scripts":
            for s in c:
                sd = {"method": s.get("method"), "func": s.get("function"), "inherit": s.get("inherit")}
                if (s.text or "").strip():
                    sd["body"] = s.text
                d["scripts"][_tag(s)] = {k: v for k, v in sd.items() if v is not None}
    return {k: v for k, v in d.items() if v is not None}


FRAME_TAGS = {"Frame", "Button", "CheckButton", "ScrollFrame", "EditBox", "Slider", "StatusBar"}


def load_xml(lua, path, addon_dir, addon_name, ns, loader):
    chunk = "@" + addon_name + "/" + os.path.relpath(path, addon_dir).replace("\\", "/")
    tree = ET.parse(path)
    for e in tree.getroot():
        t = _tag(e)
        if t == "Script" and e.get("file"):
            loader(os.path.join(os.path.dirname(path), e.get("file").replace("\\", os.sep)))
        elif t == "Include" and e.get("file"):
            loader(os.path.join(os.path.dirname(path), e.get("file").replace("\\", os.sep)))
        elif t in FRAME_TAGS:
            d = parse_frame(e)
            # inline script bodies become functions
            body_defs = []
            for sname, s in d["scripts"].items():
                if "body" in s:
                    body_defs.append((sname, s.pop("body")))
            src = "local def = %s\n" % lua_literal(d)
            for sname, body in body_defs:
                src += "def.scripts[%s] = { inline = true }\n" % lua_literal(sname)
                src += "def.scripts[%s].fnsrc = %s\n" % (lua_literal(sname), lua_literal(body))
            src += ("for k, s in pairs(def.scripts) do if s.fnsrc then "
                    "local f = assert(loadstring('return function(self, ...) ' .. s.fnsrc .. ' end', '" +
                    chunk + "')) s.func = nil; s.fn = f() end end\n")
            src += "if def.virtual then MOCK.RegisterXmlTemplate(def) else MOCK.CreateXmlFrame(def) end\n"
            fn = lua.eval("function(src, name) return loadstring(src, name) end")(src, chunk)
            lua.globals().MOCK.SafeCall(fn)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main():
    # translated texts must not crash a console that is not UTF-8
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser()
    ap.add_argument("scenarios", nargs="*")
    ap.add_argument("--legacy", action="store_true")
    ap.add_argument("--locale", help="client locale, e.g. deDE (default enUS)")
    ap.add_argument("--combat", action="store_true")
    ap.add_argument("--forbid-passthrough", action="store_true")
    ap.add_argument("--no-cleu", action="store_true")
    ap.add_argument("--missing-font", action="append", default=[])
    ap.add_argument("--addon", default="ForeverDungeonMap")
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--json")
    args = ap.parse_args()

    addon_dir = args.addon if os.path.isabs(args.addon) else os.path.join(REPO, args.addon)
    addon_name = os.path.basename(addon_dir.rstrip("\\/"))
    scenarios = args.scenarios or [os.path.join(HERE, "scenario.lua")]

    lua = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    cfg = lua.table_from({
        "legacy": args.legacy, "locale": args.locale, "passThroughForbidden": args.forbid_passthrough, "noCLEU": args.no_cleu,
        "missingFonts": lua.table_from(args.missing_font),
    })
    g.MOCK = lua.table_from({"config": cfg, "addonSourcePattern": addon_name + "/"})

    def run_file(path, chunk, *call_args):
        with open(path, encoding="utf-8") as f:
            src = f.read()
        loader = lua.eval("""function(src, chunk, ...)
            local fn, err = loadstring(src, chunk)
            if not fn then MOCK.RecordError(err, "(syntax)") return false end
            local prev = MOCK.context
            MOCK.context = "loading " .. chunk
            local ok = MOCK.Dispatch(fn, ...)
            MOCK.context = prev
            return ok
        end""")
        return loader(src, chunk, *call_args)

    with open(os.path.join(HERE, "wowmock.lua"), encoding="utf-8") as f:
        mock_fn = lua.eval("function(src) return assert(loadstring(src, '@tools/harness/wowmock.lua')) end")(f.read())
    mock_fn()
    run_file(os.path.join(HERE, "checks.lua"), "@tools/harness/checks.lua")
    lua.execute("""
    function MOCK.CreateXmlFrame(def)
        local parent = def.parent and _G[def.parent] or UIParent
        local f = CreateFrame(def.type, def.name, parent, def.inherits)
        MOCK.ApplyXmlTemplate(f, def)
        if def.hidden then f:Hide() end
        if f._scripts and f._scripts.OnLoad then MOCK.FireScript(f, "OnLoad") end
    end
    """)
    # inline <Scripts> bodies
    lua.execute("""
    local apply = MOCK.ApplyXmlTemplate
    function MOCK.ApplyXmlTemplate(f, def)
        apply(f, def)
        for script, s in pairs(def.scripts or {}) do
            if s.fn then f._scripts = f._scripts or {}; f._scripts[script] = s.fn end
        end
    end
    """)
    g.MOCK.Sandbox()

    ns = lua.table()
    g.MOCK.ns = ns
    g.MOCK.addonName = addon_name

    toc = None
    for fn in os.listdir(addon_dir):
        if fn.lower() == (addon_name + ".toc").lower():
            toc = os.path.join(addon_dir, fn)
    if not toc:
        sys.exit("no .toc in " + addon_dir)

    def load_any(path):
        rel = addon_name + "/" + os.path.relpath(path, addon_dir).replace("\\", "/")
        if not os.path.exists(path):
            g.MOCK.RecordError("file listed in toc not found: " + rel, "")
            return
        if path.lower().endswith(".lua"):
            run_file(path, "@" + rel, addon_name, ns)
        elif path.lower().endswith(".xml"):
            load_xml(lua, path, addon_dir, addon_name, ns, load_any)

    # syntax check of every .lua file in the addon (also files not listed in the toc)
    parse = lua.eval("function(src, chunk) local f, err = loadstring(src, chunk) return err end")
    nfiles = 0
    for root, _, files in os.walk(addon_dir):
        for fn in sorted(files):
            if fn.lower().endswith(".lua"):
                path = os.path.join(root, fn)
                with open(path, encoding="utf-8") as f:
                    err = parse(f.read(), "@" + addon_name + "/" + os.path.relpath(path, addon_dir).replace("\\", "/"))
                nfiles += 1
                if err:
                    g.MOCK.RecordError("SYNTAX: " + str(err), "(syntax check)")
    g.MOCK.syntaxChecked = nfiles

    saved_vars = []
    with open(toc, encoding="utf-8-sig") as f:
        for line in f:
            line = line.strip()
            if line.startswith("## SavedVariables:"):
                saved_vars = [s.strip() for s in line.split(":", 1)[1].split(",")]
            if not line or line.startswith("#"):
                continue
            load_any(os.path.join(addon_dir, line.replace("\\", os.sep)))

    g.MOCK.savedVariables = lua.table_from(saved_vars)
    g.MOCK.combat = args.combat

    for sc in scenarios:
        path = sc if os.path.isabs(sc) else os.path.join(os.getcwd(), sc)
        if not os.path.exists(path):
            path = os.path.join(HERE, sc)
        run_file(path, "@tools/harness/" + os.path.basename(path), addon_name, ns)

    return report(lua, args)


def lua_to_py(v, depth=0):
    if depth > 8:
        return "..."
    if hasattr(v, "items") and type(v).__name__ == "_LuaTable":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_py(v[k], depth + 1) for k in sorted(keys)]
        return {str(k): lua_to_py(x, depth + 1) for k, x in v.items()}
    return v


# Lua code that drops UTF-8 sequences cut in half (string.sub in details) so Python can decode them.
SANITIZE = """
function(root)
    -- keep valid UTF-8 sequences, replace broken bytes with "?"
    local function Fix(text)
        local out, i = {}, 1
        while i <= #text do
            local byte = text:byte(i)
            local need = byte < 128 and 1 or byte >= 240 and 4 or byte >= 224 and 3 or byte >= 192 and 2 or 0
            local ok = need > 0 and i + need - 1 <= #text
            for k = i + 1, i + need - 1 do
                local continuation = text:byte(k)
                if ok and (continuation < 128 or continuation > 191) then ok = false end
            end
            if ok then out[#out + 1] = text:sub(i, i + need - 1); i = i + need
            else out[#out + 1] = "?"; i = i + 1 end
        end
        return table.concat(out)
    end
    local seen = {}
    local function Walk(value)
        if type(value) ~= "table" or seen[value] then return end
        seen[value] = true
        for key, item in pairs(value) do
            if type(item) == "string" then value[key] = Fix(item) else Walk(item) end
        end
    end
    Walk(root)
end
"""


def report(lua, args):
    lua.eval(SANITIZE)(lua.globals().MOCK.report)
    R = lua_to_py(lua.globals().MOCK.report)
    out = []
    p = out.append
    errors = R.get("errors") or []
    if isinstance(errors, dict):
        errors = list(errors.values())
    p("=" * 78)
    p("LUA ERRORS: %d" % len(errors))
    for e in errors:
        p("-" * 78)
        p("[x%s] %s" % (e.get("count"), e.get("msg")))
        if e.get("context"):
            p("  during: %s" % e.get("context"))
        trace = e.get("trace") or ""
        lines = [l for l in str(trace).splitlines() if l.strip() and "stack traceback" not in l]
        if not args.verbose:
            lines = [l for l in lines if "[C]" not in l and "harness/run" not in l][:8]
        for l in lines:
            p("    " + l.strip())

    prot = R.get("protected") or []
    if isinstance(prot, dict):
        prot = list(prot.values())
    p("=" * 78)
    p("PROTECTED CALLS FROM TAINTED EXECUTION: %d" % len(prot))
    seen = {}
    for x in prot:
        key = (x.get("event"), x.get("func"), x.get("where"), x.get("context"))
        seen[key] = seen.get(key, 0) + 1
    for (ev, fn, where, ctx), n in seen.items():
        p("  %s %s x%d  first addon frame: %s  during: %s" % (ev, fn, n, where, ctx))

    checks = R.get("checks") or []
    if isinstance(checks, dict):
        checks = list(checks.values())
    failed = [c for c in checks if not c.get("ok")]
    p("=" * 78)
    p("CHECKS: %d passed, %d failed" % (len(checks) - len(failed), len(failed)))
    for c in failed:
        p("  FAIL %s: %s" % (c.get("name"), c.get("detail") or ""))
    if args.verbose:
        for c in checks:
            if c.get("ok"):
                p("  ok   %s %s" % (c.get("name"), c.get("detail") or ""))

    mg = R.get("missingGlobals") or {}
    p("=" * 78)
    p("UNDEFINED GLOBALS READ BY ADDON CODE (guarded probes are expected): %d" % len(mg))
    for name in sorted(mg):
        locs = mg[name]
        p("  %-32s %s" % (name, ", ".join(sorted(locs))[:150]))

    uk = R.get("unknownKeys") or {}
    p("=" * 78)
    p("UNKNOWN WIDGET KEYS READ BY ADDON CODE (nil in the mock): %d" % len(uk))
    for name in sorted(uk):
        p("  %-40s %s" % (name, ", ".join(sorted(uk[name]))[:140]))

    gw = R.get("globalsWritten") or {}
    p("=" * 78)
    p("GLOBALS WRITTEN BY ADDON: %s" % ", ".join("%s (%s)" % (k, v) for k, v in sorted(gw.items())))

    log = R.get("log") or []
    if isinstance(log, dict):
        log = list(log.values())
    p("=" * 78)
    p("MOCK LOG: %d entries" % len(log))
    shown = log if args.verbose else log[:40]
    for l in shown:
        p("  " + str(l))
    prints = R.get("prints") or []
    if isinstance(prints, dict):
        prints = list(prints.values())
    if prints:
        p("CHAT OUTPUT:")
        for l in prints[:30]:
            p("  " + str(l))
    print("\n".join(out))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(R, f, indent=1, default=str)
    return 1 if errors or failed or prot else 0


if __name__ == "__main__":
    sys.exit(main())
