-- ============================================================================
-- The only thing you should ever need to edit in this file. Leave as-is if
-- the relay (server/server.js) runs on this same machine, which is the
-- normal setup -- only change this if you're running the relay elsewhere.
local RELAY_HOST = "127.0.0.1"
local RELAY_PORT = 8765
-- ============================================================================

local ADDR_BATTLE_TYPE_FLAGS = 0x02022FEC
-- gMain.inBattle: a single bit that's TRUE exactly while a battle is running, FALSE otherwise.
-- More reliable than gBattleTypeFlags, which never gets cleared back to 0 when a battle ends.
local ADDR_GMAIN_IN_BATTLE = 0x030026F9
local MASK_GMAIN_IN_BATTLE = 0x02

-- gTrainers: the ROM's trainer table (struct Trainer, 0x28 bytes each). Read-only in practice --
-- ROM can't be written through this scripting API, so trainer names are swapped in the printed
-- text buffer instead (see substitutePlayer1TrainerName) rather than in this table directly.
local ADDR_GTRAINERS = 0x08310030
local TRAINER_STRUCT_SIZE = 0x28
local TRAINER_NAME_OFFSET = 0x04
local TRAINER_NAME_MAX_CHARS = 11
local ADDR_TRAINER_BATTLE_OPPONENT_A = 0x02038BCA -- current opponent trainer's ID

local ADDR_OPPONENT_HANDLE_CHOOSE_ACTION = 0x08061F9C -- AI decides fight/switch/item
local ADDR_OPPONENT_HANDLE_CHOOSE_POKEMON = 0x08062188 -- AI picks which mon to switch to
local ADDR_SHOULD_SWITCH = 0x08063614
local ADDR_GET_MOST_SUITABLE_MON = 0x08063A90
local ADDR_SHOULD_USE_ITEM = 0x08063EE0
local ADDR_HANDLE_TURN_ACTION_SELECTION = 0x0803BE74
local ADDR_GBATTLE_BUFFER_B1 = 0x02023A64 -- gBattleBufferB[1], the enemy's buffer
local ADDR_BATTLE_COMMUNICATION_1 = 0x02024333 -- gBattleCommunication[1] (enemy)

-- gBattleMons[0]/[1] (struct BattlePokemon): the active player/enemy mon, already decrypted by
-- the game. moves[4] u16 @ +0x0C, pp[4] u8 @ +0x24, species u16 @ +0x00, hp u16 @ +0x28,
-- level u8 @ +0x2A, maxHp u16 @ +0x2C.
local ADDR_ENEMY_ACTIVE = 0x020240DC
local ADDR_PLAYER_ACTIVE = 0x02024084
local ADDR_ENEMY_MOVES = 0x020240E8
local ADDR_ENEMY_PP = 0x02024100

-- gEnemyParty (struct Pokemon[6], 0x64 bytes each). Species is encrypted with a per-mon key
-- derived from personality/OT ID; level/hp/maxHp are not.
local ADDR_GENEMY_PARTY = 0x02024744
local ADDR_ENEMY_PARTY_INDEX = 0x02024070 -- which party slot is currently active (u16)
local PARTY_MON_SIZE = 0x64
local PARTY_SIZE = 6

-- Which of the 4 encrypted substructures (Growth/Attacks/EVs/Misc) holds Growth data, indexed by
-- personality % 24. From Bulbapedia's Gen 3 substructure order table.
local GROWTH_SLOT_BY_PID24 = {
    [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0,
    [6] = 1, [7] = 1,
    [8] = 2, [9] = 3, [10] = 2, [11] = 3,
    [12] = 1, [13] = 1,
    [14] = 2, [15] = 3, [16] = 2, [17] = 3,
    [18] = 1, [19] = 1,
    [20] = 2, [21] = 3, [22] = 2, [23] = 3,
}

local RECONNECT_INTERVAL_FRAMES = 120 -- ~2s at 60fps

local STATE_WAIT_ACTION_CASE_CHOSEN = 3
local PLAYER_BATTLER_INDEX = 0
local CONTROLLER_TWORETURNVALUES = 33
local B_ACTION_EXEC_SCRIPT = 10
local B_ACTION_SWITCH = 2
local BATTLE_TYPE_TRAINER = 0x8
local HEARTBEAT_INTERVAL_FRAMES = 30

-- Used only for the battle log (detecting what each battler just did), not for injection.
local ADDR_CHOSEN_MOVE_BY_BATTLER = 0x02024274
local ADDR_CHOSEN_ACTION_BY_BATTLER = 0x0202421C
local ADDR_BATTLER_PARTY_INDEX_0 = 0x0202406E
local ADDR_BATTLE_COMMUNICATION_0 = 0x02024332
local B_ACTION_USE_MOVE = 0

local ADDR_SAVE_BLOCK2_PTR = 0x03005D90 -- gSaveBlock2Ptr->playerName lives at the start of this
local PLAYER_NAME_LENGTH = 7
local GEN3_STRING_TERMINATOR = 0xFF

-- Gen 3 games don't use ASCII -- every string is its own custom byte encoding. These two tables
-- convert between that encoding and normal Lua strings, covering letters, digits, space, and a
-- handful of common punctuation marks (values from pret's charmap.txt).
local GEN3_CHARMAP = { [0x00] = " " }
local GEN3_ENCODE_MAP = { [" "] = 0x00 }
do
    local digits = "0123456789"
    for i = 1, #digits do
        local byte = 0xA0 + i
        GEN3_CHARMAP[byte] = digits:sub(i, i)
        GEN3_ENCODE_MAP[digits:sub(i, i)] = byte
    end
    local upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    for i = 1, #upper do
        local byte = 0xBA + i
        GEN3_CHARMAP[byte] = upper:sub(i, i)
        GEN3_ENCODE_MAP[upper:sub(i, i)] = byte
    end
    local lower = "abcdefghijklmnopqrstuvwxyz"
    for i = 1, #lower do
        local byte = 0xD4 + i
        GEN3_CHARMAP[byte] = lower:sub(i, i)
        GEN3_ENCODE_MAP[lower:sub(i, i)] = byte
    end
    local punctuation = { ["!"] = 0xAB, ["?"] = 0xAC, ["."] = 0xAD, ["-"] = 0xAE, [","] = 0xB8, ["'"] = 0xB4 }
    for char, byte in pairs(punctuation) do
        GEN3_CHARMAP[byte] = char
        GEN3_ENCODE_MAP[char] = byte
    end
end
local playerNameSent = false

local function encodeGen3Bytes(text, maxChars)
    local bytes = {}
    for i = 1, math.min(#text, maxChars) do
        bytes[i] = GEN3_ENCODE_MAP[text:sub(i, i)] or 0x00 -- unencodable chars fall back to a space
    end
    bytes[#bytes + 1] = GEN3_STRING_TERMINATOR
    return bytes
end

-- Draws a message into the game's own battle text box (the same one used for "Foe used Tackle!"
-- etc.), by writing encoded text into its scratch buffer and jumping into the same drawing
-- function the game itself calls to display it.
local ADDR_BATTLE_PUT_TEXT_ON_WINDOW = 0x0814F9EC
local ADDR_DISPLAYED_STRING_BATTLE = 0x02022E2C -- gDisplayedStringBattle, scratch text buffer
local ADDR_BATTLE_BG0_X = 0x02022E14
local ADDR_BATTLE_BG0_Y = 0x02022E16
local B_WIN_MSG = 0 -- window ID for the main battle message box
local BATTLE_MESSAGE_MAX_CHARS = 40 -- the window wraps longer text onto a second line itself

local function showBattleMessage(text)
    local bytes = encodeGen3Bytes(text, BATTLE_MESSAGE_MAX_CHARS)
    for i, byte in ipairs(bytes) do
        emu:write8(ADDR_DISPLAYED_STRING_BATTLE + i - 1, byte)
    end
    emu:write16(ADDR_BATTLE_BG0_X, 0)
    emu:write16(ADDR_BATTLE_BG0_Y, 0)
    emu:writeRegister("r0", ADDR_DISPLAYED_STRING_BATTLE)
    emu:writeRegister("r1", B_WIN_MSG)
    emu:writeRegister("pc", ADDR_BATTLE_PUT_TEXT_ON_WINDOW)
end

-- Takes a screenshot of the game to disk periodically, for the web UI's "stream" view when no
-- trainer battle is in progress. Uses screenshotToImage()+Image:save() rather than the simpler
-- emu:screenshot() since the latter fails silently on some platforms.
local SCREENSHOT_PATH = "C:/Users/jonas/Desktop/PokePVP/server/public/screen.png"
local SCREENSHOT_INTERVAL_FRAMES = 6 -- ~10fps
local screenshotCounter = 0

local sock = nil
local rxBuffer = ""
-- Player 2's browser can turn the screenshot stream off (e.g. when screen-sharing over Discord
-- instead), since relay and emulator aren't necessarily on the same machine as Player 2's
-- browser -- capturing/encoding a frame ~10x/sec is real work worth skipping when nobody wants it.
local streamEnabled = true
-- pendingAction: nil, or {action="move", moveIndex=N}, or {action="switch", partySlot=N}
local pendingAction = nil
local awaitingAction = false
local awaitingReplacement = false
-- Player 2 only sees "waiting for your move" after Player 1's own menu has actually closed, so
-- the message doesn't get drawn while the battle screen is still settling in. Detected via the
-- same turn-state edge the battle log below already uses, applied to Player 1's own battler.
local playerActionReady = false
local lastPlayerCommState = 0
local battleMessageShown = false
-- Player 2's chosen display name -- used in the waiting message and to replace the trainer's
-- real name in-battle (see substitutePlayer1TrainerName).
local player2Name = "Player 2"
-- True only for the brief window between letting Player 2's decision through and that decision's
-- Should*/GetMostSuitableMon chain finishing. Needed because those same functions also get called
-- for unrelated things (e.g. a forced switch-in after a faint), and would otherwise pick up a
-- stale leftover pendingAction that has nothing to do with the current call.
local steeringArmed = false
-- The game calls GetMostSuitableMonToSwitchInto() twice for a single voluntary switch (once to
-- decide, once to confirm) -- normally invisible since both resolve instantly. Remembers Player
-- 2's answer from the first call so the second doesn't re-prompt for the same decision.
local voluntarySwitchSlot = nil
-- Buffers Player 1's battle-log entries until Player 2 has committed their own choice for the
-- turn, so Player 2 can't see what Player 1 did before answering themselves.
local player2Committed = false
local pendingPlayerLogEntries = {}
local flushPendingPlayerLogEntries -- defined later, forward-declared for use above its definition

-- Called whenever the relay connection is lost or never came up, so the retry loop in onFrame
-- picks it back up. Also re-arms playerNameSent -- a freshly (re)started relay has no memory of
-- this session, so the player_info line needs to go out again once we're back on the wire.
local function disconnect(reason)
    if sock then
        console:log("[client] disconnected from relay: " .. tostring(reason))
        pcall(function() sock:close() end)
    end
    sock = nil
    rxBuffer = ""
    playerNameSent = false
end

local function connect()
    local newSock = socket.tcp()
    newSock:add("received", function()
        if sock ~= newSock then return end
        while true do
            local data, err = newSock:receive(4096)
            if data then
                rxBuffer = rxBuffer .. data
                local nl = rxBuffer:find("\n")
                while nl do
                    local line = rxBuffer:sub(1, nl - 1)
                    rxBuffer = rxBuffer:sub(nl + 1)
                    handleMessage(line)
                    nl = rxBuffer:find("\n")
                end
            else
                if err ~= socket.ERRORS.AGAIN then
                    disconnect(err)
                end
                return
            end
        end
    end)
    newSock:add("error", function(err)
        if sock ~= newSock then return end
        disconnect(err)
    end)

    local ok, err = newSock:connect(RELAY_HOST, RELAY_PORT)
    if not ok then
        console:log("[client] connect failed: " .. tostring(err))
        pcall(function() newSock:close() end)
        return
    end
    sock = newSock
    console:log("[client] connected to relay")
end

local function sendJSON(jsonLine)
    if not sock then return end
    local ok, err = pcall(function() sock:send(jsonLine .. "\n") end)
    if not ok then
        disconnect(err)
    end
end

function handleMessage(line)
    -- Expected: {"type":"action_choice","action":"move","moveIndex":0}
    --        or {"type":"action_choice","action":"switch","partySlot":2}
    --        or {"type":"set_player2_name","name":"Ash"}
    --        or {"type":"set_stream_enabled","enabled":true}
    if line:find('"type"%s*:%s*"set_player2_name"') then
        local name = line:match('"name"%s*:%s*"([^"]*)"')
        if name and name ~= "" then
            console:log("[client] Player 2 set their name: " .. name)
            player2Name = name
            sendJSON('{"type":"player2_name_ack","name":"' .. name .. '"}')
        end
        return
    end

    if line:find('"type"%s*:%s*"set_stream_enabled"') then
        local enabled = line:match('"enabled"%s*:%s*(%a+)')
        if enabled == "true" or enabled == "false" then
            streamEnabled = (enabled == "true")
            console:log("[client] screenshot stream " .. (streamEnabled and "enabled" or "disabled"))
        end
        return
    end

    local action = line:match('"action"%s*:%s*"(%a+)"')
    if action == "move" then
        local moveIndex = line:match('"moveIndex"%s*:%s*(%d)')
        if moveIndex then
            pendingAction = { action = "move", moveIndex = tonumber(moveIndex) }
            console:log("[client] received action: move " .. moveIndex)
        end
    elseif action == "switch" then
        local partySlot = line:match('"partySlot"%s*:%s*(%d)')
        if partySlot then
            pendingAction = { action = "switch", partySlot = tonumber(partySlot) }
            console:log("[client] received action: switch to slot " .. partySlot)
        end
    end
end

-- Player 1's battle-log entries are held back until Player 2 has committed their own choice for
-- the turn, so Player 2 can't see Player 1's move before answering. Player 2's own entries are
-- never delayed.
local function emitBattleLog(battler, jsonLine)
    if battler == 0 and not player2Committed then
        table.insert(pendingPlayerLogEntries, jsonLine)
    else
        sendJSON(jsonLine)
    end
end

local function isInBattle()
    return (emu:read8(ADDR_GMAIN_IN_BATTLE) & MASK_GMAIN_IN_BATTLE) ~= 0
end

-- Returns the GBA player's own trainer name, or nil if the save data isn't loaded yet.
local function decodePlayerName()
    local saveBlock2 = emu:read32(ADDR_SAVE_BLOCK2_PTR)
    if saveBlock2 == 0 then return nil end
    local chars = {}
    for i = 0, PLAYER_NAME_LENGTH - 1 do
        local byte = emu:read8(saveBlock2 + i)
        if byte == GEN3_STRING_TERMINATOR then break end
        chars[#chars + 1] = GEN3_CHARMAP[byte] or "?"
    end
    local name = table.concat(chars)
    if name == "" then return nil end
    return name
end

local function takeScreenshot()
    local ok, err = pcall(function()
        local img = emu:screenshotToImage()
        if not img then
            console:log("[client] screenshotToImage() returned nil")
            return
        end
        local saved = img:save(SCREENSHOT_PATH, "PNG")
        if not saved then
            console:log("[client] screenshot save failed: " .. SCREENSHOT_PATH)
        end
    end)
    if not ok then
        console:log("[client] screenshot error: " .. tostring(err))
    end
end

local function sendPlayerNameIfNeeded()
    if playerNameSent then return end
    local name = decodePlayerName()
    if name then
        sendJSON('{"type":"player_info","name":"' .. name .. '"}')
        playerNameSent = true
        console:log("[client] sent player name: " .. name)
    end
end

-- Player 2 only ever influences trainer battles -- wild encounters play out untouched.
local function isControllableBattle()
    if not isInBattle() then return false end
    local flags = emu:read32(ADDR_BATTLE_TYPE_FLAGS)
    return (flags & BATTLE_TYPE_TRAINER) ~= 0
end

local function decodeGen3Bytes(addr, maxChars)
    local chars = {}
    for i = 0, maxChars - 1 do
        local byte = emu:read8(addr + i)
        if byte == GEN3_STRING_TERMINATOR then break end
        chars[#chars + 1] = GEN3_CHARMAP[byte] or "?"
    end
    return table.concat(chars)
end

-- Replaces the current trainer's real name with Player 2's chosen one, wherever it appears in
-- battle text. Runs on every piece of battle text the game prints, so it's a no-op whenever the
-- trainer's name doesn't actually appear in the text being drawn.
local BATTLE_TEXT_SEARCH_WINDOW = 64 -- generous for a single printed line/message

local function substitutePlayer1TrainerName(bufferAddr)
    if player2Name == "Player 2" then return end -- no custom name set, nothing to do
    local trainerId = emu:read16(ADDR_TRAINER_BATTLE_OPPONENT_A)
    if trainerId == 0 then return end -- TRAINER_NONE

    local realName = decodeGen3Bytes(ADDR_GTRAINERS + trainerId * TRAINER_STRUCT_SIZE + TRAINER_NAME_OFFSET, TRAINER_NAME_MAX_CHARS)
    if realName == "" then return end

    local haystack = decodeGen3Bytes(bufferAddr, BATTLE_TEXT_SEARCH_WINDOW)
    local matchStart = haystack:find(realName, 1, true)
    if not matchStart then return end

    -- Replacement must be exactly realName's length so nothing after it in the buffer shifts.
    local replacement = player2Name:sub(1, #realName)
    replacement = replacement .. string.rep(" ", #realName - #replacement)
    local bytes = encodeGen3Bytes(replacement, #realName)
    table.remove(bytes) -- drop the terminator -- we're writing mid-buffer, not ending the string
    for i, byte in ipairs(bytes) do
        emu:write8(bufferAddr + matchStart - 1 + i - 1, byte)
    end
end

local function onBattlePutTextOnWindow()
    if not isControllableBattle() then return end
    local ok, err = pcall(substitutePlayer1TrainerName, emu:readRegister("r0"))
    if not ok then
        console:log("[client] trainer name substitution error: " .. tostring(err))
    end
end

local function readActiveMon(base)
    local species = emu:read16(base + 0x00)
    local hp = emu:read16(base + 0x28)
    local level = emu:read8(base + 0x2A)
    local maxHp = emu:read16(base + 0x2C)
    return species, hp, maxHp, level
end

local function readPartyMon(base)
    local personality = emu:read32(base)
    local otId = emu:read32(base + 4)
    local key = personality ~ otId
    local growthSlot = GROWTH_SLOT_BY_PID24[personality % 24]
    local encryptedWord0 = emu:read32(base + 0x20 + growthSlot * 12)
    local species = (encryptedWord0 ~ key) & 0xFFFF
    local level = emu:read8(base + 0x54)
    local hp = emu:read16(base + 0x56)
    local maxHp = emu:read16(base + 0x58)
    return species, hp, maxHp, level
end

local function buildPartyJSON(baseAddr)
    local parts = {}
    for i = 0, PARTY_SIZE - 1 do
        local species, hp, maxHp, level = readPartyMon(baseAddr + i * PARTY_MON_SIZE)
        if species ~= 0 then
            table.insert(parts, string.format(
                '{"partySlot":%d,"species":%d,"hp":%d,"maxHp":%d,"level":%d}',
                i, species, hp, maxHp, level))
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- msgType: "battle_state" for a genuine new decision request ("your turn"), "battle_update" for a
-- passive HP/status refresh. mustSwitch: true when the enemy's active mon just fainted and
-- Player 2 may only pick a replacement this turn.
local function extractEnemyState(msgType, mustSwitch)
    local moveIds = {}
    local pp = {}
    for i = 0, 3 do
        moveIds[i + 1] = emu:read16(ADDR_ENEMY_MOVES + i * 2)
        pp[i + 1] = emu:read8(ADDR_ENEMY_PP + i)
    end
    local eSpecies, eHp, eMaxHp, eLevel = readActiveMon(ADDR_ENEMY_ACTIVE)
    local pSpecies, pHp, pMaxHp, pLevel = readActiveMon(ADDR_PLAYER_ACTIVE)
    local activePartySlot = emu:read16(ADDR_ENEMY_PARTY_INDEX)
    return string.format(
        '{"type":"%s","mustSwitch":%s,"enemyMoveIds":[%d,%d,%d,%d],"pp":[%d,%d,%d,%d],'
        .. '"enemyActive":{"species":%d,"hp":%d,"maxHp":%d,"level":%d},'
        .. '"playerActive":{"species":%d,"hp":%d,"maxHp":%d,"level":%d},'
        .. '"enemyActivePartySlot":%d,'
        .. '"enemyParty":%s}',
        msgType, mustSwitch and "true" or "false",
        moveIds[1], moveIds[2], moveIds[3], moveIds[4], pp[1], pp[2], pp[3], pp[4],
        eSpecies, eHp, eMaxHp, eLevel,
        pSpecies, pHp, pMaxHp, pLevel,
        activePartySlot,
        buildPartyJSON(ADDR_GENEMY_PARTY))
end

-- Holds the enemy trainer's action-type decision (fight/switch/item) until Player 2 answers.
local function onOpponentHandleChooseAction()
    if not isControllableBattle() then
        awaitingAction = false
        return
    end

    if not awaitingAction then
        awaitingAction = true
        pendingAction = nil
        steeringArmed = false
        awaitingReplacement = false
        voluntarySwitchSlot = nil
        player2Committed = false
        pendingPlayerLogEntries = {}
        playerActionReady = false
        battleMessageShown = false
        console:log("[client] enemy choosing action, notifying Player 2 (waiting...)")
        sendJSON(extractEnemyState("battle_state"))
    end

    if not playerActionReady then
        local commState = emu:read8(ADDR_BATTLE_COMMUNICATION_0)
        if commState > STATE_WAIT_ACTION_CASE_CHOSEN and lastPlayerCommState <= STATE_WAIT_ACTION_CASE_CHOSEN then
            playerActionReady = true
        end
        lastPlayerCommState = commState
    end

    if pendingAction == nil then
        if playerActionReady and not battleMessageShown then
            battleMessageShown = true
            showBattleMessage("Waiting for " .. player2Name .. "'s move...")
        else
            local lr = emu:readRegister("lr")
            emu:writeRegister("pc", lr)
        end
    else
        if pendingAction.action == "switch" then
            -- The AI's own switch path never writes the action byte the game expects here, so we
            -- write it ourselves -- otherwise the engine hangs waiting for it.
            emu:write8(ADDR_GBATTLE_BUFFER_B1 + 1, B_ACTION_SWITCH)
            voluntarySwitchSlot = pendingAction.partySlot
        end
        steeringArmed = true
        awaitingAction = false
    end
end

-- How many other enemy party members are still alive. With fewer than 2, there's no real choice
-- to make (one option, or the battle's over), so it's not worth prompting Player 2 for it.
local function countAliveNonActiveEnemyMons()
    local activeSlot = emu:read16(ADDR_ENEMY_PARTY_INDEX)
    local count = 0
    for i = 0, PARTY_SIZE - 1 do
        if i ~= activeSlot then
            local species, hp = readPartyMon(ADDR_GENEMY_PARTY + i * PARTY_MON_SIZE)
            if species ~= 0 and hp > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- Holds an unprompted "choose a replacement" call (i.e. the enemy's mon just fainted) until
-- Player 2 answers. Left alone if this is actually the follow-through of a voluntary switch
-- (already handled above) or we're already mid-hold elsewhere.
local function onOpponentHandleChoosePokemon()
    if not isControllableBattle() then
        awaitingReplacement = false
        return
    end

    if voluntarySwitchSlot ~= nil then
        local slot = voluntarySwitchSlot
        voluntarySwitchSlot = nil
        pendingAction = { action = "switch", partySlot = slot }
        steeringArmed = true
        return
    end
    if steeringArmed or awaitingAction then
        return
    end
    if countAliveNonActiveEnemyMons() < 2 then
        awaitingReplacement = false
        return
    end

    if not awaitingReplacement then
        awaitingReplacement = true
        pendingAction = nil
        console:log("[client] enemy's mon fainted, notifying Player 2 for a replacement (waiting...)")
        sendJSON(extractEnemyState("battle_state", true))
        showBattleMessage("Waiting for " .. player2Name .. " to pick a replacement...")
        return
    end

    if pendingAction == nil then
        local lr = emu:readRegister("lr")
        emu:writeRegister("pc", lr)
    else
        steeringArmed = true
        awaitingReplacement = false
    end
end

local function onShouldSwitch()
    if not steeringArmed then return end
    if pendingAction and pendingAction.action == "switch" then
        emu:writeRegister("r0", 1)
    else
        emu:writeRegister("r0", 0)
    end
    local lr = emu:readRegister("lr")
    emu:writeRegister("pc", lr)
end

local function onGetMostSuitableMon()
    if not steeringArmed then return end
    if pendingAction and pendingAction.action == "switch" and pendingAction.partySlot ~= nil then
        emu:writeRegister("r0", pendingAction.partySlot)
        local lr = emu:readRegister("lr")
        emu:writeRegister("pc", lr)
    end
    steeringArmed = false
    pendingAction = nil
    player2Committed = true
    flushPendingPlayerLogEntries()
end

-- Item usage isn't supported yet -- always deny so the AI can't act on its own while we're
-- already controlling its move/switch decision.
local function onShouldUseItem()
    if not steeringArmed then return end
    emu:writeRegister("r0", 0)
    local lr = emu:readRegister("lr")
    emu:writeRegister("pc", lr)
    steeringArmed = false
end

-- Injects Player 2's already-decided move once the game reaches the point where it expects one.
local function onHandleTurnActionSelection()
    if not isControllableBattle() then return end
    if not (pendingAction and pendingAction.action == "move") then return end

    local enemyState = emu:read8(ADDR_BATTLE_COMMUNICATION_1)
    local header = emu:read8(ADDR_GBATTLE_BUFFER_B1)
    local action = emu:read8(ADDR_GBATTLE_BUFFER_B1 + 1)

    local enemyDecisionPending = (enemyState == STATE_WAIT_ACTION_CASE_CHOSEN
        and header == CONTROLLER_TWORETURNVALUES and action == B_ACTION_EXEC_SCRIPT)

    if enemyDecisionPending then
        local moveIndex = pendingAction.moveIndex
        emu:write8(ADDR_GBATTLE_BUFFER_B1 + 2, moveIndex) -- move slot
        emu:write8(ADDR_GBATTLE_BUFFER_B1 + 3, PLAYER_BATTLER_INDEX)   -- target
        console:log("[client] injected move " .. moveIndex)
        pendingAction = nil
        player2Committed = true
        flushPendingPlayerLogEntries()

        -- Log Player 2's move directly, using the move slot we just injected, rather than
        -- through the same gBattleCommunication-based edge-detection used for Player 1. That
        -- detector can fire for reasons unrelated to a genuine decision (e.g. during battle
        -- setup), which read whatever gChosenMoveByBattler[1] happened to still hold from a
        -- previous battle and logged it as if it just happened.
        local moveId = emu:read16(ADDR_ENEMY_MOVES + moveIndex * 2)
        local species = emu:read16(ADDR_ENEMY_ACTIVE + 0x00)
        emitBattleLog(1, string.format(
            '{"type":"battle_log","battler":1,"event":"move","moveId":%d,"speciesId":%d}',
            moveId, species))
    end
end

local wasInBattle = false
local heartbeatCounter = 0

-- Battle log: tracks each battler's move/switch decisions and sends them to the browser. Player
-- 1's entries are held back until Player 2 has committed their own choice for the turn, so
-- Player 2 can't see Player 1's move before answering.
local lastCommState = { [0] = 0, [1] = 0 }
local lastPartyIndex = { [0] = -1, [1] = -1 }

flushPendingPlayerLogEntries = function()
    for _, jsonLine in ipairs(pendingPlayerLogEntries) do
        sendJSON(jsonLine)
    end
    pendingPlayerLogEntries = {}
end

local function logMove(battler)
    local moveId = emu:read16(ADDR_CHOSEN_MOVE_BY_BATTLER + battler * 2)
    if moveId == 0 then return end
    local base = (battler == 0) and ADDR_PLAYER_ACTIVE or ADDR_ENEMY_ACTIVE
    local species = emu:read16(base + 0x00)
    emitBattleLog(battler, string.format(
        '{"type":"battle_log","battler":%d,"event":"move","moveId":%d,"speciesId":%d}',
        battler, moveId, species))
end

-- Player 1's moves are detected here (we don't control their input, only observe it). Player
-- 2's moves are logged directly at the moment we inject them (see onHandleTurnActionSelection)
-- instead -- this same gBattleCommunication-based detection can cross its threshold for reasons
-- unrelated to a genuine decision (e.g. during battle setup), which produced false log entries
-- from whatever gChosenMoveByBattler[1] happened to still hold from a previous battle.
local function checkBattleLog()
    do
        local battler = 0
        local commState = emu:read8(ADDR_BATTLE_COMMUNICATION_0)
        if commState > STATE_WAIT_ACTION_CASE_CHOSEN and lastCommState[battler] <= STATE_WAIT_ACTION_CASE_CHOSEN then
            local action = emu:read8(ADDR_CHOSEN_ACTION_BY_BATTLER + battler)
            if action == B_ACTION_USE_MOVE then
                logMove(battler)
            end
            -- Switches aren't logged here -- caught below via the party-index check instead,
            -- which also covers forced switches after a faint.
        end
        lastCommState[battler] = commState
    end

    for battler = 0, 1 do
        local partyIndex = emu:read16(ADDR_BATTLER_PARTY_INDEX_0 + battler * 2)
        if partyIndex ~= lastPartyIndex[battler] then
            local wasFirstRead = lastPartyIndex[battler] == -1
            lastPartyIndex[battler] = partyIndex
            if not wasFirstRead then
                local base = (battler == 0) and ADDR_PLAYER_ACTIVE or ADDR_ENEMY_ACTIVE
                local species = emu:read16(base + 0x00)
                emitBattleLog(battler, string.format(
                    '{"type":"battle_log","battler":%d,"event":"switch","speciesId":%d}',
                    battler, species))
            end
        end
    end
end

local function resetBattleLog()
    -- Seed with the game's REAL current state, not a hardcoded 0 -- gChosenMoveByBattler/
    -- gChosenActionByBattler never get cleared between battles, so a fake low baseline makes
    -- the very first check see a false "just happened" transition into that stale leftover data.
    lastCommState = {
        [0] = emu:read8(ADDR_BATTLE_COMMUNICATION_0),
        [1] = emu:read8(ADDR_BATTLE_COMMUNICATION_1),
    }
    lastPartyIndex = { [0] = -1, [1] = -1 }
    player2Committed = false
    pendingPlayerLogEntries = {}
    awaitingReplacement = false
    voluntarySwitchSlot = nil
end

local reconnectCounter = 0

local function onFrame()
    if not sock then
        reconnectCounter = reconnectCounter + 1
        if reconnectCounter >= RECONNECT_INTERVAL_FRAMES then
            reconnectCounter = 0
            connect()
        end
    end

    sendPlayerNameIfNeeded()

    local nowInBattle = isControllableBattle()
    if nowInBattle then
        if not wasInBattle then
            console:log("[client] trainer battle started, notifying Player 2")
            sendJSON('{"type":"battle_started"}')
            resetBattleLog()
        end
        checkBattleLog()
        heartbeatCounter = heartbeatCounter + 1
        if heartbeatCounter >= HEARTBEAT_INTERVAL_FRAMES then
            heartbeatCounter = 0
            sendJSON(extractEnemyState("battle_update"))
        end
    elseif wasInBattle then
        console:log("[client] battle ended, notifying Player 2")
        sendJSON('{"type":"battle_ended"}')
        heartbeatCounter = 0
        resetBattleLog()
    end
    wasInBattle = nowInBattle

    if isControllableBattle() or not streamEnabled then
        screenshotCounter = 0
    else
        screenshotCounter = screenshotCounter + 1
        if screenshotCounter >= SCREENSHOT_INTERVAL_FRAMES then
            screenshotCounter = 0
            takeScreenshot()
        end
    end
end

emu:setBreakpoint(onOpponentHandleChooseAction, ADDR_OPPONENT_HANDLE_CHOOSE_ACTION)
emu:setBreakpoint(onOpponentHandleChoosePokemon, ADDR_OPPONENT_HANDLE_CHOOSE_POKEMON)
emu:setBreakpoint(onShouldSwitch, ADDR_SHOULD_SWITCH)
emu:setBreakpoint(onGetMostSuitableMon, ADDR_GET_MOST_SUITABLE_MON)
emu:setBreakpoint(onShouldUseItem, ADDR_SHOULD_USE_ITEM)
emu:setBreakpoint(onHandleTurnActionSelection, ADDR_HANDLE_TURN_ACTION_SELECTION)
emu:setBreakpoint(onBattlePutTextOnWindow, ADDR_BATTLE_PUT_TEXT_ON_WINDOW)
callbacks:add("frame", onFrame)
connect()

console:log("[client] PokePVP client.lua loaded (ROM: " .. tostring(emu:getGameCode()) .. ")")
