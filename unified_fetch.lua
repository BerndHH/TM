--[[
unified_fetch.lua
Universal Pastebin + OpenGist (selfhost) Fetcher/Runner für CC:Tweaked

Befehle:
  unified_fetch put <filename> [--service pastebin|opengist]
  unified_fetch get <source> <target> [--base http://217.154.74.83:32769] [--ns BurtCraft] [--file Name.lua]
  unified_fetch run <source> [--base ...] [--ns ...] [--file Name.lua] [-- arg1 arg2 ...]

<source> kann sein:
  - Pastebin Code         (z.B. "ABC123")
  - Pastebin URL          (z.B. https://pastebin.com/raw/ABC123)
  - OpenGist Voll-URL     (z.B. http://217.154.74.83:32769/BurtCraft/<id>/raw/HEAD/<file>)
  - OpenGist Kurzform     (z.B. BurtCraft/<id>/<file>) oder nur <id> + --ns/--file

Hinweis:
- Parameter haben Vorrang (MiPri-Standard).
]]--

-- ===== Parameter-Parsing =====
local rawArgs = { ... }

local function splitArgsAndRunArgs(args)
  -- Trennt Tool-Parameter von Script-Run-Argumenten nach "--"
  for i = 1, #args do
    if args[i] == "--" then
      local left = {}
      for j = 1, i - 1 do left[#left+1] = args[j] end
      local right = {}
      for j = i + 1, #args do right[#right+1] = args[j] end
      return left, right
    end
  end
  return args, {}
end

local tArgs, runArgs = splitArgsAndRunArgs(rawArgs)

local function getArg(key, default)
  for i = 1, #tArgs do
    if tArgs[i] == "--" .. key and tArgs[i+1] then
      return tArgs[i+1]
    end
    local pref = "--" .. key .. "="
    if type(tArgs[i]) == "string" and tArgs[i]:sub(1, #pref) == pref then
      return tArgs[i]:sub(#pref + 1)
    end
  end
  return default
end

-- ===== Defaults (OpenGist) =====
local DEFAULT_BASE = getArg("base", "http://217.154.74.83:32769")
local DEFAULT_NS   = getArg("ns",   "BurtCraft")
local DEFAULT_FILE = getArg("file", nil) -- optionaler Dateiname, wenn bei Kurzform nur id übergeben wird

-- ===== Usage =====
local function printUsage()
  local programName = fs.getName(shell.getRunningProgram())
  print("Usages:")
  print(programName .. " put <filename> [--service pastebin|opengist] [--token <api_token>]")
  print(programName .. " get <source> <target> [--base URL] [--ns NS] [--file Name.lua]")
  print(programName .. " run <source> [--base URL] [--ns NS] [--file Name.lua] [-- arg1 arg2 ...]")
  print("")
  print("Quellen-Beispiele:")
  print("  ABC123")
  print("  https://pastebin.com/raw/ABC123")
  print("  " .. DEFAULT_BASE .. "/" .. DEFAULT_NS .. "/<id>/raw/HEAD/<file.lua>")
  print("  " .. DEFAULT_NS .. "/<id>/<file.lua>")
  print("  <id>  (mit --ns und --file)")
end

if #tArgs < 1 then
  printUsage()
  return
end

if not http then
  printError("Dieses Programm benötigt die HTTP-API (http.enabled = true).")
  return
end

-- ===== Pastebin-Erkennung =====
local function isPastebinSource(src)
  -- grobe Heuristik: Code oder URL
  if src:match("^https?://pastebin%.com/") then return true end
  if src:match("^[%a%d]+$") and #src <= 16 then return true end
  return false
end

local function extractPastebinId(paste)
  local patterns = {
    "^([%a%d]+)$",
    "^https?://pastebin%.com/([%a%d]+)$",
    "^pastebin%.com/([%a%d]+)$",
    "^https?://pastebin%.com/raw/([%a%d]+)$",
    "^pastebin%.com/raw/([%a%d]+)$",
  }
  for i = 1, #patterns do
    local code = paste:match(patterns[i])
    if code then return code end
  end
  return nil
end

-- ===== OpenGist-Erkennung/Parser =====
local function isFullGistUrl(src)
  return src:match("^https?://") or src:match("^http://")
end

local function parseGistSource(src)
  -- Rückgabe: base, namespace, id, file  (nil wenn nicht ermittelbar)
  -- Fälle:
  -- 1) Voll-URL: http://host/NS/ID/raw/HEAD/FILE
  if isFullGistUrl(src) then
    -- Versuche, /<ns>/<id>/raw/.../<file> zu extrahieren
    local ns, gid, file = src:match("://[^/]+/([^/]+)/([^/]+)/raw/HEAD/(.+)$")
    if ns and gid and file then
      local base = src:match("^(https?://[^/]+)") or DEFAULT_BASE
      return base, ns, gid, file
    end
    -- Andere raw-Pfade (zur Not nur base zurückgeben)
    local baseOnly = src:match("^(https?://[^%s]+)$")
    if baseOnly then
      return baseOnly, DEFAULT_NS, nil, DEFAULT_FILE
    end
  end

  -- 2) Kurzform: NS/ID/FILE
  local ns, gid, file = src:match("^([^/]+)/([^/]+)/(.+)$")
  if ns and gid and file then
    return DEFAULT_BASE, ns, gid, file
  end

  -- 3) Nur ID -> nutze Defaults
  if src:match("^[%w]+$") then
    return DEFAULT_BASE, DEFAULT_NS, src, DEFAULT_FILE
  end

  return nil, nil, nil, nil
end

local function buildGistRawUrl(base, ns, gid, file)
  if not (base and ns and gid and file) then return nil end
  return string.format("%s/%s/%s/raw/HEAD/%s", base, ns, gid, file)
end

-- ===== HTTP Utils =====
local function httpGetAll(url)
  local ok, res = pcall(function() return http.get(url, nil, true) end)
  if not ok or not res then return nil, "HTTP-GET fehlgeschlagen." end
  local headers = res.getResponseHeaders() or {}
  local body = res.readAll()
  res.close()
  if not body or #body == 0 then return nil, "Leere Antwort." end
  return body, headers
end

local function httpPostForm(url, data)
  return http.post(url, data, { ["Content-Type"] = "application/x-www-form-urlencoded" })
end

local function httpPostJson(url, data, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    return http.post(url, textutils.serializeJSON(data), headers)
end

local function backupIfExists(path)
  if fs.exists(path) then
    local backup, n = path .. ".bak", 1
    while fs.exists(backup) do
      backup = path .. ".bak." .. n
      n = n + 1
    end
    local ok, err = pcall(fs.copy, path, backup)
    if ok then
      return true, backup
    else
      return false, err
    end
  end
  return true, nil -- Kein Backup nötig, da Datei nicht existiert
end

local function writeFile(path, data)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(path, "w")
  if not f then return false, "Kann Datei nicht öffnen: " .. path end
  f.write(data)
  f.close()
  return true
end

-- ===== Downloader =====
local function getFromPastebin(source)
  local code = extractPastebinId(source)
  if not code then return nil, "Ungültiger Pastebin-Code/URL." end
  write("Verbinde mit pastebin.com... ")
  local cb = ("%x"):format(math.random(0, 2^30))
  local url = "https://pastebin.com/raw/" .. textutils.urlEncode(code) .. "?cb=" .. cb
  local body, headers = httpGetAll(url)
  if not body then
    io.stderr:write("Fehlgeschlagen.\n")
    return nil, "Download fehlgeschlagen."
  end
  if not headers["Content-Type"] or not headers["Content-Type"]:find("^text/plain") then
    io.stderr:write("Fehlgeschlagen.\n")
    return nil, "Pastebin-Spamschutz aktiv. Rufe im Browser auf: https://pastebin.com/" .. textutils.urlEncode(code)
  end
  print("OK.")
  return body
end

local function getFromGist(source)
  local base, ns, gid, file = parseGistSource(source)
  if not (base and ns and gid and file) then
    return nil, "OpenGist-Quelle unvollständig. Nutze Voll-URL oder <ns>/<id>/<file> oder <id> mit --ns/--file."
  end
  local url = buildGistRawUrl(base, ns, gid, file)
  print("Lade von: " .. url)
  local body = select(1, httpGetAll(url))
  if not body then return nil, "OpenGist-Download fehlgeschlagen." end
  return body
end

local function getUnified(source)
  if isPastebinSource(source) then
    return getFromPastebin(source)
  end
  return getFromGist(source)
end

-- ===== Commands =====
local cmd = tArgs[1]

if cmd == "put" then
  if #tArgs < 2 then printUsage() return end
  local sFile = tArgs[2]
  local sPath = shell.resolve(sFile)
  if not fs.exists(sPath) or fs.isDir(sPath) then
    print("No such file")
    return
  end
  local sName = fs.getName(sPath)
  local f = fs.open(sPath, "r")
  local sText = f.readAll()
  f.close()

  local service = getArg("service", "pastebin")

  if service == "opengist" then
    local token = getArg("token")
    if not token then
      printError("Für OpenGist wird ein API-Token benötigt. --token <dein_token>")
      return
    end

    write("Lade zu OpenGist hoch... ")
    local postData = {
      description = "Hochgeladen mit unified_fetch.lua",
      public = false,
      files = {
        [sName] = {
          content = sText
        }
      }
    }
    local url = DEFAULT_BASE .. "/api/v3/gists"
    local headers = {
      Authorization = "token " .. token
    }
    local res = httpPostJson(url, postData, headers)

    if not res then
      print("Fehlgeschlagen.")
      return
    end

    local sResponse = res.readAll()
    res.close()
    local responseData = textutils.unserializeJSON(sResponse)

    if responseData and responseData.id and responseData.files and responseData.files[sName] and responseData.owner and responseData.owner.login then
      print("Erfolg.")
      local gistId = responseData.id
      local namespace = responseData.owner.login
      local getCmd = string.format('Run "%s get %s/%s/%s %s" to download anywhere',
        fs.getName(shell.getRunningProgram()),
        namespace,
        gistId,
        sName,
        sName
      )
      print("Uploaded to: " .. responseData.html_url)
      print(getCmd)
    else
      print("Fehlgeschlagen.")
      print("Antwort: " .. (sResponse or "leer"))
    end

  elseif service == "pastebin" then
    write("Verbinde mit pastebin.com... ")
    local key = "0ec2eb25b6166c0c27a394ae118ad829"
    local res = httpPostForm(
      "https://pastebin.com/api/api_post.php",
      "api_option=paste&" ..
      "api_dev_key=" .. key .. "&" ..
      "api_paste_format=lua&" ..
      "api_paste_name=" .. textutils.urlEncode(sName) .. "&" ..
      "api_paste_code=" .. textutils.urlEncode(sText)
    )
    if not res then
      print("Failed.")
      return
    end
    print("Success.")
    local sResponse = res.readAll()
    res.close()
    local sCode = string.match(sResponse or "", "[^/]+$") or "???"
    print("Uploaded as " .. sResponse)
    print('Run "' .. fs.getName(shell.getRunningProgram()) .. ' get ' .. sCode .. ' ' .. sName .. '" to download anywhere')
  else
    printError("Unbekannter Service: " .. service)
    printUsage()
  end

elseif cmd == "get" then
  if #tArgs < 3 then printUsage() return end
  local source = tArgs[2]
  local target = tArgs[3]
  local outPath = shell.resolve(target)
  local backupOk, backupResult = backupIfExists(outPath)
  if not backupOk then
    printError("Fehler beim Sichern der vorhandenen Datei: " .. tostring(backupResult))
    return
  elseif backupResult then
    print("Vorhandene Datei gesichert als " .. fs.getName(backupResult))
  end
  local data, err = getUnified(source)
  if not data then
    printError(err or "Download fehlgeschlagen.")
    return
  end
  local ok, werr = writeFile(outPath, data)
  if not ok then
    printError(werr or "Schreibfehler.")
    return
  end
  print("Downloaded as " .. target)

elseif cmd == "run" then
  if #tArgs < 2 then printUsage() return end
  local source = tArgs[2]
  local data, err = getUnified(source)
  if not data then
    printError(err or "Download fehlgeschlagen.")
    return
  end
  local func, lerr = load(data, source, "t", _ENV)
  if not func then
    printError(lerr or "Load-Fehler.")
    return
  end
  local ok, perr = pcall(func, table.unpack(runArgs))
  if not ok then
    printError(perr or "Runtime-Fehler.")
  end

else
  printUsage()
  return
end
