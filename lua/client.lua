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

-- gSpeciesInfo: the ROM's per-species base stats table (struct SpeciesInfo, 0x1C bytes each),
-- confirmed from pret/pokeemerald's source (genderRatio at struct offset 0x10) cross-referenced
-- against Bulbapedia's documented address for this specific US release. Not yet independently
-- live-verified -- confirm before trusting (e.g. read species #1 Bulbasaur's genderRatio and check
-- it comes back as 31/0x1F, its real known ratio).
local ADDR_GSPECIES_INFO = 0x083203E8
local SPECIES_INFO_STRUCT_SIZE = 0x1C
local GENDER_RATIO_OFFSET = 0x10
local GENDER_RATIO_ALWAYS_FEMALE = 0xFE
local GENDER_RATIO_GENDERLESS = 0xFF

-- Gen 3's standard formula: genderless/always-male/always-female are special-cased sentinel
-- values; otherwise the mon's own personality value (its low byte) rolled against the species'
-- threshold decides. Returns "male", "female", or nil (genderless).
local function computeGender(species, personality)
    local genderRatio = emu:read8(ADDR_GSPECIES_INFO + species * SPECIES_INFO_STRUCT_SIZE + GENDER_RATIO_OFFSET)
    if genderRatio == GENDER_RATIO_GENDERLESS then return nil end
    if genderRatio == GENDER_RATIO_ALWAYS_FEMALE then return "female" end
    if genderRatio == 0 then return "male" end
    if (personality & 0xFF) < genderRatio then return "female" end
    return "male"
end

local ADDR_OPPONENT_HANDLE_CHOOSE_ACTION = 0x08061F9C -- AI decides fight/switch/item
local ADDR_OPPONENT_HANDLE_CHOOSE_POKEMON = 0x08062188 -- AI picks which mon to switch to
local ADDR_SHOULD_SWITCH = 0x08063614
local ADDR_GET_MOST_SUITABLE_MON = 0x08063A90
local ADDR_SHOULD_USE_ITEM = 0x08063EE0
local ADDR_HANDLE_TURN_ACTION_SELECTION = 0x0803BE74

-- gActiveBattler: which battler (0-3) the currently-executing AI decision function is deciding
-- for. Found live via before/after Memory Search (byte value 1 -> 3 across the two enemy
-- battlers' decisions within one double-battle turn) -- a single survivor address, reproduced
-- identically across two separate turns.
local ADDR_ACTIVE_BATTLER = 0x02024064

-- gBattleBufferB[0..3] / gBattleCommunication[0..3]. Index 1's address (the enemy's, in singles)
-- was already known; index 3's stride (0x200 for the buffer, matching its declared
-- `u8[MAX_BATTLERS_COUNT][0x200]` size; 1 byte for gBattleCommunication) confirmed live the same
-- way as gBattleMons's stride -- header/action/comm-state values for battler 3 matched the exact
-- same sensible protocol states already known from singles.
local ADDR_GBATTLE_BUFFER_B1 = 0x02023A64 -- gBattleBufferB[1], the enemy's buffer
local ADDR_BATTLE_COMMUNICATION_1 = 0x02024333 -- gBattleCommunication[1] (enemy)
local GBATTLE_BUFFER_STRIDE = 0x200

local function battlerBufferBase(battler)
    return ADDR_GBATTLE_BUFFER_B1 + (battler - 1) * GBATTLE_BUFFER_STRIDE
end
local function battlerCommAddr(battler)
    return ADDR_BATTLE_COMMUNICATION_1 + (battler - 1)
end

-- gBattleStruct->chosenItem[0] / ->AI_itemType[0] / ->AI_itemFlags[0]. Found via live Memory
-- Search (before/after diffing across a real item-use event) since gBattleStruct is heap-allocated
-- and neither field has a discoverable fixed address in source. Confirmed live: writing item 13
-- (Potion) + AI_ITEM_HEAL_HP here and forcing ShouldUseItem's return caused the trainer to
-- genuinely use the Potion, with OpponentHandleChooseItem's response correctly echoing it back.
-- Battler 1 only for now -- item support isn't extended to battler 3 (see ITEM_AI_CLASSIFICATION
-- usage below), so no need to compute the (gActiveBattler / 2)-based offset for the other slot yet.
local ADDR_CHOSEN_ITEM = 0x020000D0
local ADDR_AI_ITEM_TYPE = 0x020000D4
local ADDR_AI_ITEM_FLAGS = 0x020000D6

-- gBattleMons[0..3] (struct BattlePokemon): the four possible active mons (0/2 = player's,
-- 1/3 = enemy's, in a double battle -- singles only ever uses 0/1), already decrypted by the game.
-- moves[4] u16 @ +0x0C, pp[4] u8 @ +0x24, species u16 @ +0x00, hp u16 @ +0x28, level u8 @ +0x2A,
-- maxHp u16 @ +0x2C. Stride (0x58) confirmed live for battler 3 via species/HP cross-checked
-- against the actual on-screen mon across two turns of a real double battle.
local ADDR_PLAYER_ACTIVE = 0x02024084
local BATTLE_MON_STRIDE = 0x58
local ADDR_ENEMY_ACTIVE = ADDR_PLAYER_ACTIVE + 1 * BATTLE_MON_STRIDE

local function battlerMonBase(battler)
    return ADDR_PLAYER_ACTIVE + battler * BATTLE_MON_STRIDE
end
local function battlerMovesBase(battler)
    return battlerMonBase(battler) + 0x0C
end
local function battlerPPBase(battler)
    return battlerMonBase(battler) + 0x24
end

-- gEnemyParty (struct Pokemon[6], 0x64 bytes each). Species is encrypted with a per-mon key
-- derived from personality/OT ID; level/hp/maxHp are not. Nickname readable directly at +0x08.
local ADDR_GENEMY_PARTY = 0x02024744
-- gPlayerParty -- same struct/layout as gEnemyParty.
local ADDR_GPLAYER_PARTY = 0x020244EC
local PARTY_MON_SIZE = 0x64
local PARTY_SIZE = 6
local NICKNAME_OFFSET = 0x08
local NICKNAME_MAX_CHARS = 10

-- Which of the 4 encrypted substructures (Growth/Attacks/EVs/Misc) holds Growth data, indexed by
-- personality % 24. From Bulbapedia's Gen 3 substructure order table.
local GROWTH_SLOT_BY_PID24 = {
    [0] = 0,
    [1] = 0,
    [2] = 0,
    [3] = 0,
    [4] = 0,
    [5] = 0,
    [6] = 1,
    [7] = 1,
    [8] = 2,
    [9] = 3,
    [10] = 2,
    [11] = 3,
    [12] = 1,
    [13] = 1,
    [14] = 2,
    [15] = 3,
    [16] = 2,
    [17] = 3,
    [18] = 1,
    [19] = 1,
    [20] = 2,
    [21] = 3,
    [22] = 2,
    [23] = 3
}

-- Same idea, for the Attacks substructure (moves/PP) -- derived from the same 24-permutation
-- table, cross-checked against GROWTH_SLOT_BY_PID24 above (both come from the identical ordering,
-- just tracking a different letter's position each time).
local ATTACKS_SLOT_BY_PID24 = {
    [0] = 1,
    [1] = 1,
    [2] = 2,
    [3] = 3,
    [4] = 2,
    [5] = 3,
    [6] = 0,
    [7] = 0,
    [8] = 0,
    [9] = 0,
    [10] = 0,
    [11] = 0,
    [12] = 2,
    [13] = 3,
    [14] = 1,
    [15] = 1,
    [16] = 3,
    [17] = 2,
    [18] = 2,
    [19] = 3,
    [20] = 1,
    [21] = 1,
    [22] = 3,
    [23] = 2
}

local RECONNECT_INTERVAL_FRAMES = 120 -- ~2s at 60fps

local STATE_WAIT_ACTION_CASE_CHOSEN = 3
local PLAYER_BATTLER_INDEX = 0
local CONTROLLER_TWORETURNVALUES = 33
local B_ACTION_USE_ITEM = 1
local B_ACTION_EXEC_SCRIPT = 10
local B_ACTION_SWITCH = 2
local BATTLE_TYPE_TRAINER = 0x8
local HEARTBEAT_INTERVAL_FRAMES = 30
local MAX_TRAINER_ITEMS = 4
local TRAINER_ITEMS_OFFSET = 0x10

-- AI_ITEM_* / AI_HEAL_* / AI_X_* -- confirmed from pokeemerald's include/battle_ai_switch_items.h.
local AI_ITEM_FULL_RESTORE = 1
local AI_ITEM_HEAL_HP = 2
local AI_ITEM_CURE_CONDITION = 3
local AI_ITEM_X_STAT = 4
local AI_ITEM_GUARD_SPEC = 5
local AI_HEAL_CONFUSION = 0
local AI_HEAL_PARALYSIS = 1
local AI_HEAL_FREEZE = 2
local AI_HEAL_BURN = 3
local AI_HEAL_POISON = 4
local AI_HEAL_SLEEP = 5
local AI_X_ATTACK = 0
local AI_X_DEFEND = 1
local AI_X_SPEED = 2
local AI_X_SPATK = 3
local AI_X_ACCURACY = 5
local AI_DIRE_HIT = 7

-- Classifies every item a trainer could plausibly carry, matching pokeemerald's own
-- GetAI_ItemType()/ShouldUseItem() classification (src/battle_ai_switch_items.c) -- since a
-- player-driven choice bypasses that function's own logic entirely, this table (plus itemFlags,
-- for the two categories that need to say exactly which condition/stat) has to reconstruct its
-- conclusions by hand. Only the HEAL_HP path (Potion) has been live-verified end to end; the rest
-- follow the same confirmed injection mechanism but haven't been tested against a real trainer.
local ITEM_AI_CLASSIFICATION = {
    [13] = {
        itemType = AI_ITEM_HEAL_HP
    }, -- Potion
    [22] = {
        itemType = AI_ITEM_HEAL_HP
    }, -- Super Potion
    [21] = {
        itemType = AI_ITEM_HEAL_HP
    }, -- Hyper Potion
    [20] = {
        itemType = AI_ITEM_HEAL_HP
    }, -- Max Potion
    [19] = {
        itemType = AI_ITEM_FULL_RESTORE
    }, -- Full Restore
    [14] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = 1 << AI_HEAL_POISON
    }, -- Antidote
    [15] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = 1 << AI_HEAL_BURN
    }, -- Burn Heal
    [16] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = 1 << AI_HEAL_FREEZE
    }, -- Ice Heal
    [17] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = 1 << AI_HEAL_SLEEP
    }, -- Awakening
    [18] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = 1 << AI_HEAL_PARALYSIS
    }, -- Paralyze Heal
    [23] = {
        itemType = AI_ITEM_CURE_CONDITION,
        itemFlags = (1 << AI_HEAL_CONFUSION) | (1 << AI_HEAL_PARALYSIS) | (1 << AI_HEAL_FREEZE) | (1 << AI_HEAL_BURN) |
            (1 << AI_HEAL_POISON) | (1 << AI_HEAL_SLEEP)
    }, -- Full Heal
    [73] = {
        itemType = AI_ITEM_GUARD_SPEC
    }, -- Guard Spec
    [74] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_DIRE_HIT
    }, -- Dire Hit
    [75] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_X_ATTACK
    }, -- X Attack
    [76] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_X_DEFEND
    }, -- X Defend
    [77] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_X_SPEED
    }, -- X Speed
    [78] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_X_ACCURACY
    }, -- X Accuracy
    [79] = {
        itemType = AI_ITEM_X_STAT,
        itemFlags = 1 << AI_X_SPATK
    } -- X Special
}

-- Reads the current opponent trainer's carried items straight from ROM (struct Trainer.items,
-- confirmed live earlier this project). Returns up to 4 non-zero item IDs.
local function readTrainerItems()
    local trainerId = emu:read16(ADDR_TRAINER_BATTLE_OPPONENT_A)
    local base = ADDR_GTRAINERS + trainerId * TRAINER_STRUCT_SIZE + TRAINER_ITEMS_OFFSET
    local items = {}
    for i = 0, MAX_TRAINER_ITEMS - 1 do
        local item = emu:read16(base + i * 2)
        if item ~= 0 then
            items[#items + 1] = item
        end
    end
    return items
end

-- Used only for the battle log (detecting what each battler just did), not for injection.
local ADDR_CHOSEN_MOVE_BY_BATTLER = 0x02024274
local ADDR_CHOSEN_ACTION_BY_BATTLER = 0x0202421C
local ADDR_BATTLE_COMMUNICATION_0 = 0x02024332
local B_ACTION_USE_MOVE = 0

local ADDR_SAVE_BLOCK2_PTR = 0x03005D90 -- gSaveBlock2Ptr->playerName lives at the start of this
local PLAYER_NAME_LENGTH = 7
local GEN3_STRING_TERMINATOR = 0xFF

-- Gen 3 games don't use ASCII -- every string is its own custom byte encoding. These two tables
-- convert between that encoding and normal Lua strings, covering letters, digits, space, and a
-- handful of common punctuation marks (values from pret's charmap.txt).
local GEN3_CHARMAP = {
    [0x00] = " "
}
local GEN3_ENCODE_MAP = {
    [" "] = 0x00
}
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
    local punctuation = {
        ["!"] = 0xAB,
        ["?"] = 0xAC,
        ["."] = 0xAD,
        ["-"] = 0xAE,
        [","] = 0xB8,
        ["'"] = 0xB4
    }
    for char, byte in pairs(punctuation) do
        GEN3_CHARMAP[byte] = char
        GEN3_ENCODE_MAP[char] = byte
    end
end
local playerNameSent = false

local GEN3_NEWLINE = 0xFE -- "\n" control code (pret's charmap.txt) -- breaks to the window's next
-- line without waiting for a button press, unlike \l/\p which pause for input.

local function encodeGen3Bytes(text, maxChars)
    local bytes = {}
    for i = 1, math.min(#text, maxChars) do
        local char = text:sub(i, i)
        -- A literal "\n" in the source string requests a line break in the drawn message, not a
        -- Gen3-encoded space -- route it to the engine's own newline control byte instead of
        -- looking it up in GEN3_ENCODE_MAP (which has no entry for it and would draw a space).
        bytes[i] = char == "\n" and GEN3_NEWLINE or (GEN3_ENCODE_MAP[char] or 0x00) -- unencodable
        -- chars fall back to a space
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
-- Contrary to what this used to assume, jumping straight into BattlePutTextOnWindow does NOT run
-- the normal word-wrap logic ordinary battle text goes through (AddTextPrinter with a line-length
-- template) -- text just draws linearly and anything past the window's visible width is clipped,
-- not wrapped. So we word-wrap ourselves before encoding, breaking with the engine's own \n
-- control code. BATTLE_MESSAGE_LINE_WIDTH is a conservative per-line character budget (the exact
-- pixel width varies by character, so this trades a little unused margin for never overflowing).
local BATTLE_MESSAGE_LINE_WIDTH = 32
local BATTLE_MESSAGE_MAX_CHARS = 90 -- 2 lines worth + the \n byte, well under gDisplayedStringBattle's size

local function wrapBattleMessage(text)
    if #text <= BATTLE_MESSAGE_LINE_WIDTH then
        return text
    end
    local breakAt = nil
    for i = BATTLE_MESSAGE_LINE_WIDTH, 1, -1 do
        if text:sub(i, i) == " " then
            breakAt = i
            break
        end
    end
    local line1, rest
    if breakAt then
        line1 = text:sub(1, breakAt - 1)
        rest = text:sub(breakAt + 1)
    else
        line1 = text:sub(1, BATTLE_MESSAGE_LINE_WIDTH)
        rest = text:sub(BATTLE_MESSAGE_LINE_WIDTH + 1)
    end
    return line1 .. "\n" .. rest:sub(1, BATTLE_MESSAGE_LINE_WIDTH)
end

local function showBattleMessage(text)
    local bytes = encodeGen3Bytes(wrapBattleMessage(text), BATTLE_MESSAGE_MAX_CHARS)
    for i, byte in ipairs(bytes) do
        emu:write8(ADDR_DISPLAYED_STRING_BATTLE + i - 1, byte)
    end
    emu:write16(ADDR_BATTLE_BG0_X, 0)
    emu:write16(ADDR_BATTLE_BG0_Y, 0)
    emu:writeRegister("r0", ADDR_DISPLAYED_STRING_BATTLE)
    emu:writeRegister("r1", B_WIN_MSG)
    emu:writeRegister("pc", ADDR_BATTLE_PUT_TEXT_ON_WINDOW)
end

local function scriptDir()
    local source = debug.getinfo(1, "S").source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return source:match("(.*[/\\])") or "./"
end

-- Lua 5.4 has no built-in base64 encoder. Standard table-based 3-byte -> 4-char implementation

local BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local b1, b2, b3 = data:byte(i, i + 2)
        local n = b1 * 0x10000 + (b2 or 0) * 0x100 + (b3 or 0)
        local c1 = (n >> 18) & 0x3F
        local c2 = (n >> 12) & 0x3F
        local c3 = (n >> 6) & 0x3F
        local c4 = n & 0x3F
        local chunk = BASE64_CHARS:sub(c1 + 1, c1 + 1) .. BASE64_CHARS:sub(c2 + 1, c2 + 1)
        chunk = chunk .. (b2 and BASE64_CHARS:sub(c3 + 1, c3 + 1) or "=")
        chunk = chunk .. (b3 and BASE64_CHARS:sub(c4 + 1, c4 + 1) or "=")
        out[#out + 1] = chunk
    end
    return table.concat(out)
end

-- Takes a screenshot periodically, for the web UI's "stream" view when no trainer battle is in
-- progress. Captured to a local scratch file, then immediately
-- read back and sent to the relay as a "screen_frame" message

local SCREENSHOT_PATH = scriptDir() .. "screen_tmp.png"

local GBA_FRAME_RATE = 60
local MIN_STREAM_FPS = 5
local MAX_STREAM_FPS = 24
local screenshotTargetFps = MAX_STREAM_FPS -- overridable remotely, see "set_stream_fps" in handleMessage
local screenshotAccumulator = 0

local sock = nil
local rxBuffer = ""
-- Player 2's browser can turn the screenshot stream off (e.g. when screen-sharing over Discord
-- instead), since relay and emulator aren't necessarily on the same machine as Player 2's
-- browser -- capturing/encoding a frame ~24x/sec is real work worth skipping when nobody wants it.
local streamEnabled = true
-- All per-enemy-battler decision state below is keyed by battler number (1, or 3 in a double
-- battle) rather than being a single shared value -- each enemy battler makes its own independent
-- decision each turn, using its own slice of this state. Singles only ever touches key 1, so its
-- behavior is unchanged; a missing key (e.g. [3] before a double battle's second battler has had
-- its first decision) reads as nil/false, same as the old singular defaults did.
--
-- pendingAction[battler]: nil, or {action="move", moveIndex=N}, or {action="switch", partySlot=N}
--                      or {action="item", itemId=N}
local pendingAction = {}
-- How many of each item Player 2 has already used this battle, per battler -- gTrainers' item
-- list is read straight from ROM (read-only), so it never reflects consumption on its own; this is
-- subtracted from that raw count wherever items are offered/validated. Reset per battle, see
-- resetBattleLog(). Battler 3 stays empty for now -- see ITEM_AI_CLASSIFICATION's usage, item
-- support isn't extended to battler 3 yet (needs gTrainerBattleOpponent_B, not yet discovered).
local usedItemCounts = {
    [1] = {}
}
local awaitingAction = {}
local awaitingReplacement = {}
-- Player 2 only sees "waiting for your move" after Player 1's own menu has actually closed, so
-- the message doesn't get drawn while the battle screen is still settling in. Detected via the
-- same turn-state edge the battle log below already uses, applied to Player 1's own battler(s).
-- In a double battle Player 1 picks moves for both their own mons via two sequential menus
-- (battler 0 then battler 2) -- watching only battler 0 fired this message while Player 1 was
-- still picking their SECOND mon's move, stomping their own menu. Both must be ready in doubles.
local playerActionReady = false
local lastPlayerCommState = 0
local lastPlayerCommState2 = 0
local player1Battler0Ready = false
local player1Battler2Ready = false
local battleMessageShown = false
-- Player 2's chosen display name -- used in the waiting message and to replace the trainer's
-- real name in-battle (see substitutePlayer1TrainerName).
local player2Name = "Player 2"
-- True only for the brief window between letting a battler's decision through and that decision's
-- Should*/GetMostSuitableMon chain finishing. Needed because those same functions also get called
-- for unrelated things (e.g. a forced switch-in after a faint), and would otherwise pick up a
-- stale leftover pendingAction that has nothing to do with the current call.
local steeringArmed = {}
-- The game calls GetMostSuitableMonToSwitchInto() twice for a single voluntary switch (once to
-- decide, once to confirm) -- normally invisible since both resolve instantly. Remembers Player
-- 2's answer from the first call so the second doesn't re-prompt for the same decision.
local voluntarySwitchSlot = {}
-- Buffers Player 1's battle-log entries until Player 2 has committed every enemy battler's choice
-- for the turn, so Player 2 can't see what Player 1 did before answering themselves.
local player2Committed = {}
local pendingPlayerLogEntries = {}
local flushPendingPlayerLogEntries -- defined later, forward-declared for use above its definition
local isDoubleBattle -- defined later (needs isInBattle), forward-declared for use in handleMessage
local allEnemyBattlersCommitted -- defined later (needs isDoubleBattle), forward-declared for use above

-- Remaining counts for every supported item the current trainer carries, after subtracting what
-- Player 2 has already used this battle (see usedItemCounts). Items at 0 remaining are omitted.
-- Battler 3 always gets an empty list -- item support isn't extended there yet (see
-- ITEM_AI_CLASSIFICATION's usage; needs gTrainerBattleOpponent_B, not yet discovered), and
-- readTrainerItems() only ever reads trainer A's items regardless of which battler is asking.
local function remainingItemCounts(battler)
    if battler ~= 1 then
        return {}
    end
    local counts = {}
    local order = {}
    for _, itemId in ipairs(readTrainerItems()) do
        if ITEM_AI_CLASSIFICATION[itemId] then
            if not counts[itemId] then
                counts[itemId] = 0
                order[#order + 1] = itemId
            end
            counts[itemId] = counts[itemId] + 1
        end
    end
    for itemId, used in pairs(usedItemCounts[battler] or {}) do
        if counts[itemId] then
            counts[itemId] = counts[itemId] - used
        end
    end
    local result = {}
    for _, itemId in ipairs(order) do
        if counts[itemId] > 0 then
            result[#result + 1] = {
                itemId = itemId,
                count = counts[itemId]
            }
        end
    end
    return result
end

-- Move log entries are queued when chosen (keyed by battler, 0-3), then only actually sent once
-- the target's HP proves the move executed. Real values seeded by resetBattleLog() on battle start.
local pendingMoveLog = {}
local lastMoveLogHp = {}

-- Called whenever the relay connection is lost or never came up, so the retry loop in onFrame
-- picks it back up. Also re-arms playerNameSent -- a freshly (re)started relay has no memory of
-- this session, so the player_info line needs to go out again once we're back on the wire.
local function disconnect(reason)
    if sock then
        console:log("[client] disconnected from relay: " .. tostring(reason))
        pcall(function()
            sock:close()
        end)
    end
    sock = nil
    rxBuffer = ""
    playerNameSent = false
end

local function connect()
    local newSock = socket.tcp()
    newSock:add("received", function()
        if sock ~= newSock then
            return
        end
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
        if sock ~= newSock then
            return
        end
        disconnect(err)
    end)

    local ok, err = newSock:connect(RELAY_HOST, RELAY_PORT)
    if not ok then
        console:log("[client] connect failed: " .. tostring(err))
        pcall(function()
            newSock:close()
        end)
        return
    end
    sock = newSock
    console:log("[client] connected to relay")
end

local function sendJSON(jsonLine)
    if not sock then
        return
    end
    local ok, err = pcall(function()
        sock:send(jsonLine .. "\n")
    end)
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
        if name and name ~= "" and #name <= 20 then
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

    if line:find('"type"%s*:%s*"set_stream_fps"') then
        local fps = tonumber(line:match('"fps"%s*:%s*(%d+)'))
        if fps and fps >= MIN_STREAM_FPS and fps <= MAX_STREAM_FPS then
            screenshotTargetFps = fps
            screenshotAccumulator = 0
            console:log("[client] screenshot stream target: " .. fps .. "fps")
        else
            console:log("[client] rejected out-of-range stream fps: " .. tostring(fps))
        end
        return
    end

    -- battlerSlot identifies which enemy battler this choice is for (1, or 3 in a double battle).
    -- Defaults to 1 when absent so existing singles-only clients keep working unchanged.
    local battlerSlot = tonumber(line:match('"battlerSlot"%s*:%s*(%d+)')) or 1
    if battlerSlot ~= 1 and battlerSlot ~= 3 then
        console:log("[client] rejected out-of-range battlerSlot: " .. battlerSlot)
        return
    end

    local action = line:match('"action"%s*:%s*"(%a+)"')
    if action == "move" then
        local moveIndex = tonumber(line:match('"moveIndex"%s*:%s*(%d+)'))
        -- target: which of Player 1's mons to hit -- 0 or 2, only meaningful in a double battle
        -- (singles always targets 0). Defaults to 0 so non-doubles-aware clients keep working.
        local target = tonumber(line:match('"target"%s*:%s*(%d+)')) or PLAYER_BATTLER_INDEX
        if isDoubleBattle() and target ~= 0 and target ~= 2 then
            console:log("[client] rejected out-of-range target: " .. target)
            return
        elseif not isDoubleBattle() then
            target = PLAYER_BATTLER_INDEX
        end
        if moveIndex and moveIndex >= 0 and moveIndex <= 3 then
            pendingAction[battlerSlot] = {
                action = "move",
                moveIndex = moveIndex,
                target = target
            }
            console:log("[client] received action: battler " .. battlerSlot .. " move " .. moveIndex .. " -> target " ..
                            target)
        else
            console:log("[client] rejected out-of-range moveIndex: " .. tostring(moveIndex))
        end
    elseif action == "switch" then
        local partySlot = tonumber(line:match('"partySlot"%s*:%s*(%d+)'))
        -- A battler may only switch within its own trainer's half of gEnemyParty in a double
        -- battle (same split as buildPartyJSON/countAliveNonActiveEnemyMons) -- otherwise it could
        -- switch into a mon that belongs to the OTHER enemy battler's trainer entirely.
        local minSlot, maxSlot = 0, PARTY_SIZE - 1
        if isDoubleBattle() then
            if battlerSlot == 1 then
                minSlot, maxSlot = 0, PARTY_SIZE / 2 - 1
            else
                minSlot, maxSlot = PARTY_SIZE / 2, PARTY_SIZE - 1
            end
        end
        if partySlot and partySlot >= minSlot and partySlot <= maxSlot then
            pendingAction[battlerSlot] = {
                action = "switch",
                partySlot = partySlot
            }
            console:log("[client] received action: battler " .. battlerSlot .. " switch to slot " .. partySlot)
        else
            console:log("[client] rejected out-of-range partySlot: " .. tostring(partySlot))
        end
    elseif action == "item" then
        local itemId = tonumber(line:match('"itemId"%s*:%s*(%d+)'))
        local hasRemaining = false
        if itemId then
            for _, entry in ipairs(remainingItemCounts(battlerSlot)) do
                if entry.itemId == itemId then
                    hasRemaining = true
                    break
                end
            end
        end
        if hasRemaining then
            pendingAction[battlerSlot] = {
                action = "item",
                itemId = itemId
            }
            console:log("[client] received action: battler " .. battlerSlot .. " item " .. itemId)
        else
            console:log("[client] rejected item choice (none remaining or unsupported): " .. tostring(itemId))
        end
    end
end

-- Player 1's battle-log entries (both their mons, battlers 0 and 2) are held back until Player 2
-- has committed every enemy battler's choice for the turn, so Player 2 can't see Player 1's move
-- before answering. Player 2's own entries (battlers 1 and 3) are never delayed.
local function isPlayerOneBattler(battler)
    return battler == 0 or battler == 2
end

local function emitBattleLog(battler, jsonLine)
    if isPlayerOneBattler(battler) and not allEnemyBattlersCommitted() then
        table.insert(pendingPlayerLogEntries, jsonLine)
    else
        sendJSON(jsonLine)
    end
end

-- Queues raw data rather than a pre-built JSON string -- damage isn't known until the move
-- actually resolves (flush time), so the JSON can't be assembled yet. damage starts nil and
-- accumulates across however many hits the move ends up dealing (see accumulateMoveLogDamage) --
-- a multi-hit move like Double Kick fires several separate HP changes for the SAME queued entry
-- before it's finally flushed.
local function queueMoveLog(battler, moveId, speciesId)
    pendingMoveLog[battler] = {
        moveId = moveId,
        speciesId = speciesId,
        damage = nil
    }
end

-- Adds one hit's worth of HP delta to attacker's still-queued entry, without sending anything yet
-- -- multi-hit moves call this once per hit. Usually positive (damage taken by the target); can be
-- negative if `attacker` is healing itself via a draining move rather than damaging the target --
-- the interface displays that as healing, not damage.
local function accumulateMoveLogDamage(attacker, delta)
    local entry = pendingMoveLog[attacker]
    if not entry then
        return
    end
    entry.damage = (entry.damage or 0) + delta
end

-- Sends `attacker`'s queued move log entry, if any, with whatever damage has accumulated so far
-- (see accumulateMoveLogDamage). Called once the move is confirmed done resolving -- the next
-- "X used Y!" for any battler, battle text confirming a miss, or the safety-net flush in
-- onOpponentHandleChooseAction -- not on every individual HP change, so a multi-hit move's several
-- hits all land in the same log entry instead of only the first one being reported.
local function flushMoveLog(attacker, missed, noEffect)
    local entry = pendingMoveLog[attacker]
    if not entry then
        return
    end
    pendingMoveLog[attacker] = nil
    local extraField = missed and ',"missed":true' or noEffect and ',"noEffect":true' or
                           (entry.damage and string.format(',"damage":%d', entry.damage)) or ""
    emitBattleLog(attacker, string.format('{"type":"battle_log","battler":%d,"event":"move","moveId":%d,"speciesId":%d%s}',
        attacker, entry.moveId, entry.speciesId, extraField))
end

-- Discards battler `battler`'s own still-queued entry
local function discardMoveLog(battler)
    pendingMoveLog[battler] = nil
end

local function isInBattle()
    return (emu:read8(ADDR_GMAIN_IN_BATTLE) & MASK_GMAIN_IN_BATTLE) ~= 0
end

-- Returns the GBA player's own trainer name, or nil if the save data isn't loaded yet.
local function decodePlayerName()
    local saveBlock2 = emu:read32(ADDR_SAVE_BLOCK2_PTR)
    if saveBlock2 == 0 then
        return nil
    end
    local chars = {}
    for i = 0, PLAYER_NAME_LENGTH - 1 do
        local byte = emu:read8(saveBlock2 + i)
        if byte == GEN3_STRING_TERMINATOR then
            break
        end
        chars[#chars + 1] = GEN3_CHARMAP[byte] or "?"
    end
    local name = table.concat(chars)
    if name == "" then
        return nil
    end
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
            return
        end

        local f = io.open(SCREENSHOT_PATH, "rb")
        if not f then
            console:log("[client] could not reopen screenshot scratch file for reading")
            return
        end
        local bytes = f:read("*a")
        f:close()
        if not bytes or #bytes == 0 then
            console:log("[client] screenshot scratch file was empty")
            return
        end

        sendJSON('{"type":"screen_frame","data":"' .. base64Encode(bytes) .. '"}')
    end)
    if not ok then
        console:log("[client] screenshot error: " .. tostring(err))
    end
end

local function sendPlayerNameIfNeeded()
    if playerNameSent then
        return
    end
    local name = decodePlayerName()
    if name then
        sendJSON('{"type":"player_info","name":"' .. name .. '"}')
        playerNameSent = true
        console:log("[client] sent player name: " .. name)
    end
end

-- Player 2 only ever influences trainer battles -- wild encounters play out untouched.
local BATTLE_TYPE_DOUBLE = 0x1

local function isControllableBattle()
    if not isInBattle() then
        return false
    end
    local flags = emu:read32(ADDR_BATTLE_TYPE_FLAGS)
    return (flags & BATTLE_TYPE_TRAINER) ~= 0
end

isDoubleBattle = function()
    if not isInBattle() then
        return false
    end
    return (emu:read32(ADDR_BATTLE_TYPE_FLAGS) & BATTLE_TYPE_DOUBLE) ~= 0
end

-- True once every enemy battler active this battle has committed its choice for the turn (a
-- single-battler singles battle just checks battler 1; a double battle needs both 1 and 3).
allEnemyBattlersCommitted = function()
    if isDoubleBattle() then
        return player2Committed[1] and player2Committed[3]
    end
    return player2Committed[1]
end

local function decodeGen3Bytes(addr, maxChars)
    local chars = {}
    for i = 0, maxChars - 1 do
        local byte = emu:read8(addr + i)
        if byte == GEN3_STRING_TERMINATOR then
            break
        end
        chars[#chars + 1] = GEN3_CHARMAP[byte] or "?"
    end
    return table.concat(chars)
end

-- Replaces the current trainer's real name with Player 2's chosen one, wherever it appears in
-- battle text. Runs on every piece of battle text the game prints, so it's a no-op whenever the
-- trainer's name doesn't actually appear in the text being drawn.
local BATTLE_TEXT_SEARCH_WINDOW = 64 -- generous for a single printed line/message

local function substitutePlayer1TrainerName(bufferAddr)
    if player2Name == "Player 2" then
        return
    end -- no custom name set, nothing to do
    local trainerId = emu:read16(ADDR_TRAINER_BATTLE_OPPONENT_A)
    if trainerId == 0 then
        return
    end -- TRAINER_NONE

    local realName = decodeGen3Bytes(ADDR_GTRAINERS + trainerId * TRAINER_STRUCT_SIZE + TRAINER_NAME_OFFSET,
        TRAINER_NAME_MAX_CHARS)
    if realName == "" then
        return
    end

    local haystack = decodeGen3Bytes(bufferAddr, BATTLE_TEXT_SEARCH_WINDOW)
    local matchStart = haystack:find(realName, 1, true)
    if not matchStart then
        return
    end

    -- Replacement must be exactly realName's length so nothing after it in the buffer shifts.
    local replacement = player2Name:sub(1, #realName)
    replacement = replacement .. string.rep(" ", #realName - #replacement)
    local bytes = encodeGen3Bytes(replacement, #realName)
    table.remove(bytes) -- drop the terminator -- we're writing mid-buffer, not ending the string
    for i, byte in ipairs(bytes) do
        emu:write8(bufferAddr + matchStart - 1 + i - 1, byte)
    end
end

-- Tracks which battler's turn is currently being narrated in battle text, so a "missed" message
-- (which carries no battler info by itself) can be attributed to the right one.
local currentlyResolvingBattler = nil

-- Battle text mentioning any of these gets forwarded to the browser as a battle-log "text" event
-- verbatim, rather than trying to build a precise data model for every individual effect (stat
-- stages, confusion, flinch, and the various status-condition messages all have several different
-- phrasings each) -- the game's own text already says exactly what happened.
local INTERESTING_TEXT_KEYWORDS = {
    "rose!", "fell!", "won't go any higher", "won't go any lower",
    "flinched", "confus", "fully paralyzed", "frozen solid",
    "fast asleep", "woke up", "hurt by", "poisoned!", "burned!", "paralyzed!",
}

local function cleanBattleText(text)
    local cleaned = text:gsub("?", " "):gsub("%s+", " ")
    return cleaned:gsub("^%s+", ""):gsub("%s+$", "")
end

local function jsonEscapeString(text)
    return (text:gsub('[\\"]', "\\%0"))
end

-- Attributed to currentlyResolvingBattler when known (held back like any other battler-0/2 entry
-- until Player 2 has committed, via emitBattleLog); sent immediately, unattributed, otherwise --
-- e.g. weather/residual damage messages that aren't narrating any particular battler's move.
local function forwardInterestingBattleText(text)
    for _, keyword in ipairs(INTERESTING_TEXT_KEYWORDS) do
        if text:find(keyword, 1, true) then
            local cleaned = cleanBattleText(text)
            if currentlyResolvingBattler ~= nil then
                emitBattleLog(currentlyResolvingBattler, string.format(
                    '{"type":"battle_log","battler":%d,"event":"text","text":"%s"}',
                    currentlyResolvingBattler, jsonEscapeString(cleaned)))
            else
                sendJSON(string.format(
                    '{"type":"battle_log","battler":null,"event":"text","text":"%s"}',
                    jsonEscapeString(cleaned)))
            end
            return
        end
    end
end

local function onBattlePutTextOnWindow()
    if not isControllableBattle() then
        return
    end
    local ok, err = pcall(function()
        local textAddr = emu:readRegister("r0")
        local text = decodeGen3Bytes(textAddr, BATTLE_TEXT_SEARCH_WINDOW)
        if text:find(" used ", 1, true) then
            -- gActiveBattler is reused by the engine as "current attacker" during move execution
            -- text, not just AI decisions -- confirmed live, exactly matching the actual attacker
            -- (0/1/2/3) every time across a real double battle turn. Far more robust than parsing
            -- the name out of the text itself, which breaks the moment two mons share a name.
            -- Flush whatever was still queued for the PREVIOUS attacker first -- a new move
            -- starting to narrate means the last one is definitely done resolving (covers a
            -- multi-hit move's accumulated damage, and a status move that never changed any HP).
            if currentlyResolvingBattler ~= nil then
                flushMoveLog(currentlyResolvingBattler)
            end
            currentlyResolvingBattler = emu:read8(ADDR_ACTIVE_BATTLER)
            -- Marks this attacker's queued entry as having actually started executing, so a faint
            -- later this same turn (see checkBattleLog) knows to flush it instead of discarding it
            -- as an unstarted "ghost" move.
            local resolvingEntry = pendingMoveLog[currentlyResolvingBattler]
            if resolvingEntry then
                resolvingEntry.started = true
            end
        elseif text:find("missed", 1, true) and currentlyResolvingBattler ~= nil then
            flushMoveLog(currentlyResolvingBattler, true)
            currentlyResolvingBattler = nil
        elseif text:find("doesn't affect", 1, true) or text:find("had no effect", 1, true) then
            if currentlyResolvingBattler ~= nil then
                flushMoveLog(currentlyResolvingBattler, false, true)
                currentlyResolvingBattler = nil
            end
        end
        forwardInterestingBattleText(text)
        substitutePlayer1TrainerName(textAddr)
    end)
    if not ok then
        console:log("[client] battle text handling error: " .. tostring(err))
    end
end

local STATUS1_SLEEP_MASK = 0x07 -- bits 0-2, a turn counter rather than a single flag -- asleep if nonzero
local STATUS1_POISON = 0x08
local STATUS1_BURN = 0x10
local STATUS1_FREEZE = 0x20
local STATUS1_PARALYSIS = 0x40
local STATUS1_TOXIC_POISON = 0x80
-- Confusion lives in status2 (a separate field, offset 0x50 -- confirmed from source), not
-- status1 -- a mon can be confused independently of (or alongside) a status1 condition. Same
-- "nonzero turn counter" shape as the sleep mask.
local STATUS2_CONFUSION_MASK = 0x07

-- Decodes gBattleMons[].status1/status2 into a short label, or nil if healthy. status1 (the
-- "major" conditions) takes priority for display when a mon happens to have both.
local function decodeStatus(status1, status2)
    if status1 & STATUS1_FREEZE ~= 0 then
        return "frozen"
    end
    if status1 & STATUS1_TOXIC_POISON ~= 0 then
        return "badly poisoned"
    end
    if status1 & STATUS1_POISON ~= 0 then
        return "poisoned"
    end
    if status1 & STATUS1_BURN ~= 0 then
        return "burned"
    end
    if status1 & STATUS1_PARALYSIS ~= 0 then
        return "paralyzed"
    end
    if status1 & STATUS1_SLEEP_MASK ~= 0 then
        return "asleep"
    end
    if status2 & STATUS2_CONFUSION_MASK ~= 0 then
        return "confused"
    end
    return nil
end

local function readActiveMon(base)
    local species = emu:read16(base + 0x00)
    local hp = emu:read16(base + 0x28)
    local level = emu:read8(base + 0x2A)
    local maxHp = emu:read16(base + 0x2C)
    local status1 = emu:read32(base + 0x4C)
    local status2 = emu:read32(base + 0x50)
    local personality = emu:read32(base + 0x48)
    return species, hp, maxHp, level, status1, personality, status2
end

local function readNickname(partyMonBase)
    return decodeGen3Bytes(partyMonBase + NICKNAME_OFFSET, NICKNAME_MAX_CHARS)
end

-- moves/pp: decrypted from the Attacks substructure the same way species is decrypted from
-- Growth -- 3 encrypted u32 words (moves 1-2, moves 3-4, pp 1-4), XORed with the same key,
-- located at whichever of the 4 substructure slots ATTACKS_SLOT_BY_PID24 says for this mon's
-- personality.
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
    local nickname = readNickname(base)

    local attacksSlot = ATTACKS_SLOT_BY_PID24[personality % 24]
    local attacksBase = base + 0x20 + attacksSlot * 12
    local movesWord0 = emu:read32(attacksBase + 0) ~ key
    local movesWord1 = emu:read32(attacksBase + 4) ~ key
    local ppWord = emu:read32(attacksBase + 8) ~ key
    local moves = {
        movesWord0 & 0xFFFF,
        (movesWord0 >> 16) & 0xFFFF,
        movesWord1 & 0xFFFF,
        (movesWord1 >> 16) & 0xFFFF,
    }
    local pp = {
        ppWord & 0xFF,
        (ppWord >> 8) & 0xFF,
        (ppWord >> 16) & 0xFF,
        (ppWord >> 24) & 0xFF,
    }

    return species, hp, maxHp, level, nickname, personality, moves, pp
end

-- Formats an optional string as a JSON string literal, or the bare `null` token when absent
local function jsonOptionalString(value)
    if value == nil then
        return "null"
    end
    return '"' .. value .. '"'
end

-- battler: restricts which half of gEnemyParty is included, for a double battle against two
-- separate trainers -- confirmed from source (CreateNPCTrainerParty(&gEnemyParty[3],
-- gTrainerBattleOpponent_B, ...)) that trainer A's 3 mons occupy slots 0-2 and trainer B's occupy
-- 3-5. Without this, both enemy battlers' switch lists showed all 6 mons combined, including the
-- OTHER battler's own already-active mon as if it were a valid switch-in target. Singles (battler
-- 1, not a double battle) shows all 6 slots as before -- there's only one trainer, no split to make.
local function buildPartyJSON(baseAddr, battler)
    local startSlot, endSlot = 0, PARTY_SIZE - 1
    if isDoubleBattle() then
        if battler == 1 then
            startSlot, endSlot = 0, PARTY_SIZE / 2 - 1
        elseif battler == 3 then
            startSlot, endSlot = PARTY_SIZE / 2, PARTY_SIZE - 1
        end
    end
    local parts = {}
    for i = startSlot, endSlot do
        local species, hp, maxHp, level, nickname, personality, moves, pp = readPartyMon(baseAddr + i * PARTY_MON_SIZE)
        if species ~= 0 then
            table.insert(parts, string.format(
                '{"partySlot":%d,"species":%d,"hp":%d,"maxHp":%d,"level":%d,"nickname":"%s","gender":%s,'
                .. '"moveIds":[%d,%d,%d,%d],"pp":[%d,%d,%d,%d]}',
                i, species, hp, maxHp, level, nickname, jsonOptionalString(computeGender(species, personality)),
                moves[1], moves[2], moves[3], moves[4], pp[1], pp[2], pp[3], pp[4]))
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- Finds which party slot holds the mon currently on the battlefield, by matching personality
-- against gBattleMons's authoritative data
local function findActivePartySlot(partyBase, personality)
    for i = 0, PARTY_SIZE - 1 do
        local slotPersonality = emu:read32(partyBase + i * PARTY_MON_SIZE)
        if slotPersonality == personality then
            return i
        end
    end
    return 0 -- shouldn't happen with a valid personality, but never return nil
end

-- msgType: "battle_state" for a genuine new decision request ("your turn"), "battle_update" for a
-- passive HP/status refresh. mustSwitch: true when the enemy's active mon just fainted and
-- Player 2 may only pick a replacement this turn.

-- Builds a single ActiveMon JSON object (species/hp/maxHp/level/nickname/status/gender) for the
-- mon at `monBase` (a gBattleMons[] entry), looking its nickname up in `partyBase` (gEnemyParty or
-- gPlayerParty, whichever side `monBase` belongs to).
local function buildActiveMonJSON(monBase, partyBase)
    local species, hp, maxHp, level, status1, personality, status2 = readActiveMon(monBase)
    local partySlot = findActivePartySlot(partyBase, personality)
    local nickname = readNickname(partyBase + partySlot * PARTY_MON_SIZE)
    return string.format(
        '{"species":%d,"hp":%d,"maxHp":%d,"level":%d,"nickname":"%s","status":%s,"gender":%s}',
        species, hp, maxHp, level, nickname, jsonOptionalString(decodeStatus(status1, status2)),
        jsonOptionalString(computeGender(species, personality)))
end

-- Only items this project actually knows how to inject (see ITEM_AI_CLASSIFICATION) are offered
-- to Player 2, even if the trainer happens to carry something else too. Grouped by item ID with a
-- count -- a trainer carrying two Potions in separate slots should show "Potion" once, with count 2.
local function buildAvailableItemsJSON(battler)
    local parts = {}
    for _, entry in ipairs(remainingItemCounts(battler)) do
        parts[#parts + 1] = string.format('{"itemId":%d,"count":%d}', entry.itemId, entry.count)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- battler: which enemy battler (1, or 3 in a double battle) this state is for. The JSON's
-- "battlerSlot" field lets a doubles-aware client match this message to the right prompt when two
-- may be in flight at once. "playerActive" always reflects battler 0; "playerActive2" is battler
-- 2's mon (null outside a double battle), so a doubles-aware client can show both of Player 1's
-- mons and let Player 2 pick which one to target.
local function extractEnemyState(msgType, battler, mustSwitch)
    local moveIds = {}
    local pp = {}
    local movesBase = battlerMovesBase(battler)
    local ppBase = battlerPPBase(battler)
    for i = 0, 3 do
        moveIds[i + 1] = emu:read16(movesBase + i * 2)
        pp[i + 1] = emu:read8(ppBase + i)
    end
    local _, _, _, _, _, ePersonality = readActiveMon(battlerMonBase(battler))
    local activePartySlot = findActivePartySlot(ADDR_GENEMY_PARTY, ePersonality)
    local playerActive2JSON = "null"
    if isDoubleBattle() then
        playerActive2JSON = buildActiveMonJSON(battlerMonBase(2), ADDR_GPLAYER_PARTY)
    end
    return string.format(
        '{"type":"%s","battlerSlot":%d,"mustSwitch":%s,"enemyMoveIds":[%d,%d,%d,%d],"pp":[%d,%d,%d,%d],' ..
            '"enemyActive":%s,' .. '"playerActive":%s,' .. '"playerActive2":%s,' .. '"enemyActivePartySlot":%d,' ..
            '"enemyParty":%s,' .. '"availableItems":%s}', msgType, battler, mustSwitch and "true" or "false",
        moveIds[1], moveIds[2], moveIds[3], moveIds[4], pp[1], pp[2], pp[3], pp[4],
        buildActiveMonJSON(battlerMonBase(battler), ADDR_GENEMY_PARTY),
        buildActiveMonJSON(ADDR_PLAYER_ACTIVE, ADDR_GPLAYER_PARTY), playerActive2JSON, activePartySlot,
        buildPartyJSON(ADDR_GENEMY_PARTY, battler), buildAvailableItemsJSON(battler))
end

-- Holds each enemy battler's action-type decision (fight/switch/item) until Player 2 answers for
-- it. Fires once per enemy battler each turn (twice in a double battle, once for battler 1 and
-- once for battler 3, confirmed live) -- gActiveBattler tells us which one this particular call is
-- for, so each battler gets its own independent slice of all the decision state below.
local function onOpponentHandleChooseAction()
    if not isControllableBattle() then
        awaitingAction = {}
        return
    end

    local battler = emu:read8(ADDR_ACTIVE_BATTLER)

    if not awaitingAction[battler] then
        -- Safety net: a status/stat move with no HP change never gets flushed by the "next move
        -- starts narrating" trigger in onBattlePutTextOnWindow if it was the LAST move of the
        -- turn, and would otherwise sit queued forever.
        flushMoveLog(0)
        flushMoveLog(1)
        flushMoveLog(2)
        flushMoveLog(3)
        currentlyResolvingBattler = nil

        awaitingAction[battler] = true
        pendingAction[battler] = nil
        steeringArmed[battler] = false
        awaitingReplacement[battler] = false
        voluntarySwitchSlot[battler] = nil
        player2Committed[battler] = false
        flushPendingPlayerLogEntries()
        -- These are shared across both enemy battlers (the "waiting for your move" message is one
        -- message, not one per battler) -- only reset them when battler 1 starts a fresh turn
        -- cycle, since it's always the first of the two to fire each turn. Resetting them again
        -- moments later when battler 3 also starts its own cycle would clear playerActionReady
        -- right as (or just before) it was about to flip true, and the message would never draw.
        if battler == 1 then
            playerActionReady = false
            player1Battler0Ready = false
            player1Battler2Ready = false
            battleMessageShown = false
        end
        console:log("[client] enemy battler " .. battler .. " choosing action, notifying Player 2 (waiting...)")
        -- pcall-wrapped: an exception here would otherwise silently swallow this send with no
        -- visible error, since this breakpoint isn't normally pcall-protected.
        local ok, jsonOrErr = pcall(extractEnemyState, "battle_state", battler)
        if ok then
            sendJSON(jsonOrErr)
        else
            console:error("[client] extractEnemyState threw: " .. tostring(jsonOrErr))
        end
    end

    if not playerActionReady then
        if not player1Battler0Ready then
            local commState = emu:read8(ADDR_BATTLE_COMMUNICATION_0)
            if commState > STATE_WAIT_ACTION_CASE_CHOSEN and lastPlayerCommState <= STATE_WAIT_ACTION_CASE_CHOSEN then
                player1Battler0Ready = true
            end
            lastPlayerCommState = commState
        end
        if isDoubleBattle() and not player1Battler2Ready then
            local commState2 = emu:read8(battlerCommAddr(2))
            if commState2 > STATE_WAIT_ACTION_CASE_CHOSEN and lastPlayerCommState2 <= STATE_WAIT_ACTION_CASE_CHOSEN then
                player1Battler2Ready = true
            end
            lastPlayerCommState2 = commState2
        end
        if player1Battler0Ready and (player1Battler2Ready or not isDoubleBattle()) then
            playerActionReady = true
        end
    end

    if pendingAction[battler] == nil then
        if playerActionReady and not battleMessageShown then
            battleMessageShown = true
            showBattleMessage("Waiting for " .. player2Name .. "'s move...")
        else
            local lr = emu:readRegister("lr")
            emu:writeRegister("pc", lr)
        end
    else
        if pendingAction[battler].action == "switch" then
            -- The AI's own switch path never writes the action byte the game expects here, so we
            -- write it ourselves -- otherwise the engine hangs waiting for it.
            emu:write8(battlerBufferBase(battler) + 1, B_ACTION_SWITCH)
            voluntarySwitchSlot[battler] = pendingAction[battler].partySlot
        end
        steeringArmed[battler] = true
        awaitingAction[battler] = false
    end
end

-- How many of `battler`'s own trainer's party members are still alive and not already active
-- (both 1 and 3's own active slots are excluded, even though only one of them belongs to
-- `battler`'s own team -- harmless, since the other one isn't in `battler`'s half anyway). With
-- fewer than 2, there's no real choice to make (one option, or the battle's over), so it's not
-- worth prompting Player 2 for it. Restricted to `battler`'s own half of gEnemyParty in a double
-- battle, same split as buildPartyJSON -- otherwise this would count the OTHER trainer's bench
-- mons as valid replacements for a battler that can't actually switch into them. Uses
-- findActivePartySlot's personality-based matching (already proven battler-generic) rather than
-- ADDR_ENEMY_PARTY_INDEX, since that address's battler-3 equivalent hasn't been live-verified --
-- this sidesteps needing it at all.
local function countAliveNonActiveEnemyMons(battler)
    local activeSlots = {}
    local _, _, _, _, _, personality1 = readActiveMon(battlerMonBase(1))
    activeSlots[findActivePartySlot(ADDR_GENEMY_PARTY, personality1)] = true
    local startSlot, endSlot = 0, PARTY_SIZE - 1
    if isDoubleBattle() then
        local _, _, _, _, _, personality3 = readActiveMon(battlerMonBase(3))
        activeSlots[findActivePartySlot(ADDR_GENEMY_PARTY, personality3)] = true
        if battler == 1 then
            startSlot, endSlot = 0, PARTY_SIZE / 2 - 1
        elseif battler == 3 then
            startSlot, endSlot = PARTY_SIZE / 2, PARTY_SIZE - 1
        end
    end
    local count = 0
    for i = startSlot, endSlot do
        if not activeSlots[i] then
            local species, hp = readPartyMon(ADDR_GENEMY_PARTY + i * PARTY_MON_SIZE)
            if species ~= 0 and hp > 0 then
                count = count + 1
            end
        end
    end
    return count
end

-- Holds an unprompted "choose a replacement" call (i.e. an enemy battler's mon just fainted)
-- until Player 2 answers for that battler. Left alone if this is actually the follow-through of a
-- voluntary switch (already handled above) or we're already mid-hold elsewhere for this battler.
local function onOpponentHandleChoosePokemon()
    if not isControllableBattle() then
        awaitingReplacement = {}
        return
    end

    local battler = emu:read8(ADDR_ACTIVE_BATTLER)

    if voluntarySwitchSlot[battler] ~= nil then
        local slot = voluntarySwitchSlot[battler]
        voluntarySwitchSlot[battler] = nil
        pendingAction[battler] = {
            action = "switch",
            partySlot = slot
        }
        steeringArmed[battler] = true
        return
    end
    if steeringArmed[battler] or awaitingAction[battler] then
        return
    end
    if countAliveNonActiveEnemyMons(battler) < 2 then
        awaitingReplacement[battler] = false
        return
    end

    if not awaitingReplacement[battler] then
        awaitingReplacement[battler] = true
        pendingAction[battler] = nil
        console:log("[client] enemy battler " .. battler ..
                        "'s mon fainted, notifying Player 2 for a replacement (waiting...)")
        sendJSON(extractEnemyState("battle_state", battler, true))
        showBattleMessage("Waiting for " .. player2Name .. " to pick a replacement...")
        return
    end

    -- Only a "switch" choice is valid here -- a "move"/"item" choice would arm steering without
    -- actually forcing a party slot in onGetMostSuitableMon (it only does that for action=="switch"),
    -- silently letting the AI's own unintercepted logic pick the replacement instead. Rejecting
    -- anything else here (rather than trusting the interface to only ever send a switch while a
    -- replacement is pending) keeps that mismatch from ever reaching that point.
    if pendingAction[battler] ~= nil and pendingAction[battler].action ~= "switch" then
        console:error("[client] rejected non-switch action while a replacement was pending for battler " .. battler)
        pendingAction[battler] = nil
    end

    if pendingAction[battler] == nil then
        local lr = emu:readRegister("lr")
        emu:writeRegister("pc", lr)
    else
        steeringArmed[battler] = true
        awaitingReplacement[battler] = false
    end
end

local function onShouldSwitch()
    local battler = emu:read8(ADDR_ACTIVE_BATTLER)
    if not steeringArmed[battler] then
        return
    end
    if pendingAction[battler] and pendingAction[battler].action == "switch" then
        emu:writeRegister("r0", 1)
    else
        emu:writeRegister("r0", 0)
    end
    local lr = emu:readRegister("lr")
    emu:writeRegister("pc", lr)
end

local function onGetMostSuitableMon()
    local battler = emu:read8(ADDR_ACTIVE_BATTLER)
    if not steeringArmed[battler] then
        return
    end
    if pendingAction[battler] and pendingAction[battler].action == "switch" and pendingAction[battler].partySlot ~= nil then
        emu:writeRegister("r0", pendingAction[battler].partySlot)
        local lr = emu:readRegister("lr")
        emu:writeRegister("pc", lr)
    end
    steeringArmed[battler] = false
    pendingAction[battler] = nil
    player2Committed[battler] = true
    -- Only actually reveal the held-back queue once BOTH enemy battlers have committed (in
    -- doubles) -- flushPendingPlayerLogEntries() itself sends unconditionally, so calling it the
    -- moment just ONE of the two battlers commits would show Player 1's move for the OTHER,
    -- still-undecided battler early.
    if allEnemyBattlersCommitted() then
        flushPendingPlayerLogEntries()
    end
end

-- Injects Player 2's chosen item once the AI's own decision point is reached, mirroring
-- ShouldUseItem()'s own "use item" side effects (see ITEM_AI_CLASSIFICATION above for why we
-- can't just let the real function decide). Denies (same as before item support existed) whenever
-- Player 2 chose a move or switch instead, so the AI can't sneak in an item use of its own.
-- Battler 3 is always denied for now -- see ADDR_CHOSEN_ITEM's comment, item support isn't
-- extended there yet (needs gTrainerBattleOpponent_B, not yet discovered).
local function onShouldUseItem()
    local battler = emu:read8(ADDR_ACTIVE_BATTLER)
    if not steeringArmed[battler] then
        return
    end

    if battler == 1 and pendingAction[battler] and pendingAction[battler].action == "item" and
        pendingAction[battler].itemId then
        local itemId = pendingAction[battler].itemId
        local classification = ITEM_AI_CLASSIFICATION[itemId]
        if classification then
            emu:write8(ADDR_CHOSEN_ITEM, itemId)
            emu:write8(ADDR_AI_ITEM_TYPE, classification.itemType)
            emu:write8(ADDR_AI_ITEM_FLAGS, classification.itemFlags or 0)
            emu:write8(ADDR_GBATTLE_BUFFER_B1, CONTROLLER_TWORETURNVALUES)
            emu:write8(ADDR_GBATTLE_BUFFER_B1 + 1, B_ACTION_USE_ITEM)
            emu:writeRegister("r0", 1)
            local lr = emu:readRegister("lr")
            emu:writeRegister("pc", lr)

            console:log("[client] injected item " .. itemId)
            usedItemCounts[1][itemId] = (usedItemCounts[1][itemId] or 0) + 1
            pendingAction[battler] = nil
            steeringArmed[battler] = false
            player2Committed[battler] = true
            if allEnemyBattlersCommitted() then
                flushPendingPlayerLogEntries()
            end
            return
        end
        console:error("[client] no AI classification for item " .. itemId .. " -- denying")
    end

    emu:writeRegister("r0", 0)
    local lr = emu:readRegister("lr")
    emu:writeRegister("pc", lr)
end

-- Injects Player 2's already-decided move for `battler` once its own buffer reaches the point
-- where the game expects one. Deliberately does NOT gate on gActiveBattler -- this breakpoint
-- fires every single frame (confirmed), not once per battler decision like the AI decision
-- functions do, so gActiveBattler isn't reliably `battler` at the exact frame this battler's
-- buffer happens to become ready (it drifts as other engine code touches it for unrelated
-- reasons). Checking the buffer's own state directly instead is what the original singles-only
-- version already did, correctly -- gating on gActiveBattler here was the doubles regression that
-- broke singles (a move could miss its injection window and silently fall back to whatever the
-- AI had already picked).
local function tryInjectMoveForBattler(battler)
    if not (pendingAction[battler] and pendingAction[battler].action == "move") then
        return
    end

    local commAddr = battlerCommAddr(battler)
    local bufferBase = battlerBufferBase(battler)
    local enemyState = emu:read8(commAddr)
    local header = emu:read8(bufferBase)
    local action = emu:read8(bufferBase + 1)

    local enemyDecisionPending =
        (enemyState == STATE_WAIT_ACTION_CASE_CHOSEN and header == CONTROLLER_TWORETURNVALUES and action ==
            B_ACTION_EXEC_SCRIPT)

    if not enemyDecisionPending then
        return
    end

    local moveIndex = pendingAction[battler].moveIndex
    local target = pendingAction[battler].target or PLAYER_BATTLER_INDEX
    emu:write8(bufferBase + 2, moveIndex) -- move slot
    emu:write8(bufferBase + 3, target)
    console:log("[client] injected battler " .. battler .. " move " .. moveIndex)
    pendingAction[battler] = nil
    steeringArmed[battler] = false

    player2Committed[battler] = true
    if allEnemyBattlersCommitted() then
        flushPendingPlayerLogEntries()
    end

    -- Log Player 2's move directly, using the move slot we just injected, rather than through the
    -- same gBattleCommunication-based edge-detection used for Player 1. That detector can fire for
    -- reasons unrelated to a genuine decision (e.g. during battle setup), which read whatever
    -- gChosenMoveByBattler[battler] happened to still hold from a previous battle and logged it as
    -- if it just happened.
    local moveId = emu:read16(battlerMovesBase(battler) + moveIndex * 2)
    local species = emu:read16(battlerMonBase(battler))
    queueMoveLog(battler, moveId, species)
end

local function onHandleTurnActionSelection()
    if not isControllableBattle() then
        return
    end
    tryInjectMoveForBattler(1)
    if isDoubleBattle() then
        tryInjectMoveForBattler(3)
    end
end

local wasInBattle = false
local heartbeatCounter = 0

-- Battle log: tracks each of the 4 battlers' move/switch decisions and sends them to the browser.
-- Player 1's entries (battlers 0/2) are held back until Player 2 has committed every enemy
-- battler's choice for the turn, so Player 2 can't see Player 1's move before answering. Real
-- values seeded by resetBattleLog() on battle start.
local lastCommState = {}
local lastBattlerPersonality = {}

flushPendingPlayerLogEntries = function()
    for _, jsonLine in ipairs(pendingPlayerLogEntries) do
        sendJSON(jsonLine)
    end
    pendingPlayerLogEntries = {}
end

local function logMove(battler)
    local moveId = emu:read16(ADDR_CHOSEN_MOVE_BY_BATTLER + battler * 2)
    if moveId == 0 then
        return
    end
    local species = emu:read16(battlerMonBase(battler) + 0x00)
    queueMoveLog(battler, moveId, species)
end

-- Player 1's moves are detected here (we don't control their input, only observe it), for both of
-- their own battlers (0, and 2 in a double battle). Player 2's moves are logged directly at the
-- moment we inject them (see onHandleTurnActionSelection) instead -- this same
-- gBattleCommunication-based detection can cross its threshold for reasons unrelated to a genuine
-- decision (e.g. during battle setup), which produced false log entries from whatever
-- gChosenMoveByBattler[battler] happened to still hold from a previous battle.
local function checkBattleLog()
    for _, battler in ipairs({0, 2}) do
        local commState = emu:read8(battlerCommAddr(battler))
        if commState > STATE_WAIT_ACTION_CASE_CHOSEN and (lastCommState[battler] or 0) <= STATE_WAIT_ACTION_CASE_CHOSEN then
            local action = emu:read8(ADDR_CHOSEN_ACTION_BY_BATTLER + battler)
            if action == B_ACTION_USE_MOVE then
                logMove(battler)
            end
            -- Switches aren't logged here -- caught below via the species-change check instead,
            -- which also covers forced switches after a faint.
        end
        lastCommState[battler] = commState
    end

    -- Switches are detected via gBattleMons's personality actually changing. All 4 battler slots
    -- are checked unconditionally (harmless in a single battle -- battlers 2/3 just hold static,
    -- unchanging data there, so their personality/HP never actually differs from the first read).
    for battler = 0, 3 do
        local base = battlerMonBase(battler)
        local species = emu:read16(base + 0x00)
        local personality = emu:read32(base + 0x48)
        local hp = emu:read16(base + 0x28)

        if personality ~= (lastBattlerPersonality[battler] or -1) then
            local wasFirstRead = lastBattlerPersonality[battler] == nil
            lastBattlerPersonality[battler] = personality
            -- The switched-in mon's full HP must not be misread next frame as "took damage" --
            -- reset this battler's HP baseline too.
            lastMoveLogHp[battler] = hp
            if not wasFirstRead and species ~= 0 then
                emitBattleLog(battler, string.format(
                    '{"type":"battle_log","battler":%d,"event":"switch","speciesId":%d}', battler, species))
            end
        elseif hp ~= lastMoveLogHp[battler] then
            local previousHp = lastMoveLogHp[battler]
            local wasFirstRead = previousHp == nil
            lastMoveLogHp[battler] = hp
            if not wasFirstRead then
                -- currentlyResolvingBattler (set from gActiveBattler the moment battle text says
                -- "X used Y!" -- confirmed live to exactly match the real attacker, 0-3, no
                -- ambiguity even between two same-named mons) tells us WHO to credit this HP
                -- change to. A move with no attributable attacker (e.g. end-of-turn poison
                -- damage, no move currently resolving) is correctly left unattributed. Only
                -- accumulated here, not flushed -- a multi-hit move like Double Kick fires several
                -- of these HP changes for the same still-resolving move, and flushing (sending the
                -- JSON) happens once resolution is actually confirmed done: the next "X used Y!"
                -- for any battler, a miss, or the turn-boundary safety net (see
                -- onBattlePutTextOnWindow / onOpponentHandleChooseAction).
                if currentlyResolvingBattler ~= nil then
                    accumulateMoveLogDamage(currentlyResolvingBattler, previousHp - hp)
                end
                if hp == 0 then
                    local ownEntry = pendingMoveLog[battler]
                    if ownEntry and ownEntry.started then
                        flushMoveLog(battler)
                    else
                        discardMoveLog(battler)
                    end
                end
            end
        end
    end
end

local function resetBattleLog()
    -- Seed with the game's REAL current state, not a hardcoded 0 -- gChosenMoveByBattler/
    -- gChosenActionByBattler never get cleared between battles, so a fake low baseline makes
    -- the very first check see a false "just happened" transition into that stale leftover data.
    lastCommState = {
        [0] = emu:read8(battlerCommAddr(0)),
        [1] = emu:read8(battlerCommAddr(1)),
        [2] = emu:read8(battlerCommAddr(2)),
        [3] = emu:read8(battlerCommAddr(3))
    }
    lastBattlerPersonality = {}
    pendingMoveLog = {}
    lastMoveLogHp = {}
    currentlyResolvingBattler = nil
    player2Committed = {}
    pendingPlayerLogEntries = {}
    awaitingReplacement = {}
    voluntarySwitchSlot = {}
    usedItemCounts = {
        [1] = {}
    }
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
            -- mustSwitch must reflect whatever onOpponentHandleChoosePokemon last told the
            -- interface, not silently default to false -- leaving it out here was clobbering a
            -- genuine "your Pokemon fainted" state back to normal roughly every half second,
            -- letting the move-selection UI flip back on for a battler that still needed a
            -- replacement chosen.
            sendJSON(extractEnemyState("battle_update", 1, awaitingReplacement[1]))
            if isDoubleBattle() then
                sendJSON(extractEnemyState("battle_update", 3, awaitingReplacement[3]))
            end
        end
    elseif wasInBattle then
        console:log("[client] battle ended, notifying Player 2")
        sendJSON('{"type":"battle_ended"}')
        heartbeatCounter = 0
        resetBattleLog()
    end
    wasInBattle = nowInBattle

    if isControllableBattle() or not streamEnabled then
        screenshotAccumulator = 0
    else
        screenshotAccumulator = screenshotAccumulator + screenshotTargetFps
        if screenshotAccumulator >= GBA_FRAME_RATE then
            screenshotAccumulator = screenshotAccumulator - GBA_FRAME_RATE
            takeScreenshot()
        end
    end
end

local EXPECTED_ROM_CODE = "BPEE"
local romCode = emu:getGameCode()
if romCode ~= EXPECTED_ROM_CODE then
    console:error("[client] ROM mismatch: expected " .. EXPECTED_ROM_CODE .. " (Pokemon Emerald, US), got " ..
                      tostring(romCode) .. " instead. Refusing to run -- memory addresses would misalign.")
    return
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

console:log("[client] PokePVP client.lua loaded (ROM: " .. romCode .. ")")
