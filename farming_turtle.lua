--[[
  Farming Turtle Skript
  Dieses Skript automatisiert das Fällen von Bäumen und das Nachpflanzen von Setzlingen.
  Die Turtle bewegt sich zu einem Baum, fällt ihn, kehrt zurück, pflanzt einen neuen Setzling
  und wiederholt den Vorgang.
--]]

-- =============================================================================
-- Konfiguration
-- =============================================================================

-- -- Netzwerkeinstellungen --
-- Seite, an der das Modem angebracht ist (z.B. "right", "left", "top")
local MODEM_SIDE = "right"
-- ID des Computers, an den eine Nachricht gesendet werden soll
local REDNET_TARGET_ID = 3
-- Nachricht, die gesendet werden soll
local REDNET_MESSAGE = "x"

-- -- Bewegungseinstellungen --
-- Anzahl der Blöcke, die die Turtle vorwärts geht, um zum Baum zu gelangen
local DISTANCE_TO_TREE = 4
-- Anzahl der Schritte für den Rückweg (sollte DISTANCE_TO_TREE + 1 sein)
local STEPS_FOR_RETURN_PATH = DISTANCE_TO_TREE + 1
-- Maximale Anzahl von Versuchen, einen Block zu durchbrechen, bevor aufgegeben wird
local MAX_DIG_ATTEMPTS = 10

-- -- Inventareinstellungen --
-- Slot-Nummer für die Setzlinge
local SAPLING_SLOT = 5
-- Slot-Nummer für das Knochenmehl
local BONE_MEAL_SLOT = 6
-- Anzahl der Anwendungen von Knochenmehl pro Setzling
local BONE_MEAL_APPLICATIONS = 4

-- -- Betriebsmodi --
-- Anzahl der Zyklen, die die Turtle durchführen soll
local FARMING_CYCLES = 10
-- Aktiviert/deaktiviert das Senden einer Rednet-Nachricht am Ende
local ENABLE_REDNET_SIGNAL = false
-- Mindest-Treibstofflevel, bevor eine Warnung ausgegeben wird
local MINIMUM_FUEL_LEVEL = 100
-- Kritischer Treibstofflevel, bei dem die Turtle ihre Arbeit einstellt
local CRITICAL_FUEL_LEVEL = 20


-- =============================================================================
-- Hilfsfunktionen
-- =============================================================================

--[[
  Führt eine Bewegung sicher aus. Versucht die Bewegung, gräbt, falls sie blockiert ist,
  und versucht es dann erneut. Bricht nach einer maximalen Anzahl von Versuchen ab.
  @param moveFn Die Bewegungsfunktion, die ausgeführt werden soll (z.B. turtle.forward)
  @param detectFn Die Erkennungsfunktion, die prüft, ob der Weg frei ist (z.B. turtle.detect)
  @param digFn Die Grabungsfunktion, um den Weg freizumachen (z.B. turtle.dig)
  @return true, wenn die Bewegung erfolgreich war, ansonsten false
--]]
local function safeMove(moveFn, detectFn, digFn)
  local attempts = 0
  while not moveFn() do
    if detectFn and detectFn() then
      if not digFn() then
        -- Graben fehlgeschlagen (z.B. unzerstörbarer Block)
        print("Fehler: Konnte Block nicht abbauen.")
        return false
      end
      sleep(0.1) -- Kurze Pause nach dem Graben
    else
      sleep(0.2) -- Warten, falls der Weg ohne erkennbares Hindernis blockiert ist
    end
    attempts = attempts + 1
    if attempts >= MAX_DIG_ATTEMPTS then
      print("Fehler: Bewegung nach " .. MAX_DIG_ATTEMPTS .. " Versuchen abgebrochen.")
      return false
    end
  end
  return true
end

-- Bequeme Wrapper für safeMove
local function safeForward() return safeMove(turtle.forward, turtle.detect, turtle.dig) end
local function safeUp() return safeMove(turtle.up, turtle.detectUp, turtle.digUp) end
local function safeDown() return safeMove(turtle.down, turtle.detectDown, turtle.digDown) end
local function safeBack() return safeMove(turtle.back, turtle.detect, turtle.dig) end

--[[
  Sendet eine Rednet-Nachricht. Öffnet und schließt das Modem sicher.
  @param id Die ID des Empfängers
  @param message Die zu sendende Nachricht
--]]
local function sendRednetMessage(id, message)
  local ok, err = pcall(function()
    rednet.open(MODEM_SIDE)
    rednet.send(id, message)
    rednet.close(MODEM_SIDE)
  end)
  if not ok then
    print("Rednet-Fehler: " .. tostring(err))
  end
end

--[[
  Dreht die Turtle um 180 Grad.
--]]
local function turnAround()
  turtle.turnLeft()
  turtle.turnLeft()
end


-- =============================================================================
-- Kernlogik
-- =============================================================================

--[[
  Bewegt die Turtle zur Position des Baumes.
--]]
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

--[[
  Fällt den Baum von unten nach oben und gibt die Höhe des Baumes zurück.
  @return Die Anzahl der gefällten Holzblöcke (Höhe) oder nil bei Fehler
--]]
local function fellTree()
  print("Fälle den Baum...")
  local height = 0
  while turtle.detectUp() do
    turtle.digUp()
    if not safeUp() then return nil end
    height = height + 1
  end
  print("Baum mit Höhe " .. height .. " gefällt.")
  return height
end

--[[
  Bewegt die Turtle nach dem Fällen wieder auf den Boden.
  @param treeHeight Die Höhe des Baumes, die abgestiegen werden muss
--]]
local function returnToGroundLevel(treeHeight)
  print("Kehre zum Boden zurück...")
  for _ = 1, treeHeight do
    if not safeDown() then return false end
  end
  if not safeBack() then return false end
  return true
end

--[[
  Pflanzt einen neuen Setzling und düngt ihn mit Knochenmehl.
--]]
local function plantSapling()
  if not turtle.detect() then
    print("Pflanze neuen Setzling...")
    if turtle.getItemCount(SAPLING_SLOT) == 0 then
      print("Fehler: Keine Setzlinge mehr in Slot " .. SAPLING_SLOT)
      return false
    end

    turtle.select(SAPLING_SLOT)
    turtle.place()

    if turtle.getItemCount(BONE_MEAL_SLOT) > 0 then
      turtle.select(BONE_MEAL_SLOT)
      for _ = 1, BONE_MEAL_APPLICATIONS do
        pcall(turtle.place)
      end
    end
    turtle.select(1)
  else
    print("Boden ist blockiert, kann nicht pflanzen.")
  end
  return true
end

--[[
  Kehrt zur Ausgangsposition zurück.
--]]
local function returnToStart()
  print("Kehre zur Startposition zurück...")
  turnAround()
  for _ = 1, STEPS_FOR_RETURN_PATH do
    if not safeForward() then return false end
  end
  turnAround()
  return true
end

--[[
  Prüft, ob alle Voraussetzungen für den Start erfüllt sind.
  @return true, wenn alles in Ordnung ist, ansonsten false.
--]]
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
local function main()
  if not checkPrerequisites() then
    return
  end

  for i = 1, FARMING_CYCLES do
    print("Starte Zyklus " .. i .. " von " .. FARMING_CYCLES)

    if turtle.getFuelLevel() < MINIMUM_FUEL_LEVEL then
      print("Warnung: Geringer Treibstoffstand!")
      if turtle.getFuelLevel() < CRITICAL_FUEL_LEVEL then
        print("Kritischer Treibstoffmangel. Breche Arbeit ab.")
        break
      end
    end

    if not advanceToTree() then break end

    local treeHeight = fellTree()
    if treeHeight == nil then break end

    if not returnToGroundLevel(treeHeight) then break end
    if not plantSapling() then break end
    if not returnToStart() then break end

    print("Zyklus " .. i .. " abgeschlossen.")
    sleep(1)
  end

  if ENABLE_REDNET_SIGNAL then
    print("Sende Rednet-Signal...")
    sendRednetMessage(REDNET_TARGET_ID, REDNET_MESSAGE)
  end

  print("Alle Zyklen abgeschlossen. Aufgabe beendet.")
end

-- Starte das Hauptprogramm
main()
