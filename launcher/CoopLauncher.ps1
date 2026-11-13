# Warband Coop Campaign - лаунчер «в одну кнопку» для игры через Radmin VPN.
#
# Мод:   https://github.com/zABUz-rgb/Warband-Coop-Campaign  (общая карта, 2-4 игрока, MIT)
# Лаунчер только запускает мост мода (coop_bridge.py) и Warband с нужными настройками,
# игровой код мода он не меняет.
#
# Запуск: CoopLauncher.bat (двойной щелчок). Режимы для консоли:
#   CoopLauncher.ps1 -Update     скачать/обновить мод с GitHub и установить его в игру
#   CoopLauncher.ps1 -SelfTest   проверить всё без окна и вывести отчёт
#
# Windows PowerShell 5.1 (есть в Windows 10/11). Файл сохранён в UTF-8 с BOM - иначе PS 5.1 портит кириллицу.

param(
  [switch]$Update,
  [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$LauncherVersion = '1.0.0'
$Here       = $PSScriptRoot
$LauncherPath = $PSCommandPath            # внутри обработчиков окна $PSCommandPath пуст
$Repo       = 'zABUz-rgb/Warband-Coop-Campaign'
$NetPort    = 7350                       # TCP/UDP-порт моста хоста (NET_PORT в coop_bridge.py)
$ModuleName = 'Warband Coop Campaign'    # папка модуля в <Warband>\Modules
$CfgDir     = Join-Path $env:APPDATA 'WarbandCoopLauncher'
$CfgPath    = Join-Path $CfgDir 'launcher.json'
$DataDir    = Join-Path $env:LOCALAPPDATA 'WarbandCoopLauncher'
$DocsDir    = [Environment]::GetFolderPath('MyDocuments')
$LogDir     = Join-Path $DocsDir 'Warband Coop Campaign'
$SaveDir    = Join-Path $DocsDir 'Mount&Blade Warband Savegames\Warband Coop Campaign'
$RglPath    = Join-Path $DocsDir 'Mount&Blade Warband\rgl_config.txt'

New-Item -ItemType Directory -Force $CfgDir, $DataDir | Out-Null

# ======================================================================================
#  Настройки лаунчера (%APPDATA%\WarbandCoopLauncher\launcher.json)
# ======================================================================================

$script:Cfg = [ordered]@{
  mode        = 'join'     # join | host
  nick        = ''
  hostIp      = ''
  hostHistory = @()
  password    = ''         # зашифрован DPAPI (расшифровать можно только под этой учётной записью Windows)
  warbandDir  = ''
  packageDir  = ''
  installedTag = ''
  lang        = 'ru'       # какой архив мода качать: ru или en
}

function Load-Config {
  if (-not (Test-Path $CfgPath)) { return }
  try {
    $j = Get-Content $CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in @($script:Cfg.Keys)) {
      if ($j.PSObject.Properties.Name -contains $k -and $null -ne $j.$k) { $script:Cfg[$k] = $j.$k }
    }
    $script:Cfg.hostHistory = @($script:Cfg.hostHistory | Where-Object { $_ })
  } catch {
    Write-LauncherLog "Не удалось прочитать launcher.json: $($_.Exception.Message)"
  }
}

function Save-Config {
  $json = $script:Cfg | ConvertTo-Json -Depth 4
  [IO.File]::WriteAllText($CfgPath, $json, (New-Object Text.UTF8Encoding($false)))
}

function Protect-Text([string]$plain) {
  if (-not $plain) { return '' }
  return (ConvertTo-SecureString $plain -AsPlainText -Force | ConvertFrom-SecureString)
}

function Unprotect-Text([string]$enc) {
  if (-not $enc) { return '' }
  try {
    $s = ConvertTo-SecureString $enc
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
  } catch { return '' }
}

function Write-LauncherLog([string]$msg) {
  try {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $msg
    Add-Content -Path (Join-Path $CfgDir 'launcher.log') -Value $line -Encoding UTF8
  } catch {}
}

# ======================================================================================
#  Поиск программ и папок
# ======================================================================================

function Find-Python {
  # Возвращает @{ Exe = 'C:\...\python.exe'; Prefix = @('-3') } или $null.
  # Заглушку python.exe из Microsoft Store (WindowsApps) не считаем: это не Python.
  foreach ($name in 'python', 'py') {
    $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd -or $cmd.Source -match 'WindowsApps') { continue }
    $prefix = @()
    if ($name -eq 'py') { $prefix = @('-3') }
    try {
      $ver = & $cmd.Source @prefix -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
      if ($ver -match '^3\.(\d+)' -and [int]$Matches[1] -ge 8) {
        return @{ Exe = $cmd.Source; Prefix = $prefix; Version = "$ver".Trim() }
      }
    } catch {}
  }
  return $null
}

function Test-Warband([string]$dir) {
  return $dir -and (Test-Path -LiteralPath (Join-Path $dir 'mb_warband.exe')) -and (Test-Path -LiteralPath (Join-Path $dir 'Modules\Native'))
}

function Find-Warband {
  if (Test-Warband $script:Cfg.warbandDir) { return $script:Cfg.warbandDir }
  $found = @()
  foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games\1207666913', 'HKLM:\SOFTWARE\GOG.com\Games\1207666913') {
    try { $found += (Get-ItemProperty $key -ErrorAction Stop).path } catch {}
  }
  try {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
    $libraries = @($steam)
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      $libraries += Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' |
        ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    foreach ($lib in $libraries) { $found += Join-Path $lib 'steamapps\common\MountBlade Warband' }
  } catch {}
  foreach ($p in "${env:ProgramFiles(x86)}\Mount&Blade Warband", "$env:ProgramFiles\Mount&Blade Warband") { $found += $p }
  $dir = $Here
  while ($dir) { $found += $dir; $dir = Split-Path $dir -Parent }
  $hit = $found | Where-Object { Test-Warband $_ } | Select-Object -First 1
  if ($hit) { return [string]$hit }
  return $null
}

function Test-Package([string]$dir) {
  return $dir -and (Test-Path -LiteralPath (Join-Path $dir 'coop_bridge.py'))
}

function Find-Package {
  if (Test-Package $script:Cfg.packageDir) { return $script:Cfg.packageDir }
  $candidates = @($Here, (Split-Path $Here -Parent))
  $pkgRoot = Join-Path $DataDir 'package'
  if (Test-Path $pkgRoot) {
    $candidates += Get-ChildItem $pkgRoot -Directory | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.FullName }
  }
  $wb = Find-Warband
  if ($wb) {
    $candidates += Get-ChildItem -LiteralPath $wb -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }
  }
  foreach ($c in $candidates) { if (Test-Package $c) { return $c } }
  return $null
}

function Get-PackageVersion([string]$pkg) {
  # Первая строка README.txt пакета: "Warband Coop Campaign 1.2 - ..."
  foreach ($f in 'README.txt', 'README.md') {
    $p = Join-Path $pkg $f
    if (Test-Path -LiteralPath $p) {
      $first = Get-Content -LiteralPath $p -TotalCount 1 -Encoding UTF8
      if ($first -match '(\d+\.\d+(\.\d+)?)') { return $Matches[1] }
    }
  }
  if ($script:Cfg.installedTag) { return ($script:Cfg.installedTag -replace '^v', '') }
  return '?'
}

function Test-ModuleInstalled([string]$wb) {
  return $wb -and (Test-Path -LiteralPath (Join-Path $wb "Modules\$ModuleName\module.ini"))
}

# ======================================================================================
#  Сеть: Radmin VPN, связь с хостом
# ======================================================================================

function Get-RadminInfo {
  $info = @{ Installed = $false; Ips = @(); GuiRunning = $false }
  foreach ($d in "${env:ProgramFiles(x86)}\Radmin VPN", "$env:ProgramFiles\Radmin VPN") {
    if ($d -and (Test-Path $d)) { $info.Installed = $true }
  }
  $info.GuiRunning = [bool](Get-Process -Name 'RvRvpnGui' -ErrorAction SilentlyContinue)
  foreach ($nic in [Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
    if ($nic.OperationalStatus -ne 'Up') { continue }
    $isRadmin = ($nic.Description -like '*Radmin*') -or ($nic.Name -like '*Radmin*')
    foreach ($ua in $nic.GetIPProperties().UnicastAddresses) {
      if ($ua.Address.AddressFamily -ne 'InterNetwork') { continue }
      $ip = $ua.Address.ToString()
      if ($isRadmin -or $ip -like '26.*') { $info.Ips += $ip; $info.Installed = $true }
    }
  }
  return $info
}

function Test-HostLink([string]$address) {
  $r = @{ Ping = $false; PingMs = -1; Tcp = $false; Error = '' }
  try {
    $reply = (New-Object Net.NetworkInformation.Ping).Send($address, 1500)
    if ($reply.Status -eq 'Success') { $r.Ping = $true; $r.PingMs = [int]$reply.RoundtripTime }
  } catch { $r.Error = $_.Exception.Message }
  $tcp = New-Object Net.Sockets.TcpClient
  try {
    $task = $tcp.ConnectAsync($address, $NetPort)
    if ($task.Wait(2500) -and $tcp.Connected) { $r.Tcp = $true }
  } catch { if (-not $r.Error) { $r.Error = $_.Exception.InnerException.Message } }
  finally { $tcp.Close() }
  return $r
}

function Test-AddressText([string]$a) {
  $a = $a.Trim()
  if (-not $a) { return $false }
  $ip = $null
  if ([Net.IPAddress]::TryParse($a, [ref]$ip)) { return $true }
  return ($a -match '^[A-Za-z0-9.-]+$')
}

# ======================================================================================
#  Warband: настройки, запуск
# ======================================================================================

function Get-RglSetting([string]$name) {
  if (-not (Test-Path -LiteralPath $RglPath)) { return $null }
  foreach ($line in Get-Content -LiteralPath $RglPath) {
    $parts = $line -split '=', 2
    if ($parts.Count -eq 2 -and $parts[0].Trim() -eq $name) { return $parts[1].Trim() }
  }
  return $null
}

function Test-WarbandRunning {
  return [bool](Get-Process -Name 'mb_warband' -ErrorAction SilentlyContinue)
}

function Set-RglSettings([hashtable]$wanted) {
  # Меняет rgl_config.txt (копия - rgl_config.txt.bak). Warband перезаписывает файл при выходе,
  # поэтому при открытой игре ничего не трогаем.
  if (-not (Test-Path -LiteralPath $RglPath)) { return 'Файла rgl_config.txt ещё нет: запустите Warband один раз и закройте.' }
  if (Test-WarbandRunning) { return 'Warband открыт: закройте все окна игры, тогда настройки можно поправить.' }
  $text = [IO.File]::ReadAllText($RglPath)
  $changed = @()
  foreach ($k in $wanted.Keys) {
    $pattern = '(?m)^(\s*' + [regex]::Escape($k) + '\s*=\s*)(\S*)'
    $m = [regex]::Match($text, $pattern)
    if ($m.Success) {
      if ($m.Groups[2].Value -ne [string]$wanted[$k]) {
        $text = [regex]::Replace($text, $pattern, ('${1}' + $wanted[$k]))
        $changed += $k
      }
    } else {
      $text = $text.TrimEnd() + "`r`n$k = $($wanted[$k])`r`n"
      $changed += $k
    }
  }
  if ($changed.Count -gt 0) {
    Copy-Item -LiteralPath $RglPath -Destination "$RglPath.bak" -Force
    [IO.File]::WriteAllText($RglPath, $text)
    return 'Включено: ' + ($changed -join ', ')
  }
  return ''
}

function Start-Warband([string]$wb) {
  # Лаунчер Warband открывается сразу с выбранным модулем: он берёт его из реестра.
  try {
    $key = 'HKCU:\Software\MountAndBladeWarbandKeys'
    if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
    Set-ItemProperty -Path $key -Name 'last_module_warband' -Value $ModuleName
  } catch {}
  Start-Process -FilePath (Join-Path $wb 'mb_warband.exe') -WorkingDirectory $wb | Out-Null
}

# ======================================================================================
#  Мост мода (coop_bridge.py)
# ======================================================================================

function Get-RunningBridges([int]$ExceptPid = 0) {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name like 'python%' or Name like 'py.exe'" -ErrorAction Stop |
      Where-Object { $_.CommandLine -and $_.CommandLine -match 'coop_bridge\.py' -and $_.ProcessId -ne $ExceptPid })
  } catch { return @() }
}

function Quote-Arg([string]$a) {
  if ($a -eq '') { return '""' }
  if ($a -notmatch '[\s"]') { return $a }
  $escaped = [regex]::Replace($a, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
  $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
  return '"' + $escaped + '"'
}

function Start-Bridge([hashtable]$py, [string]$pkg, [string[]]$bridgeArgs, [string]$logName) {
  New-Item -ItemType Directory -Force $LogDir | Out-Null
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $out = Join-Path $DataDir "bridge-$stamp.out.txt"
  $err = Join-Path $DataDir "bridge-$stamp.err.txt"
  # старые выводы моста не копим
  Get-ChildItem $DataDir -Filter 'bridge-*.txt' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 | Remove-Item -Force -ErrorAction SilentlyContinue
  # -I: как в host.bat/join.bat мода; -X utf8: вывод в файл в UTF-8 (PYTHONIOENCODING при -I игнорируется)
  $all = @() + $py.Prefix + @('-I', '-X', 'utf8', (Join-Path $pkg 'coop_bridge.py')) + $bridgeArgs +
         @('--log', (Join-Path $LogDir $logName))
  $argLine = ($all | ForEach-Object { Quote-Arg $_ }) -join ' '
  $p = Start-Process -FilePath $py.Exe -ArgumentList $argLine -WorkingDirectory $pkg -WindowStyle Hidden `
         -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
  [void]$p.Handle   # без этого PS 5.1 потом не отдаёт ExitCode
  return @{ Process = $p; Out = $out; Err = $err }
}

# ======================================================================================
#  Скачивание и установка мода (консольный режим -Update)
# ======================================================================================

function Get-LatestRelease {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 8 `
           -Headers @{ 'User-Agent' = "WarbandCoopLauncher/$LauncherVersion" }
  $assets = @($rel.assets | Where-Object { $_.name -like '*.zip' -and $_.name -notlike '*debug*' -and $_.name -notlike '*nexus*' })
  if ($script:Cfg.lang -eq 'en') { $asset = $assets | Where-Object { $_.name -notlike '*-ru.zip' } | Select-Object -First 1 }
  else { $asset = $assets | Where-Object { $_.name -like '*-ru.zip' } | Select-Object -First 1 }
  if (-not $asset) { $asset = $assets | Select-Object -First 1 }
  return @{ Tag = [string]$rel.tag_name; Asset = $asset; Url = [string]$rel.html_url }
}

function Invoke-ModUpdate {
  $host.UI.RawUI.WindowTitle = 'Warband Coop Campaign - установка / обновление мода'
  try {
    Write-Host 'Ищу последнюю версию мода на GitHub...' -ForegroundColor Cyan
    $rel = Get-LatestRelease
    if (-not $rel.Asset) { throw "В релизе $($rel.Tag) нет архива с модом: $($rel.Url)" }
    $sizeMb = [math]::Round($rel.Asset.size / 1048576)
    Write-Host "Последняя версия: $($rel.Tag), архив $($rel.Asset.name) ($sizeMb МБ)"
    $current = $script:Cfg.installedTag
    if ($current -and $current -eq $rel.Tag -and (Test-Package $script:Cfg.packageDir)) {
      $a = Read-Host "Эта версия уже стоит. Переустановить? (Y - да, Enter - нет)"
      if ($a -notmatch '^[yYдД]') { return }
    }

    $zip = Join-Path $DataDir $rel.Asset.name
    if (-not ((Test-Path $zip) -and (Get-Item $zip).Length -eq $rel.Asset.size)) {
      Write-Host "Скачиваю $sizeMb МБ, это займёт несколько минут..."
      $tmpZip = "$zip.part"
      $ok = $false
      try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $rel.Asset.browser_download_url -Destination $tmpZip -DisplayName 'Warband Coop Campaign' -ErrorAction Stop
        $ok = $true
      } catch {
        Write-Host "BITS не сработал ($($_.Exception.Message)), качаю обычным способом..." -ForegroundColor Yellow
      }
      if (-not $ok) {
        $wc = New-Object Net.WebClient
        $wc.Headers.Add('User-Agent', "WarbandCoopLauncher/$LauncherVersion")
        $wc.DownloadFile($rel.Asset.browser_download_url, $tmpZip)
      }
      if ((Get-Item $tmpZip).Length -ne $rel.Asset.size) { throw 'Архив скачался не полностью. Запустите обновление ещё раз.' }
      Move-Item $tmpZip $zip -Force
    } else {
      Write-Host 'Архив уже скачан, распаковываю.'
    }

    Write-Host 'Распаковываю...'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $pkgRoot = Join-Path $DataDir 'package'
    $tmp = Join-Path $pkgRoot ('_new_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $tmp)
    $bridge = Get-ChildItem $tmp -Recurse -Filter 'coop_bridge.py' | Select-Object -First 1
    if (-not $bridge) { throw 'В архиве нет coop_bridge.py - похоже, это не пакет Warband Coop Campaign.' }
    $final = Join-Path $pkgRoot ($rel.Tag -replace '[^\w.-]', '_')
    if (Test-Path $final) { Remove-Item $final -Recurse -Force }
    Move-Item $bridge.DirectoryName $final
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    # старые версии пакета больше не нужны (сохранения и герои лежат в Документах, не здесь)
    Get-ChildItem $pkgRoot -Directory | Where-Object { $_.FullName -ne $final } |
      Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    $script:Cfg.packageDir = $final
    $script:Cfg.installedTag = $rel.Tag
    Save-Config
    Write-Host "Пакет $($rel.Tag) лежит в $final" -ForegroundColor Green

    $wb = Find-Warband
    $install = Join-Path $final 'install.ps1'
    Write-Host ''
    Write-Host 'Запускаю установщик мода (он сам предложит Python и Radmin VPN, если их нет).' -ForegroundColor Cyan
    if ($wb) { & powershell -NoProfile -ExecutionPolicy Bypass -File $install $wb }
    else { & powershell -NoProfile -ExecutionPolicy Bypass -File $install }
    $wbAfter = Find-Warband
    if ($wbAfter -and (Test-ModuleInstalled $wbAfter)) {
      Write-Host "Готово: мод $($rel.Tag) установлен в $wbAfter" -ForegroundColor Green
    } else {
      Write-Host 'Установщик закончил работу, но модуль в папке игры не найден - смотрите сообщения выше.' -ForegroundColor Yellow
    }
  } catch {
    Write-Host ''
    Write-Host 'Не получилось:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host "Можно скачать архив вручную: https://github.com/$Repo/releases/latest, распаковать и указать папку в лаунчере (Папки... -> Папка пакета мода)."
  }
  Write-Host ''
  try { Read-Host 'Нажмите Enter, чтобы закрыть окно' | Out-Null } catch {}
}

# ======================================================================================
#  Общая проверка (для окна и для -SelfTest)
# ======================================================================================

# Каждая строка: @{ Id; Name; Level = ok|warn|err; Text }
function Get-Checks([string]$mode, [string]$hostAddr, [switch]$WithUpdate) {
  $rows = @()
  $py = Find-Python
  if ($py) { $rows += @{ Id = 'python'; Name = 'Python 3'; Level = 'ok'; Text = "$($py.Version)  ($($py.Exe))" } }
  else { $rows += @{ Id = 'python'; Name = 'Python 3'; Level = 'err'; Text = 'Не найден. Нажмите «Установить / обновить мод» - установщик мода его поставит (или python.org, галочка Add to PATH).' } }

  $pkg = Find-Package
  if ($pkg) {
    $ver = Get-PackageVersion $pkg
    $txt = "версия $ver  ($pkg)"
    $lvl = 'ok'
    if ($WithUpdate) {
      try {
        $rel = Get-LatestRelease
        $latest = $rel.Tag -replace '^v', ''
        if ($ver -ne '?' -and $latest -and $latest -ne $ver) { $lvl = 'warn'; $txt = "версия $ver, на GitHub уже $latest - обновитесь (у всех игроков должна быть одна версия)" }
      } catch {}
    }
    $rows += @{ Id = 'package'; Name = 'Пакет мода'; Level = $lvl; Text = $txt }
  } else {
    $rows += @{ Id = 'package'; Name = 'Пакет мода'; Level = 'err'; Text = 'Не найден. Нажмите «Установить / обновить мод» или укажите папку (Папки...).' }
  }

  $wb = Find-Warband
  if (-not $wb) { $rows += @{ Id = 'warband'; Name = 'Warband'; Level = 'err'; Text = 'Папка игры не найдена: Папки... -> Папка Warband.' } }
  elseif (-not (Test-ModuleInstalled $wb)) { $rows += @{ Id = 'warband'; Name = 'Warband'; Level = 'err'; Text = "Модуль «$ModuleName» не установлен в $wb - нажмите «Установить / обновить мод»." } }
  else { $rows += @{ Id = 'warband'; Name = 'Warband'; Level = 'ok'; Text = "модуль установлен  ($wb)" } }

  $rad = Get-RadminInfo
  if ($rad.Ips.Count -gt 0) { $rows += @{ Id = 'radmin'; Name = 'Radmin VPN'; Level = 'ok'; Text = 'подключён, мой адрес ' + ($rad.Ips -join ', ') } }
  elseif ($rad.Installed) { $rows += @{ Id = 'radmin'; Name = 'Radmin VPN'; Level = 'warn'; Text = 'установлен, но не в сети: откройте Radmin VPN и включите его (кнопка питания).' } }
  else { $rows += @{ Id = 'radmin'; Name = 'Radmin VPN'; Level = 'warn'; Text = 'не найден. Для игры через интернет нужен Radmin VPN (в локальной сети можно без него).' } }

  if ($mode -eq 'join') {
    if (-not $hostAddr) { $rows += @{ Id = 'link'; Name = 'Связь с хостом'; Level = 'warn'; Text = 'Введите IP хоста из Radmin VPN (26.x.x.x).' } }
    elseif (-not (Test-AddressText $hostAddr)) { $rows += @{ Id = 'link'; Name = 'Связь с хостом'; Level = 'err'; Text = "«$hostAddr» не похоже на адрес." } }
    else {
      $l = Test-HostLink $hostAddr.Trim()
      if ($l.Tcp) {
        $ms = ''
        if ($l.Ping) { $ms = ", пинг $($l.PingMs) мс" }
        $rows += @{ Id = 'link'; Name = 'Связь с хостом'; Level = 'ok'; Text = "мост хоста отвечает (порт $NetPort$ms)" }
      } elseif ($l.Ping) {
        $rows += @{ Id = 'link'; Name = 'Связь с хостом'; Level = 'warn'; Text = "хост в сети (пинг $($l.PingMs) мс), но его мост не отвечает на $NetPort - хост ещё не нажал «Играть» или брандмауэр хоста блокирует порт." }
      } else {
        $rows += @{ Id = 'link'; Name = 'Связь с хостом'; Level = 'warn'; Text = 'хост не отвечает: проверьте, что вы с ним в одной сети Radmin, он онлайн и нажал «Играть».' }
      }
    }
  } else {
    $fw = Test-FirewallRule
    if ($fw -eq $true) { $rows += @{ Id = 'firewall'; Name = 'Брандмауэр'; Level = 'ok'; Text = "порт $NetPort для друзей открыт" } }
    elseif ($fw -eq $false) { $rows += @{ Id = 'firewall'; Name = 'Брандмауэр'; Level = 'warn'; Text = "правила для порта $NetPort нет. Если друзья не подключаются: Папки... -> Разрешить мост в брандмауэре." } }
  }

  $win = Get-RglSetting 'start_windowed'
  $lan = Get-RglSetting 'look_for_server_on_this_machine'
  $need = @()
  if ($win -ne '1') { $need += 'оконный режим' }
  if ($mode -eq 'join' -and $lan -ne '1') { $need += 'поиск сервера на этом ПК (для совместных боёв)' }
  if ($null -eq $win -and -not (Test-Path -LiteralPath $RglPath)) { $rows += @{ Id = 'settings'; Name = 'Настройки Warband'; Level = 'warn'; Text = 'rgl_config.txt не найден: запустите Warband один раз и закройте.' } }
  elseif ($need.Count -gt 0) { $rows += @{ Id = 'settings'; Name = 'Настройки Warband'; Level = 'warn'; Text = 'надо включить: ' + ($need -join ', ') + '. Лаунчер сделает это сам при «Играть».' } }
  else { $rows += @{ Id = 'settings'; Name = 'Настройки Warband'; Level = 'ok'; Text = 'оконный режим и поиск сервера включены' } }

  $ownPid = 0
  if ($script:Bridge -and $script:Bridge.Process) { $ownPid = $script:Bridge.Process.Id }
  $others = Get-RunningBridges $ownPid
  if ($others.Count -gt 0) { $rows += @{ Id = 'bridge'; Name = 'Мост'; Level = 'warn'; Text = "уже запущено копий моста: $($others.Count) (host.bat/join.bat или прошлый запуск). Лаунчер предложит их закрыть." } }
  return $rows
}

function Test-FirewallRule {
  try {
    $rules = @(Get-NetFirewallRule -DisplayName 'Warband Coop Launcher*' -ErrorAction Stop | Where-Object { $_.Enabled -eq 'True' })
    return ($rules.Count -gt 0)
  } catch { return $false }
}

function Open-FirewallElevated([string]$pythonExe) {
  $script = @"
`$ErrorActionPreference = 'Continue'
netsh advfirewall firewall delete rule name="Warband Coop Launcher TCP $NetPort" | Out-Null
netsh advfirewall firewall delete rule name="Warband Coop Launcher UDP $NetPort" | Out-Null
netsh advfirewall firewall add rule name="Warband Coop Launcher TCP $NetPort" dir=in action=allow protocol=TCP localport=$NetPort profile=any
netsh advfirewall firewall add rule name="Warband Coop Launcher UDP $NetPort" dir=in action=allow protocol=UDP localport=$NetPort profile=any
# Если когда-то в окне Windows нажали «Отмена», для python.exe осталось правило БЛОКИРОВКИ - оно сильнее разрешения.
`$py = '$($pythonExe -replace "'", "''")'
if (`$py) {
  Get-NetFirewallApplicationFilter -Program `$py -ErrorAction SilentlyContinue | Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object { `$_.Action -eq 'Block' -and `$_.Direction -eq 'Inbound' } | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}
"@
  $tmp = Join-Path $env:TEMP 'warband_coop_firewall.ps1'
  [IO.File]::WriteAllText($tmp, $script, (New-Object Text.UTF8Encoding($true)))
  $p = Start-Process powershell -Verb RunAs -WindowStyle Hidden -PassThru -Wait `
         -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tmp`""
  return $p.ExitCode
}

# ======================================================================================
#  Консольные режимы
# ======================================================================================

Load-Config

if ($Update) { Invoke-ModUpdate; exit 0 }

if ($SelfTest) {
  $mode = $script:Cfg.mode
  Write-Host "Warband Coop Launcher $LauncherVersion - проверка (режим: $mode)" -ForegroundColor Cyan
  foreach ($r in Get-Checks $mode $script:Cfg.hostIp -WithUpdate) {
    $color = @{ ok = 'Green'; warn = 'Yellow'; err = 'Red' }[$r.Level]
    Write-Host ('[{0,-4}] {1,-18} {2}' -f $r.Level.ToUpper(), $r.Name, $r.Text) -ForegroundColor $color
  }
  exit 0
}

# ======================================================================================
#  Окно лаунчера
# ======================================================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$script:Bridge = $null        # @{ Process; Out; Err }
$script:OutPos = 0
$script:Decoder = $null
$script:Partial = ''
$script:BridgeMode = ''
$script:LaunchGameOnConnect = $false
$script:GameStarted = $false
$script:Connected = $false
$script:LinkError = $false
$script:UpdateProc = $null

$font     = New-Object Drawing.Font('Segoe UI', 9)
$fontBold = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)

$form = New-Object Windows.Forms.Form
$form.Text = "Warband Coop Campaign - лаунчер $LauncherVersion"
$form.Font = $font
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object Drawing.Size(760, 730)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
try { $form.Icon = [Drawing.Icon]::ExtractAssociatedIcon((Join-Path (Find-Warband) 'mb_warband.exe')) } catch {}

function New-Ctl($type, $x, $y, $w, $h, $text) {
  $c = New-Object "Windows.Forms.$type"
  $c.Location = New-Object Drawing.Point($x, $y)
  $c.Size = New-Object Drawing.Size($w, $h)
  if ($null -ne $text) { $c.Text = $text }
  return $c
}

$title = New-Ctl Label 12 10 736 28 'Кооператив на общей карте Кальрадии (Warband Coop Campaign) через Radmin VPN'
$title.Font = New-Object Drawing.Font('Segoe UI', 12, [Drawing.FontStyle]::Bold)
$form.Controls.Add($title)

# --- Кто вы ---
$gbMode = New-Ctl GroupBox 12 44 360 76 'Кто вы'
$rbJoin = New-Ctl RadioButton 14 20 330 24 'Подключаюсь к другу'
$rbHost = New-Ctl RadioButton 14 44 330 24 'Я хост (мир живёт на моём ПК)'
$gbMode.Controls.AddRange(@($rbJoin, $rbHost))
$form.Controls.Add($gbMode)

# --- Radmin ---
$gbRad = New-Ctl GroupBox 384 44 364 76 'Radmin VPN'
$lblMyIp = New-Ctl Label 14 22 340 20 'Мой адрес: проверяю...'
$lblMyIp.Font = $fontBold
$btnCopyIp = New-Ctl Button 14 44 160 26 'Копировать мой IP'
$btnRadmin = New-Ctl Button 184 44 166 26 'Открыть Radmin VPN'
$gbRad.Controls.AddRange(@($lblMyIp, $btnCopyIp, $btnRadmin))
$form.Controls.Add($gbRad)

# --- Подключение ---
$gbConn = New-Ctl GroupBox 12 126 736 116 'Подключение'
$lblNick = New-Ctl Label 14 25 170 20 'Ник в мультиплеере:'
$txtNick = New-Ctl TextBox 190 22 220 24 $null
$lblNickHint = New-Ctl Label 420 25 306 20 'тот же, что в Warband: Мультиплеер - Профили'
$lblNickHint.ForeColor = [Drawing.Color]::Gray
$lblHost = New-Ctl Label 14 55 170 20 'IP хоста (Radmin):'
$cmbHost = New-Ctl ComboBox 190 52 220 24 $null
$btnPing = New-Ctl Button 420 51 150 26 'Проверить связь'
$btnInvite = New-Ctl Button 420 51 230 26 'Скопировать приглашение друзьям'
$lblPass = New-Ctl Label 14 85 170 20 'Пароль мира:'
$txtPass = New-Ctl TextBox 190 82 220 24 $null
$txtPass.UseSystemPasswordChar = $true
$chkShow = New-Ctl CheckBox 420 83 160 22 'показать'
$gbConn.Controls.AddRange(@($lblNick, $txtNick, $lblNickHint, $lblHost, $cmbHost, $btnPing, $btnInvite, $lblPass, $txtPass, $chkShow))
$form.Controls.Add($gbConn)

# --- Проверка ---
$gbChk = New-Ctl GroupBox 12 248 736 196 'Проверка'
$lv = New-Ctl ListView 10 20 716 166 $null
$lv.View = 'Details'
$lv.FullRowSelect = $true
$lv.HeaderStyle = 'Nonclickable'
[void]$lv.Columns.Add('Что', 150)
[void]$lv.Columns.Add('Состояние', 545)
$gbChk.Controls.Add($lv)
$form.Controls.Add($gbChk)

# --- Кнопки ---
$btnCheck  = New-Ctl Button 12 452 170 30 'Проверить всё'
$btnFix    = New-Ctl Button 190 452 200 30 'Исправить настройки Warband'
$btnUpdate = New-Ctl Button 398 452 210 30 'Установить / обновить мод'
$btnMore   = New-Ctl Button 616 452 132 30 'Папки...'
$form.Controls.AddRange(@($btnCheck, $btnFix, $btnUpdate, $btnMore))

$btnPlay = New-Ctl Button 12 490 360 54 'ИГРАТЬ'
$btnPlay.Font = New-Object Drawing.Font('Segoe UI', 14, [Drawing.FontStyle]::Bold)
$btnPlay.BackColor = [Drawing.Color]::FromArgb(46, 139, 87)
$btnPlay.ForeColor = [Drawing.Color]::White
$btnPlay.FlatStyle = 'Flat'
$btnBattle = New-Ctl Button 384 490 182 54 "Второе окно`r`nдля совместного боя"
$btnStop   = New-Ctl Button 574 490 174 54 'Остановить мост'
$btnStop.Enabled = $false
$form.Controls.AddRange(@($btnPlay, $btnBattle, $btnStop))

$lblStatus = New-Ctl Label 12 552 736 58 ''
$lblStatus.Font = $fontBold
$form.Controls.Add($lblStatus)

$txtLog = New-Ctl TextBox 12 614 736 106 $null
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object Drawing.Font('Consolas', 8.5)
$txtLog.BackColor = [Drawing.Color]::White
$form.Controls.Add($txtLog)

# --- Меню «Папки...» ---
$menu = New-Object Windows.Forms.ContextMenuStrip
$miWarband  = $menu.Items.Add('Указать папку Warband...')
$miPackage  = $menu.Items.Add('Указать папку пакета мода (уже распакованный архив)...')
[void]$menu.Items.Add('-')
$miSaves    = $menu.Items.Add('Открыть папку сохранений кооператива')
$miLogs     = $menu.Items.Add('Открыть журналы моста')
$miPkgOpen  = $menu.Items.Add('Открыть папку пакета мода')
[void]$menu.Items.Add('-')
$miFirewall = $menu.Items.Add('Разрешить мост в брандмауэре (нужны права администратора)')
$miKill     = $menu.Items.Add('Закрыть все запущенные копии моста')
$miLang     = $menu.Items.Add('Язык архива мода: русский')
[void]$menu.Items.Add('-')
$miHelp     = $menu.Items.Add('Как играть (инструкция)')

# ---------------------------------------------------------------------------------------

function Add-Log([string]$line) {
  $txtLog.AppendText($line + "`r`n")
}

function Set-Status([string]$text, [string]$level) {
  $lblStatus.Text = $text
  switch ($level) {
    'ok'   { $lblStatus.ForeColor = [Drawing.Color]::ForestGreen }
    'warn' { $lblStatus.ForeColor = [Drawing.Color]::DarkOrange }
    'err'  { $lblStatus.ForeColor = [Drawing.Color]::Firebrick }
    default { $lblStatus.ForeColor = [Drawing.Color]::Black }
  }
}

function Get-Mode { if ($rbHost.Checked) { return 'host' } return 'join' }

function Update-ModeUi {
  $isHost = (Get-Mode) -eq 'host'
  $cmbHost.Enabled = -not $isHost
  $lblHost.Enabled = -not $isHost
  $btnPing.Visible = -not $isHost
  $btnInvite.Visible = $isHost
  if ($isHost) { $lblPass.Text = 'Пароль для друзей:' } else { $lblPass.Text = 'Пароль, который дал хост:' }
}

function Show-Checks([switch]$WithUpdate) {
  $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
  try {
    $rows = Get-Checks (Get-Mode) $cmbHost.Text -WithUpdate:$WithUpdate
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($r in $rows) {
      $mark = @{ ok = [char]0x2714; warn = '!'; err = [char]0x2716 }[$r.Level]
      $it = New-Object Windows.Forms.ListViewItem -ArgumentList ("$mark  " + $r.Name)
      [void]$it.SubItems.Add($r.Text)
      $it.ForeColor = @{ ok = [Drawing.Color]::ForestGreen; warn = [Drawing.Color]::DarkOrange; err = [Drawing.Color]::Firebrick }[$r.Level]
      $it.ToolTipText = $r.Text
      [void]$lv.Items.Add($it)
    }
    $lv.ShowItemToolTips = $true
    $lv.EndUpdate()
    $rad = Get-RadminInfo
    if ($rad.Ips.Count -gt 0) { $lblMyIp.Text = 'Мой адрес: ' + $rad.Ips[0]; $lblMyIp.ForeColor = [Drawing.Color]::ForestGreen }
    else { $lblMyIp.Text = 'Мой адрес: Radmin не в сети'; $lblMyIp.ForeColor = [Drawing.Color]::DarkOrange }
    return $rows
  } finally { $form.Cursor = [Windows.Forms.Cursors]::Default }
}

function Save-FormToConfig {
  $script:Cfg.mode = Get-Mode
  $script:Cfg.nick = $txtNick.Text.Trim()
  $script:Cfg.password = Protect-Text $txtPass.Text
  $h = $cmbHost.Text.Trim()
  if ($h) {
    $script:Cfg.hostIp = $h
    $script:Cfg.hostHistory = @(@($h) + @($script:Cfg.hostHistory | Where-Object { $_ -ne $h }) | Select-Object -First 8)
  }
  Save-Config
}

function Stop-Bridge {
  if ($script:Bridge -and -not $script:Bridge.Process.HasExited) {
    try { Stop-Process -Id $script:Bridge.Process.Id -Force -ErrorAction Stop } catch {}
    Add-Log '--- мост остановлен ---'
  }
  $script:Bridge = $null
  $script:Connected = $false
  $btnStop.Enabled = $false
  $btnPlay.Enabled = $true
  $btnPlay.Text = 'ИГРАТЬ'
}

function Read-BridgeOutput {
  if (-not $script:Bridge) { return }
  $path = $script:Bridge.Out
  if (-not (Test-Path -LiteralPath $path)) { return }
  $fs = $null
  try {
    $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    if ($fs.Length -le $script:OutPos) { return }
    [void]$fs.Seek($script:OutPos, 'Begin')
    $buf = New-Object byte[] ([int]($fs.Length - $script:OutPos))
    $n = $fs.Read($buf, 0, $buf.Length)
    $script:OutPos += $n
  } catch { return } finally { if ($fs) { $fs.Close() } }
  $chars = New-Object char[] ($script:Decoder.GetCharCount($buf, 0, $n))
  [void]$script:Decoder.GetChars($buf, 0, $n, $chars, 0)
  $script:Partial += -join $chars
  $lines = $script:Partial -split "`n"
  $script:Partial = $lines[-1]
  for ($i = 0; $i -lt $lines.Count - 1; $i++) {
    $line = $lines[$i].TrimEnd("`r")
    if ($line) { Add-Log $line; Watch-BridgeLine $line }
  }
}

function Watch-BridgeLine([string]$line) {
  # Понимаем, что происходит, по сообщениям coop_bridge.py.
  # У хоста в вывод приходят и журналы друзей: '12:00:00 [net-...@26.x] 12:00:00 relay: ...' - их только показываем.
  if ($line -match '^\S+ \[net-') { return }
  $isJoin = ($script:BridgeMode -eq 'join')
  if ($isJoin -and $line -match 'relay: connected to the host') {
    $script:Connected = $true
    $script:LinkError = $false
    Set-Status 'Связь с хостом есть. Ждём сохранение хоста...' 'ok'
    if ($script:LaunchGameOnConnect -and -not $script:GameStarted) { Start-GameNow }
  }
  elseif ($isJoin -and ($line -match "relay: the host's save (\S+) is now (.+) - load it" -or $line -match 'relay: the host saved the game - (.+) now holds it')) {
    $p = $Matches[$Matches.Count - 1]
    $slot = [IO.Path]::GetFileNameWithoutExtension($p.Trim())
    Set-Status ("Сохранение хоста получено: слот $slot.`r`nВ Warband: Загрузить игру -> $slot, подождите ~5 секунд - вы станете клиентом мира хоста.") 'ok'
  }
  elseif ($isJoin -and $line -match 'relay: no save from the host yet') {
    Set-Status "Хост ещё не сохранял мир. Попросите хоста: Лагерь -> «CoopWorld: кооператив...» -> «удержать мир для подключения игрока» -> Esc -> Сохранить." 'warn'
  }
  elseif ($line -match 'wrong key') {
    if ($isJoin) { $script:LinkError = $true; Set-Status 'Хост отклонил подключение: неверный пароль. Уточните пароль у хоста.' 'err' }
    else { Set-Status 'Кто-то подключался с неверным паролем (см. журнал).' 'warn' }
  }
  elseif ($line -match 'another version|install the same package') {
    if ($isJoin) { $script:LinkError = $true }
    Set-Status 'У вас с хостом разные версии мода. Нажмите «Установить / обновить мод» у обоих.' 'err'
  }
  elseif ($isJoin -and $line -match 'relay: (cannot reach the host|waiting for the host)') {
    if (-not $script:Connected -and -not $script:LinkError) { Set-Status 'Жду хоста... Проверьте IP, пароль и что хост нажал «Играть». Мост переподключится сам.' 'warn' }
  }
  elseif ($isJoin -and $line -match 'relay: (lost the host|the host stopped answering)') {
    $script:Connected = $false
    Set-Status 'Связь с хостом прервалась, переподключаюсь...' 'warn'
  }
  elseif ($line -match "net: player (\S+) (connected again|connected)(, multiplayer name '([^']*)')?") {
    $who = $Matches[1]
    if ($Matches[4]) { $who = $Matches[4] + ' (' + $Matches[1] + ')' }
    Set-Status ("Друг подключился: $who.") 'ok'
  }
  elseif ($line -match 'net: player (\S+) left') {
    Set-Status ("Друг отключился: " + $Matches[1]) 'warn'
  }
  elseif ($line -match 'net: listening for players') {
    Set-Status "Мост хоста запущен. Загрузите кампанию -> Лагерь -> «CoopWorld: кооператив...» -> «сделать эту игру СЕРВЕРОМ МИРА и играть в ней».`r`nДля каждого друга: «удержать мир для подключения игрока» и сохраните игру." 'ok'
  }
  elseif ($line -match 'Address already in use|10048|PermissionError') {
    Set-Status 'Порт занят другой программой или другой копией моста. Папки... -> «Закрыть все копии моста» и нажмите «Играть» ещё раз.' 'err'
  }
}

function Start-GameNow {
  $wb = Find-Warband
  if (-not $wb) { return }
  if (Test-WarbandRunning) { Add-Log 'Warband уже открыт - новое окно не запускаю.'; $script:GameStarted = $true; return }
  Start-Warband $wb
  $script:GameStarted = $true
  Add-Log "Запускаю Warband (модуль «$ModuleName» выбран в лаунчере игры - нажмите Play)."
}

function Invoke-Play {
  $mode = Get-Mode
  $nick = $txtNick.Text.Trim()
  $pass = $txtPass.Text
  $hostAddr = $cmbHost.Text.Trim()

  if (-not $nick) { Set-Status 'Введите ник: под этим именем вы заходите в мультиплеер, по нему мост отдаёт вам ваших солдат.' 'err'; [void]$txtNick.Focus(); return }
  if ($nick -match '\s') { Set-Status 'Ник в Warband не может содержать пробелы.' 'err'; return }
  if ($mode -eq 'join') {
    if (-not (Test-AddressText $hostAddr)) { Set-Status 'Введите IP хоста из Radmin VPN, например 26.12.34.56.' 'err'; [void]$cmbHost.Focus(); return }
    if (-not $pass) { Set-Status 'Введите пароль, который дал хост.' 'err'; [void]$txtPass.Focus(); return }
  } elseif (-not $pass) {
    $a = [Windows.Forms.MessageBox]::Show('Без пароля друзья не смогут подключиться (мост пустит только игры на этом ПК). Продолжить без пароля?', 'Пароль', 'YesNo', 'Warning')
    if ($a -ne 'Yes') { [void]$txtPass.Focus(); return }
  }

  Save-FormToConfig
  $rows = Show-Checks
  $errs = @($rows | Where-Object { $_.Level -eq 'err' -and $_.Id -ne 'link' })
  if ($errs.Count -gt 0) { Set-Status ('Сначала исправьте: ' + (($errs | ForEach-Object { $_.Name }) -join ', ') + ' (см. список выше).') 'err'; return }

  if ($mode -eq 'join') {
    $link = $rows | Where-Object { $_.Id -eq 'link' } | Select-Object -First 1
    if ($link -and $link.Level -ne 'ok') {
      $a = [Windows.Forms.MessageBox]::Show("Мост хоста сейчас не отвечает:`r`n$($link.Text)`r`n`r`nВсё равно запустить? Мост будет ждать хоста и подключится сам.", 'Связь с хостом', 'YesNo', 'Question')
      if ($a -ne 'Yes') { return }
    }
  }

  $others = Get-RunningBridges
  if ($others.Count -gt 0) {
    $a = [Windows.Forms.MessageBox]::Show("Уже запущено копий моста: $($others.Count) (окно host.bat/join.bat или прошлый запуск). Два моста на одном ПК мешают друг другу. Закрыть их?", 'Мост уже запущен', 'YesNo', 'Question')
    if ($a -eq 'Yes') { foreach ($o in $others) { try { Stop-Process -Id $o.ProcessId -Force } catch {} }; Start-Sleep -Milliseconds 500 }
  }

  $wanted = @{ start_windowed = 1 }
  if ($mode -eq 'join') { $wanted['look_for_server_on_this_machine'] = 1 }
  $msg = Set-RglSettings $wanted
  if ($msg) { Add-Log "Настройки Warband: $msg" }

  $py = Find-Python
  $pkg = Find-Package
  if ($mode -eq 'join') {
    $bridgeArgs = @('join', $hostAddr, '--key', $pass, '--fetch-save', '--mp-name', $nick)
    $logName = 'join.log'
  } else {
    $bridgeArgs = @('host', '--mp-name', $nick)
    if ($pass) { $bridgeArgs += @('--key', $pass) }
    $logName = 'bridge.log'
  }
  try {
    $script:Bridge = Start-Bridge $py $pkg $bridgeArgs $logName
  } catch {
    Set-Status ('Мост не запустился: ' + $_.Exception.Message) 'err'
    return
  }
  $script:OutPos = 0
  $script:Partial = ''
  $script:Decoder = [Text.Encoding]::UTF8.GetDecoder()
  $script:BridgeMode = $mode
  $script:Connected = $false
  $script:LinkError = $false
  $script:GameStarted = $false
  $btnStop.Enabled = $true
  $btnPlay.Enabled = $false
  $btnPlay.Text = 'Мост работает'
  Add-Log "--- мост запущен ($mode), журнал: $(Join-Path $LogDir $logName) ---"

  if ($mode -eq 'host') {
    $script:LaunchGameOnConnect = $false
    Start-GameNow
    Set-Status 'Мост хоста запускается...' ''
  } else {
    # Игру открываем, как только мост соединится с хостом: тогда сохранение хоста уже на подходе.
    $script:LaunchGameOnConnect = $true
    Set-Status "Подключаюсь к $hostAddr..." ''
  }
}

function Show-Help {
  $t = @"
ОДИН РАЗ
  1. «Установить / обновить мод»: лаунчер скачает мод с GitHub и запустит его установщик
     (он же предложит поставить Python и Radmin VPN).
  2. Radmin VPN: хост создаёт сеть, друзья входят в неё. В Radmin у хоста виден адрес 26.x.x.x.
  3. У каждого своя лицензионная Warband 1.174 (Steam/GOG) с ключом для мультиплеера.

ХОСТ
  1. «Я хост», ник, пароль -> ИГРАТЬ. Нажмите «Скопировать приглашение» и отправьте друзьям.
  2. В Warband загрузите кампанию -> Лагерь -> «CoopWorld: кооператив...» ->
     «сделать эту игру СЕРВЕРОМ МИРА и играть в ней (хост)».
  3. Для каждого друга: там же «удержать мир для подключения игрока», затем Esc -> Сохранить.

ДРУГ
  1. «Подключаюсь к другу», ник, IP хоста, пароль -> ИГРАТЬ.
  2. Лаунчер сам скачает сохранение хоста и откроет Warband. Загрузите слот, который он назовёт,
     и подождите ~5 секунд - вы станете клиентом мира хоста.

СОВМЕСТНЫЕ БОИ
  Хост: «Второе окно для совместного боя» -> Мультиплеер -> Создать игру, режим «Битва», боты 0.
  Друг: «Второе окно для совместного боя» -> Сетевая игра -> Присоединиться -> Локальная сеть -> Обновить.
  Если в списке два одинаковых сервера - один идёт напрямую через Radmin и пишет «неправильный
  номер авторизации»: заходите в другой и добавьте его в избранное.
  Заходите под тем же ником, что в лаунчере.

ВАЖНО
  - Не закрывайте лаунчер, пока играете: в нём работает мост.
  - Держите в папке сохранений кооператива только сохранения текущей совместной кампании.
  - Все игроки - на одной версии мода.
"@
  [Windows.Forms.MessageBox]::Show($t, 'Как играть', 'OK', 'Information') | Out-Null
}

# ---------------------------------------------------------------------------------------
#  Обработчики
# ---------------------------------------------------------------------------------------

$rbJoin.Add_CheckedChanged({ Update-ModeUi })
$rbHost.Add_CheckedChanged({ Update-ModeUi })
$chkShow.Add_CheckedChanged({ $txtPass.UseSystemPasswordChar = -not $chkShow.Checked })

$btnCopyIp.Add_Click({
  $rad = Get-RadminInfo
  if ($rad.Ips.Count -gt 0) { [Windows.Forms.Clipboard]::SetText($rad.Ips[0]); Set-Status "Скопировано: $($rad.Ips[0])" 'ok' }
  else { Set-Status 'Radmin VPN не в сети - адреса нет.' 'warn' }
})

$btnRadmin.Add_Click({
  $exe = @("${env:ProgramFiles(x86)}\Radmin VPN\RvRvpnGui.exe", "$env:ProgramFiles\Radmin VPN\RvRvpnGui.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
  if ($exe) { Start-Process $exe } else { Set-Status 'Radmin VPN не найден. Его ставит установщик мода, или скачайте с radmin-vpn.com.' 'warn' }
})

$btnInvite.Add_Click({
  $rad = Get-RadminInfo
  if ($rad.Ips.Count -eq 0) { Set-Status 'Radmin VPN не в сети - включите его, чтобы друзья вас видели.' 'warn'; return }
  $text = "Warband Coop Campaign: IP хоста $($rad.Ips[0]), пароль: $($txtPass.Text). Запусти CoopLauncher -> «Подключаюсь к другу» -> ИГРАТЬ. Версия мода: $(Get-PackageVersion (Find-Package))."
  [Windows.Forms.Clipboard]::SetText($text)
  Set-Status 'Приглашение скопировано - вставьте его друзьям в чат.' 'ok'
})

$btnPing.Add_Click({
  $h = $cmbHost.Text.Trim()
  if (-not (Test-AddressText $h)) { Set-Status 'Введите IP хоста.' 'err'; return }
  $form.Cursor = [Windows.Forms.Cursors]::WaitCursor
  try { $l = Test-HostLink $h } finally { $form.Cursor = [Windows.Forms.Cursors]::Default }
  if ($l.Tcp) { Set-Status "Хост $h на связи, мост отвечает." 'ok' }
  elseif ($l.Ping) { Set-Status "Хост $h в сети (пинг $($l.PingMs) мс), но мост не отвечает: хост ещё не нажал «Играть» или брандмауэр." 'warn' }
  else { Set-Status "Хост $h не отвечает. Вы в одной сети Radmin? Хост онлайн?" 'err' }
})

$btnCheck.Add_Click({ [void](Show-Checks -WithUpdate) })

$btnFix.Add_Click({
  $wanted = @{ start_windowed = 1 }
  if ((Get-Mode) -eq 'join') { $wanted['look_for_server_on_this_machine'] = 1 }
  $m = Set-RglSettings $wanted
  if (-not $m) { $m = 'Всё уже настроено.' }
  Set-Status $m ''
  [void](Show-Checks)
})

$btnUpdate.Add_Click({
  if ($script:Bridge) { Set-Status 'Сначала остановите мост.' 'warn'; return }
  if (Test-WarbandRunning) { Set-Status 'Закройте Warband перед установкой мода.' 'warn'; return }
  Save-FormToConfig
  $script:UpdateProc = Start-Process powershell -PassThru -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$LauncherPath`" -Update"
  Set-Status 'Установка мода идёт в отдельном окне. Когда оно закроется, лаунчер всё перепроверит.' ''
})

$btnMore.Add_Click({ $menu.Show($btnMore, (New-Object Drawing.Point(0, $btnMore.Height))) })

$btnPlay.Add_Click({ Invoke-Play })

$btnBattle.Add_Click({
  $wb = Find-Warband
  if (-not $wb) { Set-Status 'Папка Warband не найдена.' 'err'; return }
  if (-not $script:Bridge) { Set-Status 'Сначала нажмите «Играть»: бои идут через мост.' 'warn'; return }
  Start-Warband $wb
  if ((Get-Mode) -eq 'host') { Set-Status 'Во втором окне: Мультиплеер -> Создать игру, режим «Битва», боты 0. Выберите сторону и вернитесь в окно кампании.' '' }
  else { Set-Status 'Во втором окне: Сетевая игра -> Присоединиться -> Локальная сеть -> Обновить. Заходите под своим ником.' '' }
})

$btnStop.Add_Click({ Stop-Bridge; Set-Status 'Мост остановлен.' '' })

$miWarband.Add_Click({
  $d = New-Object Windows.Forms.FolderBrowserDialog
  $d.Description = 'Папка Mount & Blade Warband (где лежит mb_warband.exe)'
  if ($d.ShowDialog() -eq 'OK') {
    if (Test-Warband $d.SelectedPath) { $script:Cfg.warbandDir = $d.SelectedPath; Save-Config; [void](Show-Checks) }
    else { Set-Status 'В этой папке нет mb_warband.exe и Modules\Native.' 'err' }
  }
})
$miPackage.Add_Click({
  $d = New-Object Windows.Forms.FolderBrowserDialog
  $d.Description = 'Распакованный архив Warband Coop Campaign (папка, где лежит coop_bridge.py)'
  if ($d.ShowDialog() -eq 'OK') {
    if (Test-Package $d.SelectedPath) { $script:Cfg.packageDir = $d.SelectedPath; Save-Config; [void](Show-Checks) }
    else { Set-Status 'В этой папке нет coop_bridge.py.' 'err' }
  }
})
$miSaves.Add_Click({ New-Item -ItemType Directory -Force $SaveDir | Out-Null; Start-Process explorer.exe "`"$SaveDir`"" })
$miLogs.Add_Click({ New-Item -ItemType Directory -Force $LogDir | Out-Null; Start-Process explorer.exe "`"$LogDir`"" })
$miPkgOpen.Add_Click({ $p = Find-Package; if ($p) { Start-Process explorer.exe "`"$p`"" } else { Set-Status 'Пакет мода не найден.' 'warn' } })
$miFirewall.Add_Click({
  $py = Find-Python
  $exe = ''
  if ($py) { $exe = $py.Exe }
  try { [void](Open-FirewallElevated $exe); Set-Status "Порт $NetPort разрешён в брандмауэре." 'ok' }
  catch { Set-Status 'Нужно подтвердить запрос администратора.' 'warn' }
  [void](Show-Checks)
})
$miKill.Add_Click({
  if ($script:Bridge) { Stop-Bridge }
  $n = 0
  foreach ($o in Get-RunningBridges) { try { Stop-Process -Id $o.ProcessId -Force; $n++ } catch {} }
  Set-Status "Закрыто копий моста: $n" ''
})
$miLang.Add_Click({
  if ($script:Cfg.lang -eq 'ru') { $script:Cfg.lang = 'en' } else { $script:Cfg.lang = 'ru' }
  Save-Config
  Update-LangItem
})
$miHelp.Add_Click({ Show-Help })

function Update-LangItem {
  if ($script:Cfg.lang -eq 'en') { $miLang.Text = 'Язык архива мода: английский (+китайский) - сменить' }
  else { $miLang.Text = 'Язык архива мода: русский - сменить' }
}

# Таймер: вывод моста, его падение, конец установки
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 400
$timer.Add_Tick({
  try {
    if ($script:Bridge) {
      Read-BridgeOutput
      if ($script:Bridge -and $script:Bridge.Process.HasExited) {
        Read-BridgeOutput
        $errText = ''
        try { $errText = (Get-Content -LiteralPath $script:Bridge.Err -Raw -Encoding UTF8) } catch {}
        if ($errText) { Add-Log $errText.TrimEnd() }
        Add-Log "--- мост завершился (код $($script:Bridge.Process.ExitCode)) ---"
        Set-Status 'Мост остановился сам - причина в журнале ниже. Нажмите «Играть», чтобы запустить снова.' 'err'
        $script:Bridge = $null
        $btnStop.Enabled = $false
        $btnPlay.Enabled = $true
        $btnPlay.Text = 'ИГРАТЬ'
      }
    }
    if ($script:UpdateProc -and $script:UpdateProc.HasExited) {
      $script:UpdateProc = $null
      Load-Config
      [void](Show-Checks)
      Set-Status 'Установка закончена, проверка обновлена.' ''
    }
  } catch { Write-LauncherLog ("tick: " + $_.Exception.Message) }
})

$form.Add_Shown({
  $txtNick.Text = $script:Cfg.nick
  foreach ($h in $script:Cfg.hostHistory) { [void]$cmbHost.Items.Add($h) }
  $cmbHost.Text = $script:Cfg.hostIp
  $txtPass.Text = Unprotect-Text $script:Cfg.password
  if ($script:Cfg.mode -eq 'host') { $rbHost.Checked = $true } else { $rbJoin.Checked = $true }
  Update-ModeUi
  Update-LangItem
  Set-Status 'Проверяю игру, мод, Radmin VPN и обновления...' ''
  $form.Refresh()
  $rows = Show-Checks -WithUpdate
  if (@($rows | Where-Object { $_.Level -eq 'err' }).Count -eq 0) { Set-Status 'Всё готово - нажмите «ИГРАТЬ».' 'ok' }
  else { Set-Status 'Есть что исправить - см. красные строки. Первый раз? Нажмите «Установить / обновить мод».' 'warn' }
  $timer.Start()
})

$form.Add_FormClosing({
  param($sender, $e)
  if ($script:Bridge -and -not $script:Bridge.Process.HasExited) {
    $a = [Windows.Forms.MessageBox]::Show('Мост работает: если закрыть лаунчер, кооператив прервётся. Остановить мост и выйти?', 'Выход', 'OKCancel', 'Warning')
    if ($a -ne 'OK') { $e.Cancel = $true; return }
    Stop-Bridge
  }
  try { Save-FormToConfig } catch {}
  $timer.Stop()
})

try {
  [void]$form.ShowDialog()
} catch {
  Write-LauncherLog ("crash: " + $_.Exception.ToString())
  [Windows.Forms.MessageBox]::Show("Лаунчер упал: $($_.Exception.Message)`r`nПодробности: $CfgDir\launcher.log", 'Ошибка', 'OK', 'Error') | Out-Null
} finally {
  if ($script:Bridge -and -not $script:Bridge.Process.HasExited) { try { Stop-Process -Id $script:Bridge.Process.Id -Force } catch {} }
}
