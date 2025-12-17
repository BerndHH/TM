-- Konfiguration
local Modem_Side = "top"

-- Statusvariablen für die UI
local status = "Bereit für die Eingabe."
local last_sent_id = "N/A"
local last_sent_count = "N/A"

-- UI Funktion
local function updateUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- Interaktive Turtle-Steuerung ---")
    term.setCursorPos(1, 3)
    print("Status: " .. status)
    term.setCursorPos(1, 5)
    print("Zuletzt gesendet an ID: " .. last_sent_id)
    print("Zuletzt gesendete Anzahl: " .. last_sent_count)

    -- Eingabeaufforderungen
    term.setCursorPos(1, 8)
    print("Turtle ID eingeben: ")
    term.setCursorPos(1, 9)
    print("Anzahl der Bäume eingeben: ")
end

-- Startup
rednet.open(Modem_Side)
updateUI()

-- Hauptschleife (wird in späteren Schritten implementiert)
-- Hauptschleife
while true do
    -- ID Eingabe
    term.setCursorPos(21, 8)
    local target_id_str = read()

    -- Anzahl Eingabe
    term.setCursorPos(28, 9)
    local anzahl_str = read()

    -- Eingaben validieren
    local target_id = tonumber(target_id_str)
    local anzahl = tonumber(anzahl_str)

    if not target_id or not anzahl then
        status = "Fehler: ID und Anzahl müssen Zahlen sein."
    else
        -- Senden
        status = "Sende Daten..."
        updateUI() -- Status vor dem Senden aktualisieren
        rednet.send(target_id, tostring(anzahl))

        -- UI nach dem Senden aktualisieren
        last_sent_id = tostring(target_id)
        last_sent_count = tostring(anzahl)
        status = "Daten an ID " .. target_id .. " gesendet."
    end

    -- UI für die nächste Eingabe vorbereiten
    updateUI()
    sleep(2) -- Kurze Pause, damit der Benutzer den Status lesen kann
    status = "Bereit für die nächste Eingabe."
    updateUI()
end
