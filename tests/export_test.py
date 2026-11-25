# Export / import: one text with settings, profiles, enemies (phone links only when ticked); read back safely;
# a cut text is refused; settings replaced, enemies merged. Each character keeps its own profile.
import sys
from harness import load, errors

lua, ex, ev = load()
fails = []
def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)
    if not cond: fails.append(what)

ex(r'''
NS.db.discordWebhook = "https://discord.com/api/webhooks/secret"
NS.db.enemies["Ryu-X"] = { name = "Ryu Jiin", class = "ROGUE", level = 39, kos = true, note = "camps the FP", kills = 2 }
NS.db.nearbyMax = 14
NS.db.rebuff = { MAGE = { "Ice Armor / Frost Armor" } }
NS.db.sounds = { kos = "horn" }
NS.db.someFloat = 0.1 + 0.2
NS.db.unicode = "Rævdilter – Sotrøyr ✓ |cffff0000red|r"
TEXT = NS.MakeExport({ settings = true, enemies = true })
''')
text = str(ev('TEXT'))
print("    export:", len(text), "chars:", text[:40] + "...")
check(text.startswith("WATCHX1:") and "|" not in text and "\n" not in text, "one line, no | (the chat box reads those)")
ex('EXP = NS.ReadExport(TEXT)')
check(ev('EXP ~= nil'), "it reads back")
check(ev('EXP.data.nearbyMax') == 14 and ev('EXP.data.sounds.kos') == "horn" and ev('EXP.data.rebuff.MAGE[1]') == "Ice Armor / Frost Armor", "settings, sounds, rebuffs")
check(ev('EXP.data.someFloat == 0.1 + 0.2'), "numbers exactly")
check(ev('EXP.data.unicode') == "Rævdilter – Sotrøyr ✓ |cffff0000red|r", "any text (UTF-8, colour codes)")
check(ev('EXP.data.enemies["Ryu-X"].note') == "camps the FP", "enemies with notes")
check(ev('EXP.data.discordWebhook == nil'), "phone links: not unless ticked")
check(ev('EXP.data.roles == nil and EXP.data.log == nil'), "caches and logs: never")
ex('T2 = NS.ReadExport(NS.MakeExport({ secrets = true }))')
check(ev('T2.data.discordWebhook') == "https://discord.com/api/webhooks/secret" and ev('T2.data.nearbyMax == nil'), "only phone links, when that's all that's ticked")
# a cut or changed text is refused
ex('A, WHY = NS.ReadExport(TEXT:sub(1, #TEXT - 20))')
check(ev('A == nil') and "cut" in str(ev('WHY')), "a cut text: refused – " + str(ev('WHY')))
ex('A, WHY = NS.ReadExport("hello"); B = NS.ReadExport("return os.exit()")')
check(ev('A == nil and B == nil'), "anything else: refused (never run)")
ex('local mid = math.floor(#TEXT / 2); local ch = TEXT:sub(mid, mid) == "A" and "B" or "A"; C = NS.ReadExport(TEXT:sub(1, mid - 1) .. ch .. TEXT:sub(mid + 1))')
check(ev('C == nil'), "a changed letter: refused")
# import: settings replaced, enemies merged
ex(r'''
NS.db.nearbyMax = 5
NS.db.enemies["Ryu-X"] = { name = "Ryu Jiin", class = "ROGUE", level = 40, kills = 5 }
NS.db.enemies["New-X"] = { name = "New Guy", class = "MAGE", level = 30 }
N = NS.ApplyExport(EXP)
''')
check(ev('NS.db.nearbyMax') == 14, "settings: the export's")
check(ev('NS.db.enemies["Ryu-X"].kos') and ev('NS.db.enemies["Ryu-X"].note') == "camps the FP" and ev('NS.db.enemies["Ryu-X"].kills') == 5,
      "a player you both have: KOS and note added, the higher count kept")
check(ev('NS.db.enemies["New-X"] ~= nil'), "players only you have: kept")
check(ev('NS.db.discordWebhook') == "https://discord.com/api/webhooks/secret", "your phone link: untouched (not in the export)")
# the window
ex('NS.ShowExport(); WatchXExport.box:SetText(TEXT); WatchXExport.imp:GetScript("OnClick")(WatchXExport.imp)')
check("Click again" in str(ev('WatchXExport.status:GetText()')), "import: says what's in it first – " + str(ev('WatchXExport.status:GetText()'))[:90])
ex('WatchXExport.imp:GetScript("OnClick")(WatchXExport.imp)')
check("Imported" in str(ev('WatchXExport.status:GetText()')), "the second click imports")
# each character its own profile
ex(r'''
NS.NewProfile("Rogue PvP")
UnitName = function() return "Othertoon" end
NS.SwitchProfile("Camping")
UnitName = function() return "Rikerud" end
''')
check(ev('NS.db.charProfile["Rikerud-" .. tostring(GetRealmName())]') == "Rogue PvP"
      and ev('NS.db.charProfile["Othertoon-" .. tostring(GetRealmName())]') == "Camping", "each character remembers its own profile")
ex('NS.InitProfiles()')
check(ev('NS.db.profile') == "Rogue PvP", "logging in on a character: its profile")
errs = errors(ev)
check(len(errs) == 0, "no Lua errors " + (str(errs[0])[:300] if errs else ""))
print("export:", "ALL PASSED" if not fails else "%d FAILED" % len(fails))
sys.exit(1 if fails else 0)
