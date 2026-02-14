-- Konfiguration
local MODEM_SIDE = "top"
local RS_OUT_SIDE = "bottom"

-- Statusvariablen für die UI
local status = "Initialisiere..."
local turtle_status = "N/A"
local last_sent_id = "N/A"

-- Eigene ID für die Kommunikation
local controller_id = os.getComputerID()

-- =============================================================================
-- UI und Redstone
-- =============================================================================

local function updateUI()
    local x, y = term.getCursorPos()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- Erweiterte Turtle-Steuerung (ID: " .. controller_id .. ") ---")
    term.setCursorPos(1, 3)
    print("Controller-Status: " .. status)
    term.setCursorPos(1, 4)
    print("Turtle-Status: " .. turtle_status)
    term.setCursorPos(1, 6)
    print("Letzter Befehl an ID: " .. last_sent_id)

    if status == "Bereit für die Eingabe." then
        term.setCursorPos(1, 8)
        print("Turtle ID: ")
        term.setCursorPos(1, 9)
        print("Anzahl Bäume: ")
        term.setCursorPos(1, 10)
        print("Knochenmehl (j/n): ")
    end
    term.setCursorPos(x, y)
end

local function triggerRedstonePulse()
    print("Sende Redstone-Impuls auf Seite: " .. RS_OUT_SIDE)
    redstone.setOutput(RS_OUT_SIDE, true)
    sleep(0.5)
    redstone.setOutput(RS_OUT_SIDE, false)
end

-- =============================================================================
-- Event-Handler
-- =============================================================================

local function handleUserInput(id_str, count_str, bonemeal_str)
    local target_id = tonumber(id_str)
    local count = tonumber(count_str)
    local use_bonemeal = (bonemeal_str:lower() == "j")

    if not target_id or not count then
        status = "Fehler: ID und Anzahl müssen Zahlen sein."
        updateUI()
        sleep(2)
        return
    end

    local command_table = {
        command = "farm",
        count = count,
        use_bonemeal = use_bonemeal,
        controller_id = controller_id
    }

    status = "Sende Befehl an Turtle " .. target_id
    turtle_status = "Warte auf Bestätigung..."
    last_sent_id = tostring(target_id)
    updateUI()

    rednet.send(target_id, textutils.serialize(command_table))
end

local function handleRednetMessage(sender_id, message_str)
    -- Versuche, die Nachricht als Tabelle zu deserialisieren
    local message, err = textutils.unserialize(message_str)
    if not message then message = message_str end -- Wenn es keine Tabelle war, als String behandeln

    if type(message) == "table" and message.command then
        -- Behandle Befehle von der Turtle
        if message.command == "start_waiting" then
            turtle_status = "Wartet auf Baumwachstum..."
            triggerRedstonePulse()
        elseif message.command == "tree_grown" then
            turtle_status = "Baum ist gewachsen!"
            triggerRedstonePulse()
        end
    elseif type(message) == "string" then
        -- Behandle einfache Status-Updates
        turtle_status = message
    end

    -- Wenn eine finale Nachricht empfangen wird, gehe zurück zum Eingabemodus
    if type(message) == "string" and (message:find("abgeschlossen") or message:find("abgebrochen")) then
        status = "Bereit für die Eingabe."
    end

    updateUI()
end

-- =============================================================================
-- Haupt-Event-Schleife
-- =============================================================================

rednet.open(MODEM_SIDE)
status = "Bereit für die Eingabe."

while true do
    updateUI()

    -- Wrapper-Funktionen für parallel.waitForAny
    local function pullRednetEvent()
        local sender, msg = rednet.receive()
        return { "rednet_message", sender, msg }
    end

    local function pullInputEvent()
        if status ~= "Bereit für die Eingabe." then
            -- Blockiere die Eingabe, während die Turtle arbeitet
            return nil
        end
        term.setCursorPos(12, 8)
        local id_str = read()
        term.setCursorPos(16, 9)
        local count_str = read()
        term.setCursorPos(21, 10)
        local bonemeal_str = read()
        return { "user_input", id_str, count_str, bonemeal_str }
    end

    -- Event-Puller dynamisch zusammenstellen
    local event_pullers = { pullRednetEvent }
    if status == "Bereit für die Eingabe." then
        table.insert(event_pullers, pullInputEvent)
    end

    -- Warte auf das nächste Ereignis
    local event, p1, p2, p3 = parallel.waitForAny(unpack(event_pullers))

    if event == "rednet_message" then
        handleRednetMessage(p1, p2)
    elseif event == "user_input" then
        status = "Verarbeite Eingabe..."
        updateUI()
        handleUserInput(p1, p2, p3)
    end
end
