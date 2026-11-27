# WatchX bridge (Windows) – Made by Rikerud
#
# Sends WatchX alerts to ntfy and Discord:
#   * instant: watches the Screenshots folder. WatchX takes a screenshot with a small code block in
#     the corner; the alert is sent within a second, with the picture.
#   * logout: the game writes its settings file when you're logged out – WatchX notes why (AFK,
#     disconnect); a game that closes without that (a crash) is noticed too.
#   * slow fallback: tagged lines in WoWChatLog.txt (only when screenshots don't work).
# Needs nothing extra – uses PowerShell, which ships with Windows.
# The URLs are set in game (/wx) and read from WTF\Account\*\SavedVariables\WatchX.lua.
#
# Normally started automatically by "Install (Windows).bat".
# Manually:  powershell -ExecutionPolicy Bypass -File watchx_bridge.ps1 [-Test] [-Decode <image>]

param([switch]$Test, [string]$Decode = '', [switch]$Install, [switch]$Cloud)

$ErrorActionPreference = 'Continue'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
Add-Type -AssemblyName System.Drawing

$Dir = $PSScriptRoot

# ---------------------------------------------------------------- install (run by "Install (Windows).bat")
# Finds the game's _forever_ folder, copies the bridge to %LOCALAPPDATA%\WatchX (so addon updates can't break
# it), remembers the folder in wow_folder.txt, adds it to Startup and starts it.
if ($Install) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'WatchX'
    function Test-WowFolder([string]$p) {
        if (-not $p) { return $false }
        return (Test-Path -LiteralPath (Join-Path $p 'WTF')) -or (Test-Path -LiteralPath (Join-Path $p 'Interface\AddOns'))
    }
    $cands = New-Object System.Collections.Generic.List[string]
    if ($env:NW_ROOT) { $cands.Add($env:NW_ROOT) }
    try { $cands.Add([IO.Path]::GetFullPath((Join-Path $Dir '..\..\..\..'))) } catch {}   # run from Interface\AddOns\WatchX\bridge
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try {
            $ip = [string](Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath
            if ($ip) {
                $ip = $ip.TrimEnd('\')
                $cands.Add((Join-Path $ip '_forever_'))
                $cands.Add((Join-Path (Split-Path $ip -Parent) '_forever_'))
            }
        } catch {}
    }
    foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($rel in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft',
                         'Games\World of Warcraft', 'Blizzard\World of Warcraft', 'Battle.net\World of Warcraft') {
            $cands.Add((Join-Path (Join-Path $d.Root $rel) '_forever_'))
        }
    }
    $wow = $null
    foreach ($c in $cands) { if (Test-WowFolder $c) { $wow = [IO.Path]::GetFullPath($c); break } }
    while (-not (Test-WowFolder $wow)) {
        Write-Host "Couldn't find World of Warcraft's _forever_ folder."
        $wow = ([string](Read-Host 'Paste the path to it (e.g. C:\Program Files (x86)\World of Warcraft\_forever_)')).Trim().Trim('"').TrimEnd('\')
        if (-not $wow) { Write-Host 'Cancelled.'; exit 1 }
        if (-not (Test-WowFolder $wow) -and (Test-WowFolder (Join-Path $wow '_forever_'))) { $wow = Join-Path $wow '_forever_' }
    }
    Write-Host "World of Warcraft: $wow"

    # stop any old bridge
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*watchx_bridge.ps1*' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

    [void](New-Item -ItemType Directory -Force -Path $InstallDir)
    if ([IO.Path]::GetFullPath($Dir).TrimEnd('\') -ne [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')) {
        foreach ($f in 'watchx_bridge.ps1', 'watchx_decode.js', 'Uninstall (Windows).bat', 'Cloud sync (Windows).bat') {
            $src = Join-Path $Dir $f
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $InstallDir -Force }
        }
    }
    [IO.File]::WriteAllText((Join-Path $InstallDir 'wow_folder.txt'), $wow)
    Get-ChildItem -LiteralPath $InstallDir | Unblock-File -ErrorAction SilentlyContinue

    $ps1 = Join-Path $InstallDir 'watchx_bridge.ps1'
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $args1 = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $ps1 + '"'
    $lnk = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup\WatchX bridge.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = $exe
    $s.Arguments = $args1
    $s.WorkingDirectory = $InstallDir
    $s.WindowStyle = 7
    $s.Save()
    Start-Process -FilePath $exe -ArgumentList $args1 -WorkingDirectory $InstallDir -WindowStyle Hidden
    exit 0
}

# ---------------------------------------------------------------- pick the cloud folder ("Cloud sync (Windows).bat")
# A folder OneDrive, Dropbox, Google Drive or iCloud keeps in step between your computers; saved in cloud_folder.txt
# next to the installed bridge, which picks it up within a few seconds. Cancel = as it was; "Turn off" = no sync.
if ($Cloud) {
    $InstallDir = Join-Path $env:LOCALAPPDATA 'WatchX'
    $cfg = Join-Path $InstallDir 'cloud_folder.txt'
    [void](New-Item -ItemType Directory -Force -Path $InstallDir)
    Add-Type -AssemblyName System.Windows.Forms
    $now = ''
    if (Test-Path -LiteralPath $cfg) { $now = ([IO.File]::ReadAllText($cfg)).Trim() }
    if ($now) {
        $a = [Windows.Forms.MessageBox]::Show("WatchX syncs to:`n$now`n`nYes = pick another folder`nNo = turn sync off`nCancel = keep it",
            'WatchX cloud sync', 'YesNoCancel', 'Question')
        if ($a -eq 'Cancel') { exit 0 }
        if ($a -eq 'No') { Remove-Item -LiteralPath $cfg -Force; Write-Host 'Cloud sync is off.'; exit 0 }
    }
    $dlg = New-Object Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Pick a folder your cloud keeps in step (OneDrive, Dropbox, Google Drive, iCloud Drive)'
    $dlg.ShowNewFolderButton = $true
    if ($env:OneDrive -and (Test-Path -LiteralPath $env:OneDrive)) { $dlg.SelectedPath = $env:OneDrive }
    if ($dlg.ShowDialog() -ne 'OK' -or -not $dlg.SelectedPath) { Write-Host 'Nothing changed.'; exit 0 }
    [IO.File]::WriteAllText($cfg, $dlg.SelectedPath)
    Write-Host "Cloud sync: $($dlg.SelectedPath)\WatchX"
    Write-Host 'Do the same on your other computer, with the same folder. Play on one computer at a time.'
    exit 0
}

# The game's _forever_ folder: set by the installer (wow_folder.txt), or the old spot (AddOns\WatchX\bridge).
$Root = $env:NW_ROOT
$RootFile = Join-Path $Dir 'wow_folder.txt'
if (-not $Root -and (Test-Path -LiteralPath $RootFile)) { $Root = ([IO.File]::ReadAllLines($RootFile)[0]).Trim() }
if (-not $Root) { $Root = [IO.Path]::GetFullPath((Join-Path $Dir '..\..\..\..')) }
$ChatLog = Join-Path $Root 'Logs\WoWChatLog.txt'
$Shots = Join-Path $Root 'Screenshots'
$LogFile = Join-Path $env:LOCALAPPDATA 'WatchX-bridge.log'
$Work = Join-Path $env:TEMP 'watchx-bridge'
$UA = 'WatchX-bridge/2.0'
$ProgressPreference = 'SilentlyContinue'   # the progress bar slows web requests a lot in Windows PowerShell 5.1
$KeepShots = 30
[void](New-Item -ItemType Directory -Force -Path $Work)

$script:LastLog = ''; $script:LastLogAt = [DateTime]::MinValue
function Log([string]$msg) {
    # the same line again within a minute (an error that keeps coming back) isn't written again
    if ($msg -eq $script:LastLog -and ((Get-Date) - $script:LastLogAt).TotalSeconds -lt 60) { return }
    $script:LastLog = $msg; $script:LastLogAt = Get-Date
    $line = '[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch {}
}
# a log that grew big starts over (the last one is kept as .old)
try { if ((Get-Item -LiteralPath $LogFile -ErrorAction Stop).Length -gt 1MB) { Move-Item -LiteralPath $LogFile ($LogFile + '.old') -Force } } catch {}

function Get-SvFile {
    # the game folder taken literally ([ ] in a folder name aren't wildcards), only the account folder is one
    $base = [Management.Automation.WildcardPattern]::Escape($Root)
    Get-ChildItem -Path (Join-Path $base 'WTF\Account\*\SavedVariables\WatchX.lua') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-SvValue([string]$text, [string]$key) {
    $m = [regex]::Match($text, '\["' + $key + '"\]\s*=\s*"((?:[^"\\]|\\.)*)"')
    if ($m.Success) { return ($m.Groups[1].Value -replace '\\(.)', '$1').Trim() }
    $m = [regex]::Match($text, '\["' + $key + '"\]\s*=\s*(\d+)')
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

# WatchX's own key per WoW account (one game folder can hold several), as " key1 key2 ":
# only chat-log lines with one of them are alerts.
function Get-KnownKeys {
    $base = [Management.Automation.WildcardPattern]::Escape($Root)
    $keys = ' '
    foreach ($f in @(Get-ChildItem -Path (Join-Path $base 'WTF\Account\*\SavedVariables\WatchX.lua') -ErrorAction SilentlyContinue)) {
        $k = ''
        try { $k = Get-SvValue ([IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)) 'bridgeKey' } catch {}
        if ($k) { $keys += $k + ' ' }
    }
    return $keys
}

function Get-Settings {
    $s = @{ ntfyUrl = ''; ntfyToken = ''; discordWebhook = ''; discordMention = ''; file = '' }
    $sv = Get-SvFile
    if ($sv) {
        $s.file = $sv.FullName.Substring($Root.Length).TrimStart('\')
        $text = [IO.File]::ReadAllText($sv.FullName, [Text.Encoding]::UTF8)
        foreach ($k in @('ntfyUrl', 'ntfyToken', 'discordWebhook', 'discordMention')) { $s[$k] = Get-SvValue $text $k }
        # "ntfy.sh/topic" works too: add https:// when it's missing
        foreach ($k in @('ntfyUrl', 'discordWebhook')) {
            if ($s[$k] -and $s[$k] -notmatch '^[a-zA-Z]+://') { $s[$k] = 'https://' + $s[$k] }
        }
    }
    return $s
}

function Get-Targets($s) {
    $t = @()
    if ($s.ntfyUrl) { $t += 'ntfy' }
    if ($s.discordWebhook) { $t += 'Discord' }
    if ($t.Count -eq 0) { return 'NONE – set it up in game with /wx' }
    return ($t -join ', ')
}

# One HTTP request with retries. Returns the status code (0 = no answer).
function Send-Request([string]$url, [string]$method, [byte[]]$body, [string]$contentType, $headers) {
    for ($i = 1; $i -le 2; $i++) {
        try {
            $r = Invoke-WebRequest -Uri $url -Method $method -Body $body -ContentType $contentType `
                -Headers $headers -UserAgent $UA -UseBasicParsing -TimeoutSec 12
            return [int]$r.StatusCode
        } catch {
            $code = 0
            $wait = $i
            if ($_.Exception.Response) {
                $code = [int]$_.Exception.Response.StatusCode
                if ($code -eq 429) {   # too many: wait as long as the server says (up to 10 s)
                    $ra = 0
                    try { $ra = [int][double]$_.Exception.Response.Headers['Retry-After'] } catch {}
                    $wait = [math]::Min([math]::Max($ra, 1), 10) + 1
                }
            }
            Log "  Error ($code): $($_.Exception.Message)"
            if ($code -ge 400 -and $code -lt 500 -and $code -ne 429) { return $code }
        }
        if ($i -lt 2) { Start-Sleep -Seconds $wait }
    }
    return $code
}

function Send-Json([string]$url, $obj, [string]$token) {
    $body = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress -Depth 4))
    $headers = @{}
    if ($token) { $headers['Authorization'] = "Bearer $token" }
    return Send-Request $url 'Post' $body 'application/json; charset=utf-8' $headers
}

function Send-Notification([string]$kind, [string]$subject, [string]$text, [string]$image = '') {
    $s = Get-Settings   # always fresh URLs (changed in game + reload)
    # a zero-width space after @ and between ] and (: names or notes someone else wrote can't ping or link
    $zw = [string][char]0x200B
    $subject = $subject.Replace('@', '@' + $zw).Replace('](', ']' + $zw + '(')
    $text = $text.Replace('@', '@' + $zw).Replace('](', ']' + $zw + '(')
    switch ($kind) {
        'SPAWN'   { $title = "$subject is up!";   $prio = 5; $tags = [string[]]@('rotating_light') }
        'LOOT'    { $title = "$subject dropped!"; $prio = 5; $tags = [string[]]@('tada', 'gem') }
        'ENEMY'   { $title = "$subject spotted!"; $prio = 4; $tags = [string[]]@('crossed_swords') }
        'PLAYER'  { $title = "$subject found!";   $prio = 4; $tags = [string[]]@('eyes') }
        'FRIEND'  { $title = "$subject nearby";   $prio = 3; $tags = [string[]]@('wave') }
        'ATTACK'  { $title = "You're being attacked!"; $prio = 5; $tags = [string[]]@('warning', 'crossed_swords') }
        'DEATH'   { $title = "$subject died";     $prio = 3; $tags = [string[]]@('skull') }
        'AFK'     { $title = 'AFK logout soon – move!'; $prio = 5; $tags = [string[]]@('warning', 'hourglass') }
        'LOGOUT'  { $title = 'Logging out now!'; $prio = 5; $tags = [string[]]@('warning') }
        'OFFLINE' { $title = $subject;           $prio = 5; $tags = [string[]]@('electric_plug') }
        'CLOSED'  { $title = $subject;           $prio = 3; $tags = [string[]]@('electric_plug') }   # a guess (crash?): no mention
        'TEST'    { $title = 'WatchX test';      $prio = 3; $tags = [string[]]@('test_tube') }
        default   { $title = "WatchX $kind";     $prio = 3; $tags = [string[]]@('bell') }
    }
    if (-not $s.ntfyUrl -and -not $s.discordWebhook) {
        Log '  No ntfy/Discord set up in game – nothing sent.'
        return
    }
    $bytes = $null
    if ($image) { try { $bytes = [IO.File]::ReadAllBytes($image) } catch { $bytes = $null } }

    if ($s.ntfyUrl) {
        $url = $s.ntfyUrl.TrimEnd('/')
        $code = 0
        if ($bytes) {
            # the picture as the body, the rest as query parameters (UTF-8 safe)
            $q = 'title=' + [Uri]::EscapeDataString($title) + '&message=' + [Uri]::EscapeDataString($text) +
                "&priority=$prio&tags=" + [Uri]::EscapeDataString($tags -join ',') + '&filename=watchx.jpg'
            $headers = @{}
            if ($s.ntfyToken) { $headers['Authorization'] = "Bearer $($s.ntfyToken)" }
            $code = Send-Request "${url}?$q" 'Put' $bytes 'image/jpeg' $headers
            Log "  ntfy (with screenshot) -> $code"
        }
        # the text alone: no picture, or the picture refused (too big…) – not after a time-out (it may have arrived)
        if (-not $bytes -or ($code -ge 400 -and $code -lt 500 -and $code -ne 429)) {
            $cut = $url.LastIndexOf('/')
            $obj = [ordered]@{ topic = $url.Substring($cut + 1); title = $title; message = $text; priority = $prio; tags = $tags }
            Log "  ntfy -> $(Send-Json "$($url.Substring(0, $cut))/" $obj $s.ntfyToken)"
        }
    }
    if ($s.discordWebhook) {
        $mention = ''
        if (@('SPAWN', 'LOOT', 'ENEMY', 'PLAYER', 'ATTACK', 'AFK', 'LOGOUT', 'OFFLINE') -contains $kind) { $mention = $s.discordMention }
        $content = ("$mention **$title**").Trim() + "`n" + $text
        $payload = @{ content = $content } | ConvertTo-Json -Compress
        $code = 0
        if ($bytes) {
            # multipart by hand (Windows PowerShell 5.1 has no -Form)
            $b = '----WatchX' + [Guid]::NewGuid().ToString('N')
            $enc = [Text.Encoding]::UTF8
            $ms = New-Object IO.MemoryStream
            $part1 = "--$b`r`nContent-Disposition: form-data; name=`"payload_json`"`r`nContent-Type: application/json`r`n`r`n$payload`r`n" +
                "--$b`r`nContent-Disposition: form-data; name=`"files[0]`"; filename=`"watchx.jpg`"`r`nContent-Type: image/jpeg`r`n`r`n"
            $p = $enc.GetBytes($part1); $ms.Write($p, 0, $p.Length)
            $ms.Write($bytes, 0, $bytes.Length)
            $p = $enc.GetBytes("`r`n--$b--`r`n"); $ms.Write($p, 0, $p.Length)
            $code = Send-Request $s.discordWebhook 'Post' $ms.ToArray() "multipart/form-data; boundary=$b" @{}
            Log "  discord (with screenshot) -> $code"
        }
        if (-not $bytes -or ($code -ge 400 -and $code -lt 500 -and $code -ne 429)) {
            Log "  discord -> $(Send-Json $s.discordWebhook @{ content = $content } '')"
        }
    }
}

# ---------------------------------------------------------------- instant: screenshots
# The code block (see WatchX.lua, "instant alerts"): in the top-left corner, a black margin of one
# cell, a white border of one cell, then 48 data cells per row, MSB first:
#   "W" "X" <length> <payload> <fletcher-16 a> <b>
#   payload: <kind letter> <epoch: 4 bytes> <counter> <subject> 0x1F <text>

$Kinds = @{ 'S' = 'SPAWN'; 'L' = 'LOOT'; 'E' = 'ENEMY'; 'P' = 'PLAYER'; 'F' = 'FRIEND'; 'H' = 'ATTACK'; 'D' = 'DEATH'; 'T' = 'TEST'; 'A' = 'AFK'; 'O' = 'LOGOUT' }
$Cols = 48

# Returns a hashtable (a WatchX alert), 'NO' (not ours) or 'ERR' (can't be read yet).
function Read-Shot([string]$path) {
    try { $raw = [IO.File]::ReadAllBytes($path) } catch { return 'ERR' }
    $ms = New-Object IO.MemoryStream(, $raw)
    try { $bmp = New-Object Drawing.Bitmap($ms) } catch { $ms.Dispose(); return 'ERR' }
    try {
        $W = $bmp.Width; $H = $bmp.Height
        if ($W -lt 200 -or $H -lt 200) { return 'NO' }
        function IsWhite([double]$x, [double]$y) {
            $ix = [int][Math]::Round($x); $iy = [int][Math]::Round($y)
            if ($ix -lt 0 -or $iy -lt 0 -or $ix -ge $W -or $iy -ge $H) { return $false }
            $c = $bmp.GetPixel($ix, $iy)
            return (0.299 * $c.R + 0.587 * $c.G + 0.114 * $c.B) -gt 127
        }
        $cell0 = $H * 7 / 768
        $yb = $cell0 * 1.5
        $limit = [Math]::Min($W - 1, [int][Math]::Round($cell0 * ($Cols + 8)))
        $x0 = -1; $x1 = -1
        for ($x = 0; $x -le $limit; $x++) { if (IsWhite $x $yb) { $x0 = $x; break } }
        if ($x0 -lt 0 -or $x0 -gt $cell0 * 2.5) { return 'NO' }
        for ($x = $x0; $x -le $limit; $x++) { if (-not (IsWhite $x $yb)) { break }; $x1 = $x }
        $cell = ($x1 - $x0 + 1) / ($Cols + 2)
        if ($cell -le $cell0 * 0.7 -or $cell -ge $cell0 * 1.3) { return 'NO' }
        $y0 = -1
        for ($y = 0; $y -le [Math]::Round($cell0 * 2.5); $y++) { if (IsWhite ($x0 + $cell * 0.5) $y) { $y0 = $y; break } }
        if ($y0 -lt 0) { return 'NO' }
        $gx = $x0 + $cell; $gy = $y0 + $cell
        function ByteAt([int]$n) {
            $v = 0
            for ($k = 0; $k -lt 8; $k++) {
                $i = $n * 8 + $k
                $c = $i % $Cols; $r = [Math]::Floor($i / $Cols)
                $v = $v * 2 + [int](IsWhite ($gx + ($c + 0.5) * $cell) ($gy + ($r + 0.5) * $cell))
            }
            return $v
        }
        if ((ByteAt 0) -ne 87 -or (ByteAt 1) -ne 88) { return 'NO' }
        $len = ByteAt 2
        if ($len -lt 7 -or $len -gt 120) { return 'NO' }
        $a = $len % 255; $b = $len % 255
        $payload = New-Object byte[] $len
        for ($n = 0; $n -lt $len; $n++) {
            $v = ByteAt (3 + $n)
            $payload[$n] = $v
            $a = ($a + $v) % 255
            $b = ($b + $a) % 255
        }
        if ((ByteAt (3 + $len)) -ne $a -or (ByteAt (4 + $len)) -ne $b) { return 'NO' }
        $kind = $Kinds[[string][char]$payload[0]]
        if (-not $kind) { $kind = 'TEST' }
        $epoch = (([long]$payload[1] * 256 + $payload[2]) * 256 + $payload[3]) * 256 + $payload[4]
        $id = '{0}{1:D3}' -f $epoch, $payload[5]
        [byte[]]$rest = @($payload[6..($len - 1)])   # @() and the cast: one byte stays an array
        $sep = [Array]::IndexOf($rest, [byte]31)
        $enc = [Text.Encoding]::UTF8
        if ($sep -ge 0) {
            $subject = if ($sep -gt 0) { $enc.GetString($rest, 0, $sep) } else { '' }
            $text = $enc.GetString($rest, $sep + 1, $rest.Length - $sep - 1)
        } else { $subject = $enc.GetString($rest); $text = '' }
        $bw = $x0 + ($Cols + 3) * $cell
        $bh = $y0 + ([Math]::Ceiling(($len + 5) * 8 / $Cols) + 3) * $cell
        return @{ kind = $kind; id = $id; subject = $subject; text = $text; bw = $bw; bh = $bh }
    } catch {
        return 'ERR'
    } finally { $bmp.Dispose(); $ms.Dispose() }
}

# A smaller JPEG for the phone (max 1600 px), with the code block painted over. Returns its path,
# or the original on failure.
function Get-SmallCopy([string]$path, [double]$bw = 0, [double]$bh = 0) {
    $out = Join-Path $Work 'watchx.jpg'
    try {
        $raw = [IO.File]::ReadAllBytes($path)
        $ms = New-Object IO.MemoryStream(, $raw)
        $img = [Drawing.Image]::FromStream($ms)
        try {
            $scale = [Math]::Min(1.0, 1600.0 / [Math]::Max($img.Width, $img.Height))
            $w = [int]($img.Width * $scale); $h = [int]($img.Height * $scale)
            $bmp = New-Object Drawing.Bitmap($w, $h)
            $g = [Drawing.Graphics]::FromImage($bmp)
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.DrawImage($img, 0, 0, $w, $h)
            if ($bw -gt 0 -and $bh -gt 0) {
                $brush = New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(13, 13, 15))
                $g.FillRectangle($brush, 0, 0, [int][Math]::Ceiling($bw * $scale) + 1, [int][Math]::Ceiling($bh * $scale) + 1)
                $brush.Dispose()
            }
            $g.Dispose()
            $codec = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
            $ep = New-Object Drawing.Imaging.EncoderParameters(1)
            $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter([Drawing.Imaging.Encoder]::Quality, [long]75)
            $bmp.Save($out, $codec, $ep)
            $bmp.Dispose()
        } finally { $img.Dispose(); $ms.Dispose() }
        return $out
    } catch { return $path }
}

function Size-Of([string]$path) {
    try { return (Get-Item -LiteralPath $path -ErrorAction Stop).Length } catch { return -1 }
}

function Process-Shot([string]$path) {
    $res = 'ERR'
    for ($try = 0; $try -lt 10; $try++) {
        if (-not (Test-Path -LiteralPath $path)) { return }
        $s1 = Size-Of $path
        $res = Read-Shot $path
        if ($res -is [hashtable]) { break }
        Start-Sleep -Milliseconds 200
        if ($res -eq 'NO' -and (Size-Of $path) -eq $s1) { return }   # not ours
    }
    if (-not ($res -is [hashtable])) { return }
    if ($script:Sent.Contains($res.id)) { return }
    Mark-Sent $res.id
    # held up (a slow network before it): over 2 minutes late, it says so
    try {
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$res.id.Substring(0, $res.id.Length - 3)
        if ($age -gt 120) { $res.text += " (late: $([math]::Floor($age / 60)) min)" }
    } catch {}
    Log "$($res.kind) (instant): $($res.subject) – $($res.text)"
    # wait until WoW has finished writing the file
    $s1 = -2
    for ($try = 0; $try -lt 20; $try++) {
        $s2 = Size-Of $path
        if ($s2 -ge 0 -and $s2 -eq $s1) { break }
        $s1 = $s2
        Start-Sleep -Milliseconds 150
    }
    Send-Notification $res.kind $res.subject $res.text (Get-SmallCopy $path $res.bw $res.bh)
    # WatchX's own screenshots go to Screenshots\WatchX (the newest few are kept)
    try {
        $dest = Join-Path $Shots 'WatchX'
        [void](New-Item -ItemType Directory -Force -Path $dest)
        Move-Item -LiteralPath $path -Destination $dest -Force -ErrorAction Stop
        Get-ChildItem -LiteralPath $dest -File | Sort-Object LastWriteTime -Descending |
            Select-Object -Skip $KeepShots | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
}

$script:Sent = New-Object System.Collections.Generic.Queue[string]
function Mark-Sent([string]$id) {
    $script:Sent.Enqueue($id)
    if ($script:Sent.Count -gt 200) { [void]$script:Sent.Dequeue() }
}

$script:ShotSince = (Get-Date).ToUniversalTime()
$script:Recent = New-Object System.Collections.Generic.Queue[string]
function Check-Shots {
    if (-not (Test-Path -LiteralPath $Shots)) { return }
    $next = (Get-Date).ToUniversalTime().AddSeconds(-1)
    $files = Get-ChildItem -LiteralPath $Shots -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -ge $script:ShotSince -and $_.Extension -match '^\.(jpe?g|png)$' }
    foreach ($f in $files) {
        if ($script:Recent.Contains($f.Name)) { continue }
        $script:Recent.Enqueue($f.Name); if ($script:Recent.Count -gt 100) { [void]$script:Recent.Dequeue() }
        Process-Shot $f.FullName
    }
    $script:ShotSince = $next
}

# ---------------------------------------------------------------- logged out / game closed

function Test-WowRunning {
    $p = Get-Process -Name 'Wow*', 'World*' -ErrorAction SilentlyContinue | Where-Object {
        try { $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -and $_.Path -notmatch '\\Interface\\' } catch { $false }
    }
    return [bool]$p
}

$script:SvTime = $null; $script:LastExit = ''; $script:WowUp = $false; $script:NextWowCheck = [DateTime]::MinValue
$script:WowSince = 0
function Check-Exit {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $sv = Get-SvFile
    if ($sv -and $sv.LastWriteTimeUtc -ne $script:SvTime) {
        $script:SvTime = $sv.LastWriteTimeUtc
        $text = ''
        try { $text = [IO.File]::ReadAllText($sv.FullName, [Text.Encoding]::UTF8) } catch {}
        $why = Get-SvValue $text 'exitWhy'; $at = Get-SvValue $text 'exitAt'
        if ($at -and $at -ne $script:LastExit -and ($now - [long]$at) -lt 120) {
            $script:LastExit = $at
            switch ($why) {
                'afk' {
                    Log 'Logged out (AFK)'
                    Send-Notification 'OFFLINE' 'Logged out of WoW (AFK)' 'The game logged you out for being AFK.'
                }
                'disconnect' {
                    # closing the game window looks the same – only a game that keeps running was thrown out
                    Start-Sleep -Seconds 8
                    if (Test-WowRunning) {
                        Log 'Logged out / disconnected'
                        Send-Notification 'OFFLINE' 'Logged out of WoW' "You're no longer in the game (disconnected or logged out)."
                    } else { Log 'Game closed' }
                }
                default { Log "Game: $why" }
            }
        }
    }
    if ((Get-Date) -lt $script:NextWowCheck) { return }
    $script:NextWowCheck = (Get-Date).AddSeconds(2)
    if (Test-WowRunning) {
        if (-not $script:WowUp) { $script:WowSince = $now }
        $script:WowUp = $true
    }
    elseif ($script:WowUp) {
        $script:WowUp = $false
        Start-Sleep -Seconds 3   # a normal quit writes the settings file first
        $sv = Get-SvFile; $at = ''
        if ($sv) { try { $at = Get-SvValue ([IO.File]::ReadAllText($sv.FullName, [Text.Encoding]::UTF8)) 'exitAt' } catch {} }
        # a crash = no logout written since the game started (sitting at character select for a while is fine)
        if (-not $at -or [long]$at -lt $script:WowSince) {
            Log 'Game closed without logging out (crash?)'
            Send-Notification 'CLOSED' 'WoW closed' 'The game closed without logging out (crash?).'
        }
        if ($sv) { $script:SvTime = $sv.LastWriteTimeUtc }
    }
}

# ---------------------------------------------------------------- cloud sync (optional)
# One folder you pick ("Cloud sync (Windows).bat" writes it to cloud_folder.txt): a folder OneDrive, Dropbox, Google
# Drive or iCloud keeps in step between your computers. WatchX's settings file of each WoW account is kept there as
# <folder>\WatchX\<account>\WatchX.lua:
#   * yours changed (you logged out or reloaded): copied up
#   * the cloud's changed (another computer) and the game isn't running: copied down (the game reads it at login,
#     and writes over it at logout – so never while it runs). Yours is kept as WatchX.lua.before-sync first.
#   * the first time on a computer, when the cloud already has one: the cloud's is taken (yours kept as above).
# What was last in step is remembered per account (sync\<account>.sum), so it's clear which side changed. Both
# changed (two computers playing at once): yours wins, the cloud's is kept next to it as WatchX.lua.conflict.
$CloudCfg = Join-Path $Dir 'cloud_folder.txt'
$SyncDir = Join-Path $Dir 'sync'
$script:CloudNext = [DateTime]::MinValue; $script:CloudSaid = ''
function Get-Sum([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    try { return (Get-FileHash -LiteralPath $path -Algorithm SHA1 -ErrorAction Stop).Hash } catch { return '' }
}
function Test-Settled([string]$path) {   # not being written right now (same size twice, half a second apart)
    $a = Size-Of $path; Start-Sleep -Milliseconds 500; $b = Size-Of $path
    return ($a -ge 0 -and $a -eq $b)
}
function Copy-Whole([string]$from, [string]$to) {   # a whole copy or none (a temp file next to it, then renamed)
    [void](New-Item -ItemType Directory -Force -Path (Split-Path $to -Parent))
    $tmp = $to + '.watchx-tmp'
    Copy-Item -LiteralPath $from -Destination $tmp -Force -ErrorAction Stop
    Move-Item -LiteralPath $tmp -Destination $to -Force -ErrorAction Stop
}
function Say-Cloud([string]$msg) { if ($script:CloudSaid -ne $msg) { $script:CloudSaid = $msg; Log "Cloud sync: $msg" } }
function Sync-Cloud {   # every 5 seconds
    if ((Get-Date) -lt $script:CloudNext) { return }
    $script:CloudNext = (Get-Date).AddSeconds(5)
    if (-not (Test-Path -LiteralPath $CloudCfg)) { $script:CloudSaid = ''; return }
    $cloud = ''
    try { $cloud = ([IO.File]::ReadAllText($CloudCfg)).Trim() } catch {}
    if (-not $cloud) { return }
    if (-not (Test-Path -LiteralPath $cloud)) { Say-Cloud "the folder isn't there: $cloud"; return }
    $top = Join-Path $cloud 'WatchX'
    try {
        [void](New-Item -ItemType Directory -Force -Path $top -ErrorAction Stop)
        [IO.File]::WriteAllText((Join-Path $top '.watchx-test'), 'ok')
        Remove-Item -LiteralPath (Join-Path $top '.watchx-test') -Force
    } catch { Say-Cloud "can't write to $cloud"; return }
    Say-Cloud "on – $top"
    [void](New-Item -ItemType Directory -Force -Path $SyncDir)
    $accRoot = Join-Path $Root 'WTF\Account'
    foreach ($acc in @(Get-ChildItem -LiteralPath $accRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($acc.Name -eq 'SavedVariables') { continue }
        $L = Join-Path $acc.FullName 'SavedVariables\WatchX.lua'
        $C = Join-Path (Join-Path $top $acc.Name) 'WatchX.lua'
        $S = Join-Path $SyncDir ($acc.Name + '.sum')
        $base = ''
        if (Test-Path -LiteralPath $S) { try { $base = ([IO.File]::ReadAllText($S)).Trim() } catch {} }
        $ls = Get-Sum $L; $cs = Get-Sum $C
        if ($ls -eq $cs) {
            if ($ls -and $base -ne $ls) { [IO.File]::WriteAllText($S, $ls) }
            continue
        }
        try {
            if ($cs -and (-not $base -or $cs -ne $base) -and (-not $base -or $ls -eq $base -or -not $ls)) {
                # down: the cloud's is new (or this computer is new to it) and yours hasn't changed
                if (Test-WowRunning) { continue }
                if (-not (Test-Settled $C)) { continue }
                if ($ls) { Copy-Item -LiteralPath $L -Destination ($L + '.before-sync') -Force }
                Copy-Whole $C $L
                [IO.File]::WriteAllText($S, (Get-Sum $L))
                Log "Cloud sync: $($acc.Name) – got the settings from the cloud"
                # the file changed, but nothing happened here: no "logged out" alert from another computer's logout
                $sv = Get-SvFile
                if ($sv) { $script:SvTime = $sv.LastWriteTimeUtc }
                $at = Get-SvValue ([IO.File]::ReadAllText($L, [Text.Encoding]::UTF8)) 'exitAt'
                if ($at) { $script:LastExit = $at }
            }
            elseif ($ls) {
                # up: yours changed (a logout, a reload) – or the cloud has none yet
                if (-not (Test-Settled $L)) { continue }
                if ($cs -and $base -and $cs -ne $base) {
                    Copy-Item -LiteralPath $C -Destination ($C + '.conflict') -Force
                    Log "Cloud sync: $($acc.Name) – both changed; yours kept, the cloud's saved as WatchX.lua.conflict"
                }
                Copy-Whole $L $C
                [IO.File]::WriteAllText($S, $ls)
                Log "Cloud sync: $($acc.Name) – sent your settings to the cloud"
            }
        } catch { Log "Cloud sync: $($acc.Name) – $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------- slow fallback: chat log

# Only WatchX's own lines: "<key> [WatchX]#..." with this install's key (in any game language). Other players
# can type "[WatchX]#..." in Trade, but they don't know the key. Before the game has saved a key (it does at the
# next reload or logout) – and for the old tag without one – only a line that starts like your own
# "You are now Busy:" message (or a whisper you sent) counts.
$reKey = [regex]'(^|[^A-Za-z0-9])([A-Za-z0-9]+) \[WatchX\]#([0-9]+) ([A-Z]+) (.*)$'
$reMine = [regex]'^[0-9/]+ [0-9:.]+  (You are now Busy: |To [^:]+: )([A-Za-z0-9]+ )?\[WatchX\]#'
$reOld = [regex]'^[0-9/]+ [0-9:.]+  You are now Busy: \[WatchX\]#([0-9]+) ([A-Z]+) (.*)$'
$script:Pos = -1
if (-not (Test-Path -LiteralPath $ChatLog)) { $script:Pos = 0 }   # not there yet: read it from the start when it comes
$script:Carry = ''
function Check-ChatLog {
    if (-not (Test-Path -LiteralPath $ChatLog)) { if ($script:Pos -gt 0) { $script:Pos = 0 }; return }
    try {
        $fs = [IO.File]::Open($ChatLog, 'Open', 'Read', 'ReadWrite, Delete')
        try {
            if ($script:Pos -lt 0) { $script:Pos = $fs.Length }        # don't send old events on startup
            if ($fs.Length -lt $script:Pos) { $script:Pos = 0 }        # file was truncated/replaced
            if ($fs.Length -le $script:Pos) { return }
            [void]$fs.Seek($script:Pos, 'Begin')
            $buf = New-Object byte[] ($fs.Length - $script:Pos)
            $n = $fs.Read($buf, 0, $buf.Length)
            $script:Pos += $n
        } finally { $fs.Dispose() }
        $lines = ($script:Carry + [Text.Encoding]::UTF8.GetString($buf, 0, $n)) -split "`n"
        $script:Carry = $lines[-1]
        if ($lines.Count -lt 2) { return }
        foreach ($line in $lines[0..($lines.Count - 2)]) {
            $l = $line.TrimEnd("`r")
            if ($l.IndexOf('[WatchX', [StringComparison]::Ordinal) -lt 0) { continue }
            $m = $reKey.Match($l)
            if ($m.Success) {
                $keys = Get-KnownKeys
                if ($keys -eq ' ') { if (-not $reMine.IsMatch($l)) { continue } }
                elseif (-not $keys.Contains(' ' + $m.Groups[2].Value + ' ')) { continue }
                $id = $m.Groups[3].Value; $kind = $m.Groups[4].Value; $rest = $m.Groups[5].Value
            } else {
                $m = $reOld.Match($l)
                if (-not $m.Success) { continue }
                if ((Get-KnownKeys) -ne ' ') { continue }   # a key is saved: this WatchX always uses it, the old tag isn't from it
                $id = $m.Groups[1].Value; $kind = $m.Groups[2].Value; $rest = $m.Groups[3].Value
            }
            # the id is the time + 3 digits: an old line (or a strange id) is skipped
            if ($id.Length -lt 4 -or $id.Length -gt 16) { continue }
            $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [long]$id.Substring(0, $id.Length - 3)
            if ($age -gt 1800) { continue }   # (WoW writes this file late: up to 30 min is kept)
            if ($script:Sent.Contains($id)) { continue }   # sent instantly already (or a whisper logged twice)
            Mark-Sent $id
            $cut = $rest.IndexOf('::')
            if ($cut -ge 0) { $subject = $rest.Substring(0, $cut); $text = $rest.Substring($cut + 2) }
            else { $subject = 'WatchX'; $text = $rest }
            if ($age -gt 120) { $text += " (late: $([math]::Floor($age / 60)) min)" }
            Log "$kind (chat log): $text"
            Send-Notification $kind $subject $text
        }
    } catch {
        Log "Read error: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- main

Log 'WatchX bridge 2.0 – Made by Rikerud'
$settings = Get-Settings
$from = ''
if ($settings.file) { $from = "  (from $($settings.file))" }
Log "Targets: $(Get-Targets $settings)$from"

if ($Test) {
    Send-Notification 'TEST' 'WatchX' 'Test from the bridge – alerts are working.'
    exit 0
}
if ($Decode) {
    $r = Read-Shot $Decode
    if ($r -is [hashtable]) { "OK`t$($r.kind)`t$($r.id)`t$($r.subject)`t$($r.text)" } else { $r }
    exit 0
}

# Only one bridge at a time.
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WatchXBridge', [ref]$created)
if (-not $created) { Log 'Bridge is already running – exiting.'; exit 0 }

$sv0 = Get-SvFile
if ($sv0) { $script:SvTime = $sv0.LastWriteTimeUtc }
$script:WowUp = Test-WowRunning
if ($script:WowUp) { $script:WowSince = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
Log "Watching $Shots (instant), the game (logout) and $ChatLog (fallback)"

while ($true) {
    Check-Shots
    Check-Exit
    Check-ChatLog
    Sync-Cloud
    if ($script:WowUp) { Start-Sleep -Milliseconds 300 } else { Start-Sleep -Seconds 2 }   # next to no CPU when not playing
}
