-- Konfiguration
local Modem_Side = "top"
local rs_out = "bottom"

-- Statusvariablen für die UI
local last_command = "Kein"
local status = "Warte auf Befehl..."
local tree_count = 0

-- UI Funktion
local function updateUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- Turtle-Steuerung ---")
    term.setCursorPos(1, 3)
    print("Letzter Befehl: " .. last_command)
    term.setCursorPos(1, 4)
    print("Status: " .. status)
    term.setCursorPos(1, 5)
    print("Letzte gesendete Anzahl: " .. tree_count)
end

-- Befehls-Handler
local function handleXCommand()
    status = "Redstone wird aktiviert..."
    updateUI()
    redstone.setOutput(rs_out, true)
    sleep(0.5)
    redstone.setOutput(rs_out, false)
    status = "Redstone-Signal gesendet."
end

local function handleZaehleCommand(target_id, anzahl)
    if not target_id or not anzahl then
        status = "Fehler: ID oder Anzahl fehlt."
        return
    end

    status = "Sende Baum-Anzahl an Turtle..."
    updateUI()
    rednet.send(target_id, tostring(anzahl))
    tree_count = anzahl -- UI-Variable aktualisieren
    status = "Anzahl " .. anzahl .. " an ID " .. target_id .. " gesendet."
end


-- Startup
rednet.open(Modem_Side)
updateUI()

-- Hauptschleife
while true do
    local sender, msg = rednet.receive()
    last_command = msg

    local parts = {}
    for part in string.gmatch(msg, "[^ ]+") do
        table.insert(parts, part)
    end

    local cmd = parts[1]

    if cmd == "x" then
        handleXCommand()
    elseif cmd == "zaehle" then
        local target_id = tonumber(parts[2])
        local anzahl = tonumber(parts[3])
        handleZaehleCommand(target_id, anzahl)
    else
        status = "Unbekannter Befehl."
    end

    updateUI() -- UI nach jeder Aktion aktualisieren
end
