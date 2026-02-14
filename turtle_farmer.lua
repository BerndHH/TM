--[[
  Farming Turtle Skript V3
  Implementiert eine neue Fäll-Logik und optionales Warten auf natürliches Wachstum.
--]]

-- =============================================================================
-- Konfiguration
-- =============================================================================

local MODEM_SIDE = "right"
local MAX_DIG_ATTEMPTS = 10
local SAPLING_SLOT = 1
local BONE_MEAL_SLOT = 2
local MAX_BONE_MEAL_ATTEMPTS = 8
local GROWTH_CHECK_INTERVAL = 10 -- Sekunden zwischen den Überprüfungen auf natürliches Wachstum

-- =============================================================================
-- Hilfsfunktionen
-- =============================================================================
local function safeMove(moveFn, detectFn, digFn)
  local attempts = 0
  while not moveFn() do
    if detectFn and detectFn() then
      if not digFn() then print("Fehler: Konnte Block nicht abbauen.") return false end
    end
    attempts = attempts + 1
    if attempts >= MAX_DIG_ATTEMPTS then print("Bewegung fehlgeschlagen.") return false end
  end
  return true
end

local function safeForward() return safeMove(turtle.forward, turtle.detect, turtle.dig) end
local function safeUp() return safeMove(turtle.up, turtle.detectUp, turtle.digUp) end
local function safeDown() return safeMove(turtle.down, turtle.detectDown, turtle.digDown) end
local function safeBack() return safeMove(turtle.back, nil, nil) end

local function sendRednetMessage(id, message)
    if id then
        local serialized_msg = textutils.serialize(message)
        rednet.send(id, serialized_msg)
    end
end

local function turnAround()
    turtle.turnLeft()
    turtle.turnLeft()
end

-- =============================================================================
-- Kernlogik
-- =============================================================================

local function fellTree()
    print("Beginne mit dem Fällen des Baumes...")
    if not turtle.detect() then
        print("Fehler: Kein Baum vor der Turtle.")
        return false
    end

    -- Ersten Block abbauen und in Position bewegen
    turtle.dig()
    if not safeForward() then return false end

    -- Nach oben fällen
    local height = 1
    while turtle.detectUp() do
        turtle.digUp()
        if safeUp() then
            height = height + 1
        end
    end
    print("Baum mit Höhe " .. height .. " gefällt.")

    -- Zurück zum Boden
    for _ = 1, height do
        if not safeDown() then return false end
    end

    return true
end

local function plantAndGrow(use_bonemeal, controller_id)
    print("Beginne mit dem Pflanzen...")
    if turtle.detect() then
        print("Fehler: Boden blockiert.")
        return false
    end
    if turtle.getItemCount(SAPLING_SLOT) == 0 then
        print("Fehler: Keine Setzlinge.")
        return false
    end

    turtle.select(SAPLING_SLOT)
    turtle.place()
    print("Setzling gepflanzt.")

    -- Wachstum
    if use_bonemeal then
        -- Knochenmehl-Logik
        if turtle.getItemCount(BONE_MEAL_SLOT) == 0 then
            print("Kein Knochenmehl, warte auf natürliches Wachstum.")
            -- Fallback zu natürlichem Wachstum
        else
            turtle.select(BONE_MEAL_SLOT)
            for i = 1, MAX_BONE_MEAL_ATTEMPTS do
                local success, data = turtle.inspect()
                if success and string.find(data.name, "log") then
                    print("Baum nach " .. i-1 .. " Versuchen gewachsen.")
                    turtle.select(1)
                    return true
                end
                if turtle.getItemCount(BONE_MEAL_SLOT) > 0 then turtle.place() end
                sleep(0.5)
            end
            local success, data = turtle.inspect()
            if success and string.find(data.name, "log") then
                print("Baum gewachsen.")
                turtle.select(1)
                return true
            end
            print("Fehler: Baum nach " .. MAX_BONE_MEAL_ATTEMPTS .. " Versuchen nicht gewachsen.")
            turtle.select(1)
            return false
        end
    end

    -- Logik für natürliches Wachstum
    print("Warte auf natürliches Wachstum...")
    sendRednetMessage(controller_id, { command = "start_waiting" })

    while true do
        sleep(GROWTH_CHECK_INTERVAL)
        local success, data = turtle.inspect()
        if success and string.find(data.name, "log") then
            print("Baum ist natürlich gewachsen.")
            sendRednetMessage(controller_id, { command = "tree_grown" })
            turtle.select(1)
            return true
        end
    end
end

local function returnToStart()
    print("Kehre zur Startposition zurück...")
    if not safeBack() then return false end
    return true
end

-- =============================================================================
-- Hauptprogramm
-- =============================================================================
local function runFarmingCycles(task)
  sendRednetMessage(task.controller_id, "Befehl erhalten. Starte " .. task.count .. " Zyklen.")

  for i = 1, task.count do
    sendRednetMessage(task.controller_id, "Starte Zyklus " .. i .. "/" .. task.count)

    if not fellTree() then return false end
    if not plantAndGrow(task.use_bonemeal, task.controller_id) then return false end
    if not returnToStart() then return false end

    sendRednetMessage(task.controller_id, "Zyklus " .. i .. " abgeschlossen.")
  end

  return true
end

-- =============================================================================
-- Rednet Command Listener
-- =============================================================================
local function listenForCommands()
  rednet.open(MODEM_SIDE)
  print("Warte auf Befehle...")

  while true do
    local senderId, message_str = rednet.receive()
    local task, err = textutils.unserialize(message_str)

    if type(task) == "table" and task.command == "farm" then
      local controller_id_to_reply = task.controller_id or senderId
      local success = runFarmingCycles(task)
      if success then
        sendRednetMessage(controller_id_to_reply, "Aufgabe erfolgreich abgeschlossen.")
      else
        sendRednetMessage(controller_id_to_reply, "Aufgabe aufgrund eines Fehlers abgebrochen.")
      end
    else
      sendRednetMessage(senderId, "Fehler: Ungültiger Befehl.")
    end
  end
end

listenForCommands()
