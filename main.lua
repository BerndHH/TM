--[[
MiPri Touch OS
Ein Touch-basiertes Betriebssystem für stationäre Computer mit Monitoren.
Entwickelt für das MiPri-System.
--]]

-- ============================================================================
-- KONSTANTEN
-- ============================================================================

local OS_TITLE = "====== MiPri Touch OS ======="
local CONFIG_FILE = "mipri_os.conf"

-- UI-Layout-Konstanten
local HEADER_Y = 1
local TITLE_Y = 3
local LIST_START_Y = 6
local LIST_INDENT = 2

-- ============================================================================
-- INITIALISIERUNG
-- ============================================================================

-- Rednet für die Netzwerkkommunikation öffnen
rednet.open("back")

-- Monitor-Peripherie suchen und konfigurieren
local monitor = peripheral.find("monitor")
if monitor then
  local w, h = monitor.getSize()
  -- Textgröße an die Monitorgröße anpassen
  if w <= 20 or h <= 10 then
    monitor.setTextScale(2)
  else
    monitor.setTextScale(1)
  end
  monitor.clear()
  monitor.setCursorPos(1, HEADER_Y)
  monitor.write(OS_TITLE)
  sleep(1)
else
  -- Fallback, wenn kein Monitor gefunden wird
  print("Fehler: Kein Monitor gefunden!")
  print("MiPri Touch OS benötigt einen angeschlossenen Monitor.")
  return -- Skript beenden, da es ohne Monitor nicht funktioniert
end

-- ============================================================================
-- KONFIGURATION
-- ============================================================================

local config = {
  devices = {},
  gistUsers = {}
}

-- Lädt die Konfiguration aus der Datei.
local function ladeConfig()
  if fs.exists(CONFIG_FILE) then
    local file, err = fs.open(CONFIG_FILE, "r")
    if not file then
      print("Warnung: Konfigurationsdatei konnte nicht gelesen werden: " .. (err or ""))
      return
    end

    local data = file.readAll()
    file.close()

    local success, deserialized = pcall(textutils.unserialize, data)
    if success and type(deserialized) == "table" then
      config = deserialized
      -- Sicherstellen, dass die Hauptschlüssel existieren
      if not config.devices then config.devices = {} end
      if not config.gistUsers then config.gistUsers = {} end
    else
      print("Warnung: Konfigurationsdatei beschädigt. Erstelle neue Konfiguration.")
      -- Bei Fehler eine leere Konfiguration erstellen
      config = { devices = {}, gistUsers = {} }
    end
  else
    -- Wenn keine Datei existiert, eine leere Konfiguration erstellen
    config = { devices = {}, gistUsers = {} }
  end
end

-- Speichert die aktuelle Konfiguration in die Datei.
-- @return boolean, string True bei Erfolg, ansonsten false und eine Fehlermeldung.
local function speichereConfig()
  local file, err = fs.open(CONFIG_FILE, "w")
  if not file then
    local errMsg = "Fehler beim Öffnen der Datei: " .. (err or "unbekannt")
    print(errMsg)
    return false, errMsg
  end

  local serialized = textutils.serialize(config)
  local success, writeErr = pcall(function()
    file.write(serialized)
    file.close()
  end)

  if not success then
    local errMsg = "Fehler beim Schreiben: " .. (writeErr or "unbekannt")
    print(errMsg)
    return false, errMsg
  end

  return true
end

-- ============================================================================
-- UI-FUNKTIONEN
-- ============================================================================

-- Zeichnet eine Liste von Einträgen auf dem Monitor.
-- @param titel Der Titel, der über der Liste angezeigt wird.
-- @param eintraege Eine Tabelle mit den anzuzeigenden Listeneinträgen.
local function zeichneListe(titel, eintraege)
  monitor.clear()
  monitor.setCursorPos(1, HEADER_Y)
  monitor.write(OS_TITLE)
  monitor.setCursorPos(1, TITLE_Y)
  monitor.write(titel)

  for i, eintrag in ipairs(eintraege) do
    monitor.setCursorPos(LIST_INDENT, i + LIST_START_Y - 1)
    monitor.write("> " .. eintrag)
  end
end

-- Wartet auf eine gültige Touch-Eingabe in einem Listenbereich.
-- @param maxAnzahl Die maximale Anzahl der Listeneinträge.
-- @return Die Nummer des ausgewählten Listeneintrags (beginnend bei 1).
local function warteAufTouch(maxAnzahl)
  local listStartY = LIST_START_Y
  local listEndY = listStartY + maxAnzahl - 1

  while true do
    local event, side, x, y = os.pullEvent("monitor_touch")
    if y >= listStartY and y <= listEndY then
      return y - listStartY + 1
    end
  end
end

-- ============================================================================
-- PLATZHALTER-FUNKTIONEN (Müssen noch implementiert werden)
-- ============================================================================

-- Platzhalter für die Texteingabe über den Touchscreen.
local function touchTextEingabe(prompt)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.write(prompt)
    monitor.setCursorPos(1,3)
    monitor.write("(Noch nicht implementiert)")
    sleep(2)
    return ""
end

-- Platzhalter für die Funktion zum Senden von Programmen.
local function sendeProgramm()
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.write("Programm senden...")
    monitor.setCursorPos(1,3)
    monitor.write("(Noch nicht implementiert)")
    sleep(2)
end

-- ============================================================================
-- DETAILANSICHTEN
-- ============================================================================

-- Zeigt die Details eines spezifischen Geräts an.
-- @param id Die ID des anzuzeigenden Geräts.
local function zeigeGeraeteDetails(id)
  local geraet = config.devices[id]
  if not geraet then return end

  local zeilen = {
    "Gerätename: " .. (geraet.name or "?"),
    "System: " .. (geraet.system or "Unbekannt"),
    "Status: " .. (geraet.status or "?"),
    "Letzte Antwort: " .. (geraet.letzteAntwort and textutils.formatTime(geraet.letzteAntwort, true) or "-"),
    "",
    "Programme:"
  }

  if geraet.programme and #geraet.programme > 0 then
    for _, p in ipairs(geraet.programme) do
      table.insert(zeilen, "  - " .. p.name .. (p.abfrage and " (Anzahl?)" or ""))
    end
  else
    table.insert(zeilen, "  (keine Programme)")
  end

  table.insert(zeilen, "")
  table.insert(zeilen, "Zurück")

  zeichneListe("Gerätedetails:", zeilen)

  -- Warten auf Touch, bis "Zurück" ausgewählt wird
  while true do
    if warteAufTouch(#zeilen) == #zeilen then
        break
    end
  end
end

-- ============================================================================
-- NETZWERKFUNKTIONEN
-- ============================================================================

-- Scannt das Rednet-Netzwerk nach Geräten und aktualisiert die Konfiguration.
local function geraeteScannen()
  local gefundene = {}
  zeichneListe("Scanne Netzwerk...", {})

  rednet.broadcast("scan")
  local startZeit = os.clock()

  -- 3 Sekunden lang auf Antworten warten
  while os.clock() - startZeit < 3 do
    local senderId, daten = rednet.receive(0.5)
    if daten then
      local ok, info = pcall(textutils.unserialize, daten)
      if ok and type(info) == "table" and info.typ == "report" then
        gefundene[senderId] = info
      end
    end
  end

  local anzeigeZeilen = {}
  for id, info in pairs(gefundene) do
    table.insert(anzeigeZeilen, id .. ": " .. (info.label or "Ohne Label"))

    -- Gerätedaten in der Konfiguration speichern oder aktualisieren
    config.devices[id] = config.devices[id] or {}
    config.devices[id].name = info.label or ("Gerät " .. id)
    config.devices[id].letzteAntwort = os.time()
    for k, v in pairs(info) do
      if k ~= "label" then
        config.devices[id][k] = v
      end
    end
    config.devices[id].programme = config.devices[id].programme or {}
  end

  local success, err = speichereConfig()
  if not success then
    zeichneListe("Fehler", {"Speichern fehlgeschlagen:", err})
    sleep(4)
  end

  if #anzeigeZeilen == 0 then
    zeichneListe("Keine Geräte gefunden", {"Prüfe Rednet und Labels."})
  else
    zeichneListe("Gefundene Geräte:", anzeigeZeilen)
  end
  sleep(3)
end

-- ============================================================================
-- MENÜS
-- ============================================================================

-- Zeigt das Menü für das Gerätemanagement an.
local function geraeteManagementMenu()
  while true do
    local ids = {}
    for id, data in pairs(config.devices) do
      if type(data) == "table" and data.name then
        table.insert(ids, { id = id, name = data.name })
      end
    end
    table.sort(ids, function(a, b) return a.id < b.id end)

    local eintraege = {
      "Geräte scannen",
      "Neues Gerät hinzufügen",
    }
    for _, e in ipairs(ids) do
      table.insert(eintraege, e.name .. " (ID: " .. e.id .. ")")
    end
    table.insert(eintraege, "Zurück")

    zeichneListe("Geräte-Management:", eintraege)
    local auswahl = warteAufTouch(#eintraege)

    if auswahl == 1 then
      geraeteScannen()
    elseif auswahl == 2 then
      local id_str = touchTextEingabe("Geräte-ID:")
      local id = tonumber(id_str)
      if not id then break end

      local name = touchTextEingabe("Name:")
      config.devices[id] = { name = name, programme = {} }

      while true do
        local pname = touchTextEingabe("Programmname (leer=Ende):")
        if pname == "" then break end
        local abfrage_str = touchTextEingabe("Anzahl-Abfrage? (j/n):")
        local abfrage = (abfrage_str == "j")

        table.insert(config.devices[id].programme, {
          name = pname,
          abfrage = abfrage,
          hinzugefuegt = os.time()
        })
      end

      local success, err = speichereConfig()
      if not success then
        zeichneListe("Fehler", {"Speichern fehlgeschlagen:", err})
        sleep(4)
      end

    elseif auswahl == #eintraege then
      break
    else
      local index = auswahl - 2
      local ziel = ids[index]
      if ziel then
        zeigeGeraeteDetails(ziel.id)
      end
    end
  end
end

-- Zeigt das Hauptkonfigurationsmenü an.
local function konfigMenu()
  local menueEintraege = {
    "Geräte-Management",
    "Gist-Management",
    "Zurück"
  }

  while true do
    zeichneListe("Konfig-Menü:", menueEintraege)
    local wahl = warteAufTouch(#menueEintraege)

    if wahl == 1 then
      geraeteManagementMenu()
    elseif wahl == 2 then
      zeichneListe("Gist-Management", {"(Noch nicht implementiert)", "Zurück"})
      warteAufTouch(2)
    elseif wahl == 3 then
      return
    end
  end
end

-- ============================================================================
-- HAUPTSCHLEIFE
-- ============================================================================

-- Konfiguration beim Start laden
ladeConfig()

while true do
  local hauptmenueEintraege = {
    "Befehl senden",
    "Einstellungen"
  }
  zeichneListe("Hauptmenü:", hauptmenueEintraege)

  local auswahl = warteAufTouch(#hauptmenueEintraege)

  if auswahl == 1 then
    sendeProgramm()
    sleep(1)
  elseif auswahl == 2 then
    konfigMenu()
    sleep(1)
  end
end
