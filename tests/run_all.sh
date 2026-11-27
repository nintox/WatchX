#!/bin/bash
# All tests. Needs Python 3 with lupa: PY=/path/to/python bash tests/run_all.sh (default: python3)
cd "$(dirname "$0")"
PY="${PY:-python3}"
fail=0
"$PY" - <<'PYEOF' || fail=1
import lupa.lua51 as L
lua = L.LuaRuntime()
comp = lua.eval("function(s, n) local f, e = loadstring(s, n) return f ~= nil, e end")
for f in ("../WatchX.lua", "../UI.lua", "../Scrolls.lua", "../Data/Rares.lua"):
    ok, err = comp(open(f, encoding="utf-8").read(), f)
    print(("compile ok   " if ok else "COMPILE FAIL ") + f + ("" if ok else ": " + str(err)))
    if not ok: raise SystemExit(1)
PYEOF
for t in smoke_test combat_test warnings_test eating_test names_news_test announce_test multikill_test xpfood_test names_gate_test sounds_test camp_test food_test share_test xprate_test rebuff_test export_test ownbounty_test size_test settings_test rebuffgroups_test combattext_test minibar_test scrolls_test potions_test layout_test blizzxp_test combo_test swing_test; do
    out="$("$PY" "$t.py" 2>&1)"
    if [ $? -eq 0 ]; then echo "pass  $(printf '%s' "$out" | tail -n 1)"; else echo "FAIL  $t"; printf '%s\n' "$out" | grep -v "^ok" | tail -n 15; fail=1; fi
done
for f in ../bridge/watchx_bridge.sh "../bridge/Install (Mac).command"; do bash -n "$f" || fail=1; done
out="$(bash cloudsync_test.sh 2>&1)"
if [ $? -eq 0 ]; then echo "pass  $(printf '%s' "$out" | tail -n 1)"; else echo "FAIL  cloudsync_test"; printf '%s\n' "$out" | grep -v "^ok"; fail=1; fi
[ $fail = 0 ] && echo "bash -n ok – all passed"
exit $fail
