--[[
  Farming Turtle Skript
  Dieses Skript automatisiert das Fällen von Bäumen und das Nachpflanzen von Setzlingen.
  Die Turtle kann über Rednet ferngesteuert werden, um eine bestimmte Anzahl von Bäumen zu fällen.
--]]

-- =============================================================================
-- Konfiguration
-- =============================================================================

-- -- Netzwerkeinstellungen --
local MODEM_SIDE = "right"

-- -- Bewegungseinstellungen --
local DISTANCE_TO_TREE = 4
local STEPS_FOR_RETURN_PATH = DISTANCE_TO_TREE + 1
local MAX_DIG_ATTEMPTS = 10

-- -- Inventareinstellungen --
local SAPLING_SLOT = 5
local BONE_MEAL_SLOT = 6
local MAX_BONE_MEAL_ATTEMPTS = 8

-- -- Betriebsmodi --
local MINIMUM_FUEL_LEVEL = 100
local CRITICAL_FUEL_LEVEL = 20


-- =============================================================================
-- Hilfsfunktionen
-- =============================================================================

local function safeMove(moveFn, detectFn, digFn)
  local attempts = 0
  while not moveFn() do
    if detectFn and detectFn() then
      if not digFn() then
        print("Fehler: Konnte Block nicht abbauen.")
        return false
      end
      sleep(0.1)
    else
      sleep(0.2)
    end
    attempts = attempts + 1
    if attempts >= MAX_DIG_ATTEMPTS then
      print("Fehler: Bewegung nach " .. MAX_DIG_ATTEMPTS .. " Versuchen abgebrochen.")
      return false
    end
  end
  return true
end

local function safeForward() return safeMove(turtle.forward, turtle.detect, turtle.dig) end
local function safeUp() return safeMove(turtle.up, turtle.detectUp, turtle.digUp) end
local function safeDown() return safeMove(turtle.down, turtle.detectDown, turtle.digDown) end
local function safeBack() return safeMove(turtle.back, turtle.detect, turtle.dig) end

local function sendRednetMessage(id, message)
  local ok, err = pcall(function()
    rednet.send(id, message)
  end)
  if not ok then
    print("Rednet-Fehler: " .. tostring(err))
  end
end

local function turnAround()
  turtle.turnLeft()
  turtle.turnLeft()
end


-- =============================================================================
-- Kernlogik
-- =============================================================================

local function advanceToTree()
  print("Bewege mich zum Baum...")
  for _ = 1, DISTANCE_TO_TREE do
    if not safeForward() then return false end
  end
  if not safeUp() then return false end

  if turtle.detect() then
    turtle.dig()
  end

  if not safeForward() then return false end
  return true
end

local function fellTree()
  print("Fälle den Baum...")
  local height = 0
  while turtle.detectUp() do
    turtle.digUp()
    if not safeUp() then return false end
    height = height + 1

    -- Überprüfen, ob der Block unter dem aktuellen ein Log ist
    local success, data = turtle.inspectDown()
    if not success or not data or not string.find(data.name, "log") then
        break
    end
  end
  print("Baum mit Höhe " .. height .. " gefällt.")
  return height
end

local function returnToGroundLevel(treeHeight)
  print("Kehre zum Boden zurück...")
  for _ = 1, treeHeight do
    if not safeDown() then return false end
  end
  if not safeBack() then return false end
  return true
end

local function plantSapling()
  -- Zuerst den Boden prüfen und Setzling pflanzen
  if turtle.detect() then
    print("Boden ist blockiert, kann nicht pflanzen.")
    return false
  end

  if turtle.getItemCount(SAPLING_SLOT) == 0 then
    print("Fehler: Keine Setzlinge mehr in Slot " .. SAPLING_SLOT)
    return false
  end

  turtle.select(SAPLING_SLOT)
  turtle.place()
  print("Setzling gepflanzt.")

  -- Knochenmehl verwenden, falls vorhanden
  if turtle.getItemCount(BONE_MEAL_SLOT) > 0 then
    turtle.select(BONE_MEAL_SLOT)
    print("Beginne mit dem Düngen...")

    for i = 1, MAX_BONE_MEAL_ATTEMPTS do
      -- Prüfen, ob der Baum gewachsen ist
      local success, data = turtle.inspectDown()
      if success and data and string.find(data.name, "log") then
        print("Baum ist nach " .. (i-1) .. " Versuchen gewachsen.")
        turtle.select(1)
        return true
      end

      -- Knochenmehl anwenden
      if turtle.getItemCount(BONE_MEAL_SLOT) == 0 then
        print("Warnung: Kein Knochenmehl mehr.")
        break
      end
      pcall(turtle.placeDown) -- pcall verwenden, falls es fehlschlägt
      sleep(0.5) -- Kurze Pause, damit der Baum wachsen kann
    end

    -- Letzte Überprüfung nach der Schleife
    local success, data = turtle.inspectDown()
    if success and data and string.find(data.name, "log") then
      print("Baum ist nach " .. MAX_BONE_MEAL_ATTEMPTS .. " Versuchen gewachsen.")
      turtle.select(1)
      return true
    end

    print("Fehler: Baum ist nach " .. MAX_BONE_MEAL_ATTEMPTS .. " Düngeversuchen nicht gewachsen.")
    turtle.select(1)
    return false
  end

  -- Falls kein Knochenmehl vorhanden ist, einfach erfolgreich zurückkehren
  turtle.select(1)
  return true
end

local function returnToStart()
  print("Kehre zur Startposition zurück...")
  turnAround()
  for _ = 1, STEPS_FOR_RETURN_PATH do
    if not safeForward() then return false end
  end
  turnAround()
  return true
end

local function checkPrerequisites()
  if turtle.getFuelLevel() < CRITICAL_FUEL_LEVEL then
    print("Kritischer Treibstoffmangel. Breche ab.")
    return false
  end
  if turtle.getItemCount(SAPLING_SLOT) == 0 then
    print("Keine Setzlinge in Slot " .. SAPLING_SLOT .. ". Breche ab.")
    return false
  end
  print("Voraussetzungen geprüft. Starte...")
  return true
end


-- =============================================================================
-- Hauptprogramm
-- =============================================================================
local function runFarmingCycles(numberOfCycles)
  if not checkPrerequisites() then
    return false
  end

  for i = 1, numberOfCycles do
    print("Starte Zyklus " .. i .. " von " .. numberOfCycles)

    if turtle.getFuelLevel() < MINIMUM_FUEL_LEVEL then
      print("Warnung: Geringer Treibstoffstand!")
      if turtle.getFuelLevel() < CRITICAL_FUEL_LEVEL then
        print("Kritischer Treibstoffmangel. Breche Arbeit ab.")
        return false
      end
    end

    if not advanceToTree() then return false end

    local treeHeight = fellTree()
    if treeHeight == nil then return false end

    if not returnToGroundLevel(treeHeight) then return false end
    if not plantSapling() then return false end
    if not returnToStart() then return false end

    print("Zyklus " .. i .. " abgeschlossen.")
    sleep(1)
  end

  print("Alle Zyklen abgeschlossen.")
  return true
end


-- =============================================================================
-- Rednet Command Listener
-- =============================================================================
local function listenForCommands()
  print("Initialisiere Rednet-Empfänger...")
  rednet.open(MODEM_SIDE)
  print("Warte auf Rednet-Befehle auf der Seite: " .. MODEM_SIDE)

  while true do
    local senderId, message = rednet.receive()

    print("Nachricht von ID " .. senderId .. " erhalten: '" .. tostring(message) .. "'")

    local numCycles = tonumber(message)

    if numCycles and numCycles > 0 and math.floor(numCycles) == numCycles then
      print("Gültiger Befehl: Führe " .. numCycles .. " Zyklen aus.")

      -- Bestätigungsnachricht senden
      sendRednetMessage(senderId, "Befehl erhalten. Starte " .. numCycles .. " Farm-Zyklen.")

      local success = runFarmingCycles(numCycles)

      if success then
        sendRednetMessage(senderId, "Aufgabe erfolgreich abgeschlossen.")
      else
        sendRednetMessage(senderId, "Aufgabe aufgrund eines Fehlers abgebrochen.")
      end

      print("Warte auf neuen Befehl.")
    else
      print("Ungültiger Befehl. Muss eine positive Ganzzahl sein.")
      sendRednetMessage(senderId, "Fehler: Ungültiger Befehl. Bitte senden Sie eine positive Ganzzahl.")
    end
  end
end

-- Starte den Befehlsempfänger
listenForCommands()
