-- Konfiguration
local Modem_Side = "top"
local RESPONSE_TIMEOUT = 10 -- Sekunden

-- Statusvariablen für die UI
local status = "Bereit für die Eingabe."
local turtle_status = "N/A"
local last_sent_id = "N/A"
local last_sent_count = "N/A"

-- UI Funktion
local function updateUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- Interaktive Turtle-Steuerung ---")
    term.setCursorPos(1, 3)
    print("Controller-Status: " .. status)
    term.setCursorPos(1, 4)
    print("Turtle-Status: " .. turtle_status)
    term.setCursorPos(1, 6)
    print("Zuletzt gesendet an ID: " .. last_sent_id)
    print("Zuletzt gesendete Anzahl: " .. last_sent_count)

    -- Eingabeaufforderungen (werden nur angezeigt, wenn bereit)
    if status == "Bereit für die Eingabe." then
        term.setCursorPos(1, 9)
        print("Turtle ID eingeben: ")
        term.setCursorPos(1, 10)
        print("Anzahl der Bäume eingeben: ")
    end
end

-- Funktion zum Warten auf Feedback
local function listenForFeedback(turtle_id)
    turtle_status = "Warte auf Antwort von Turtle " .. turtle_id .. "..."
    updateUI()

    local startTime = os.clock()
    while os.clock() - startTime < RESPONSE_TIMEOUT do
        local senderId, message = rednet.receive(RESPONSE_TIMEOUT - (os.clock() - startTime))
        if senderId and senderId == turtle_id then
            turtle_status = message
            updateUI()
            -- Wenn die Aufgabe abgeschlossen oder fehlgeschlagen ist, beende das Warten
            if string.find(message, "abgeschlossen") or string.find(message, "abgebrochen") then
                return
            end
            -- Setze den Timer zurück, da wir eine Nachricht erhalten haben
            startTime = os.clock()
        end
    end

    turtle_status = "Timeout: Keine Rückmeldung von der Turtle."
end

-- Startup
rednet.open(Modem_Side)

-- Hauptschleife
while true do
    status = "Bereit für die Eingabe."
    turtle_status = "N/A"
    updateUI()

    -- ID Eingabe
    term.setCursorPos(21, 9)
    local target_id_str = read()

    -- Anzahl Eingabe
    term.setCursorPos(28, 10)
    local anzahl_str = read()

    -- Eingaben validieren
    local target_id = tonumber(target_id_str)
    local anzahl = tonumber(anzahl_str)

    if not target_id or not anzahl then
        status = "Fehler: ID und Anzahl müssen Zahlen sein."
        updateUI()
        sleep(2)
    else
        -- Senden
        status = "Sende Befehl an Turtle " .. target_id .. "..."
        updateUI()
        rednet.send(target_id, tostring(anzahl))

        last_sent_id = tostring(target_id)
        last_sent_count = tostring(anzahl)

        -- Auf Feedback warten
        listenForFeedback(target_id)

        status = "Vorgang beendet. Bereit für die nächste Eingabe."
        updateUI()
        sleep(3) -- Zeit, um das Endergebnis zu lesen
    end
end
