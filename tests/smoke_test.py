# Every file loads, then login, slash commands, a fight, bags/auras/XP/quests/mail events and logout: no Lua errors.
import sys
from harness import load, errors

lua, ex, ev = load()
for c in ["", "mem", "mem reset", "auras", "rares", "wanted", "xp", "buffs", "nearby test", "help", "list",
          "lock", "unlock", "lock"]:
    ex('local ok, err = pcall(SlashCmdList.WATCHX, %r) if not ok then ERRS[#ERRS+1] = "/wx %s: " .. tostring(err) end' % (c, c))
ex('tick(5)')
ex('fire("PLAYER_REGEN_DISABLED"); COMBAT=true; INFIGHT=true; tick(3); COMBAT=false; INFIGHT=false; fire("PLAYER_REGEN_ENABLED"); tick(5)')
ex('fire("BAG_UPDATE_DELAYED"); fire("UNIT_AURA", "player"); fire("PLAYER_XP_UPDATE", "player"); fire("QUEST_LOG_UPDATE"); '
   'fire("MAIL_SHOW"); fire("MAIL_CLOSED"); tick(3)')
ex('fire("PLAYER_LOGOUT")')
errs = errors(ev)
seen = []
for e in errs:
    if e not in seen: seen.append(e)
for e in seen[:20]: print(" -", e[:300])
print("smoke: errors:", len(errs))
sys.exit(1 if errs else 0)
