#Requires -Version 5.1
<#
    SteamSwitcher.ps1
    Interactive console dashboard for managing and switching Steam accounts.
    Author: Kcpx_  |  https://github.com/kacpix0000
    Notes : Fully portable (based on $PSScriptRoot). Uses safe ASCII characters
            only, to avoid console encoding glitches. Self-heals Engine.ps1
            if it goes missing.
#>

$ErrorActionPreference = "Stop"

$RootFolder      = $PSScriptRoot
$EnginePath      = Join-Path $RootFolder "Engine.ps1"
$SettingsPath    = Join-Path $RootFolder "settings.json"
$ProfilesPath    = Join-Path $RootFolder "profiles.json"

function New-DefaultAppSettings {
    return [PSCustomObject]@{
        SteamPathOverride = $null
        GamesFolderOverride = $null
    }
}

function Get-AppSettings {
    if (Test-Path $SettingsPath) {
        try {
            $settings = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $settings) { return New-DefaultAppSettings }

            $result = New-DefaultAppSettings
            if ($settings.PSObject.Properties.Name -contains 'SteamPathOverride') {
                $result.SteamPathOverride = $settings.SteamPathOverride
            }
            if ($settings.PSObject.Properties.Name -contains 'GamesFolderOverride') {
                $result.GamesFolderOverride = $settings.GamesFolderOverride
            }
            return $result
        } catch { }
    }
    return New-DefaultAppSettings
}

function Save-AppSettings {
    param($Settings)
    $normalized = New-DefaultAppSettings
    if ($null -ne $Settings) {
        $normalized.SteamPathOverride = $Settings.SteamPathOverride
        $normalized.GamesFolderOverride = $Settings.GamesFolderOverride
    }
    $normalized | ConvertTo-Json | Set-Content -Path $SettingsPath -Encoding UTF8
}

$script:Settings = Get-AppSettings
if ($script:Settings.GamesFolderOverride) {
    $GamesFolder = $script:Settings.GamesFolderOverride
} else {
    $GamesFolder = Join-Path $RootFolder "Games"
}

if (-not (Test-Path $GamesFolder)) {
    New-Item -ItemType Directory -Path $GamesFolder -Force | Out-Null
}

# =====================================================================
#  SELF-HEALING: (Re)create Engine.ps1 if it is missing
# =====================================================================
function Install-Engine {
    $EngineCode = @'
#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$InfoPath
)
$ErrorActionPreference = "Stop"
$EngineRoot = $PSScriptRoot
$SettingsFile = Join-Path $EngineRoot "settings.json"

if (-not (Test-Path $InfoPath)) { throw "accountinfo.json not found: $InfoPath" }
$Info = Get-Content $InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$AccountName = $Info.AccountName
$AppID = $Info.AppID

function Find-SteamPath {
    $path = $null
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction Stop
        $candidate = ($reg.SteamPath -replace '/', '\')
        if ($candidate -and (Test-Path (Join-Path $candidate "Steam.exe"))) { $path = $candidate }
    } catch { }

    if (-not $path) {
        $progFiles86 = ${env:ProgramFiles(x86)}
        $progFiles   = ${env:ProgramFiles}
        $commonCandidates = @()
        if ($progFiles86) { $commonCandidates += (Join-Path $progFiles86 "Steam") }
        if ($progFiles)   { $commonCandidates += (Join-Path $progFiles "Steam") }
        foreach ($c in $commonCandidates) {
            if (Test-Path (Join-Path $c "Steam.exe")) { $path = $c; break }
        }
    }

    if (-not $path) {
        try {
            $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                if (-not $d.Root) { continue }
                $candidate = Join-Path $d.Root "Steam"
                if (Test-Path (Join-Path $candidate "Steam.exe")) { $path = $candidate; break }
            }
        } catch { }
    }

    return $path
}

$SteamPath = $null
if (Test-Path $SettingsFile) {
    try {
        $settings = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.SteamPathOverride -and (Test-Path (Join-Path $settings.SteamPathOverride "Steam.exe"))) {
            $SteamPath = $settings.SteamPathOverride
        }
    } catch { }
}
if (-not $SteamPath) { $SteamPath = Find-SteamPath }
if (-not $SteamPath) { throw "Steam installation could not be located. Use option [3] Setup Paths to set it manually." }

$SteamExe = Join-Path $SteamPath "Steam.exe"
$VdfPath  = Join-Path $SteamPath "config\loginusers.vdf"

if (Get-Process -Name "steam*" -ErrorAction SilentlyContinue) {
    Get-Process -Name "steam*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

if (Test-Path $VdfPath) {
    try {
        $content = [System.IO.File]::ReadAllText($VdfPath, [System.Text.Encoding]::UTF8)
        $content = [regex]::Replace($content, '("MostRecent"\s+)"1"', '$1"0"')
        $accPattern = '"AccountName"\s+"' + [regex]::Escape($AccountName) + '"'
        $accMatch = [regex]::Match($content, $accPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($accMatch.Success) {
            $base = $accMatch.Index + $accMatch.Length
            $window = $content.Substring($base, [Math]::Min(700, $content.Length - $base))
            $mr = [regex]::Match($window, '("MostRecent"\s+)"[01]"')
            if ($mr.Success) {
                $content = $content.Substring(0, $base + $mr.Index) + $mr.Groups[1].Value + '"1"' + $content.Substring($base + $mr.Index + $mr.Length)
            }
        }
        [System.IO.File]::WriteAllText($VdfPath, $content, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warning "Could not update loginusers.vdf: $($_.Exception.Message)"
    }
}

try {
    Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "AutoLoginUser" -Value $AccountName -ErrorAction Stop
    Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "RememberPassword" -Value 1 -ErrorAction Stop
} catch {
    Write-Warning "Could not update registry AutoLoginUser: $($_.Exception.Message)"
}

if ($AppID) {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent -applaunch $AppID" -WindowStyle Hidden
} else {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent" -WindowStyle Hidden
}
exit 0
'@
    Set-Content -Path $EnginePath -Value $EngineCode -Encoding UTF8
}

if (-not (Test-Path $EnginePath)) {
    try {
        Install-Engine
    } catch {
        Write-Host "[-] Failed to generate Engine.ps1: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# =====================================================================
#  UI HELPERS
# =====================================================================
function Show-Header {
    param(
        [string]$Title = "MAIN MENU",
        [string]$Subtitle = ""
    )

    Clear-Host
    $width = 60
    Write-Host ("+" + ("-" * ($width - 2)) + "+") -ForegroundColor Cyan
    Write-Host ("|" + (" " * [Math]::Floor((($width - 2) - "SteamSwitcher".Length) / 2)) + "SteamSwitcher" + (" " * [Math]::Floor((($width - 2) - "SteamSwitcher".Length) / 2)) + "|") -ForegroundColor Magenta
    Write-Host ("|" + (" " * [Math]::Floor((($width - 2) - "by Kcpx".Length) / 2)) + "by Kcpx" + (" " * [Math]::Floor((($width - 2) - "by Kcpx".Length) / 2)) + "|") -ForegroundColor DarkCyan
    Write-Host ("|" + (" " * [Math]::Floor((($width - 2) - $Title.Length) / 2)) + $Title + (" " * [Math]::Floor((($width - 2) - $Title.Length) / 2)) + "|") -ForegroundColor Yellow
    if ($Subtitle) {
        Write-Host ("|" + (" " * [Math]::Floor((($width - 2) - $Subtitle.Length) / 2)) + $Subtitle + (" " * [Math]::Floor((($width - 2) - $Subtitle.Length) / 2)) + "|") -ForegroundColor DarkCyan
    }
    Write-Host ("+" + ("-" * ($width - 2)) + "+") -ForegroundColor Cyan
    Write-Host ("-" * $width) -ForegroundColor Cyan
}

# =====================================================================
#  STEAM PATH DETECTION (portable, no hardcoded drive letters)
# =====================================================================
function Find-SteamPath {
    $path = $null
    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction Stop
        $candidate = ($reg.SteamPath -replace '/', '\')
        if ($candidate -and (Test-Path (Join-Path $candidate "Steam.exe"))) { $path = $candidate }
    } catch { }

    if (-not $path) {
        $progFiles86 = ${env:ProgramFiles(x86)}
        $progFiles   = ${env:ProgramFiles}
        $commonCandidates = @()
        if ($progFiles86) { $commonCandidates += (Join-Path $progFiles86 "Steam") }
        if ($progFiles)   { $commonCandidates += (Join-Path $progFiles "Steam") }
        foreach ($c in $commonCandidates) {
            if (Test-Path (Join-Path $c "Steam.exe")) { $path = $c; break }
        }
    }

    if (-not $path) {
        try {
            $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue
            foreach ($d in $drives) {
                if (-not $d.Root) { continue }
                $candidate = Join-Path $d.Root "Steam"
                if (Test-Path (Join-Path $candidate "Steam.exe")) { $path = $candidate; break }
            }
        } catch { }
    }

    return $path
}

function Get-ConfiguredSteamPath {
    $settings = Get-AppSettings
    if ($settings.SteamPathOverride -and (Test-Path (Join-Path $settings.SteamPathOverride "Steam.exe"))) {
        return $settings.SteamPathOverride
    }
    return Find-SteamPath
}

function Get-DetectedSteamAccount {
    $steamPath = Get-ConfiguredSteamPath
    if (-not $steamPath) {
        return $null
    }

    $vdfPath = Join-Path $steamPath "config\loginusers.vdf"
    if (-not (Test-Path $vdfPath)) {
        return $null
    }

    try {
        $reg = Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "AutoLoginUser" -ErrorAction Stop
        if ($reg.AutoLoginUser) {
            return $reg.AutoLoginUser.ToString()
        }
    } catch { }

    try {
        $content = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
    } catch {
        return $null
    }

    $blocks = [regex]::Matches($content, '(?ms)"[0-9]+"\s*\{(?<body>.*?)\}')
    $bestAccount = $null

    foreach ($block in $blocks) {
        $body = $block.Groups['body'].Value
        $accountMatch = [regex]::Match($body, '"AccountName"\s*"([^"]+)"')
        if (-not $accountMatch.Success) {
            continue
        }

        $accountName = $accountMatch.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($accountName)) {
            continue
        }

        $mostRecentMatch = [regex]::Match($body, '"MostRecent"\s*"([01])"')
        if ($mostRecentMatch.Success -and $mostRecentMatch.Groups[1].Value -eq '1') {
            return $accountName
        }

        if (-not $bestAccount) {
            $bestAccount = $accountName
        }
    }

    return $bestAccount
}

function Get-ProfileManifest {
    if (Test-Path $ProfilesPath) {
        try {
            $content = Get-Content $ProfilesPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -eq $content) { return @() }
            if ($content -is [System.Array]) { return $content }
            return @($content)
        } catch { }
    }
    return @()
}

function Save-ProfileManifest {
    param([array]$Profiles)
    $Profiles | ConvertTo-Json -Depth 5 | Set-Content -Path $ProfilesPath -Encoding UTF8
}

function Write-ProfileLauncherScript {
    param(
        [string]$ProfileFolder,
        [string]$ScriptName,
        [string]$EnginePath
    )

    $vbsPath = Join-Path $ProfileFolder "$ScriptName.vbs"
    $enginePathValue = $EnginePath.Replace('\\', '\\\\')
    $vbsCode = @'
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
vbsPath = fso.GetParentFolderName(WScript.ScriptFullName)
enginePath = "{0}"
infoPath = vbsPath & "\accountinfo.json"
cmd = "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & enginePath & """ -InfoPath """ & infoPath & """"
shell.Run cmd, 0, false
'@ -f $enginePathValue
    Set-Content -Path $vbsPath -Value $vbsCode -Encoding ASCII
    return $vbsPath
}

function Update-ProfileManifestEntry {
    param(
        [string]$ProfilePath,
        [string]$DisplayName,
        [string]$AccountName,
        [string]$AppID
    )

    $profiles = Get-ProfileManifest
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        if ($profiles[$i].Path -eq $ProfilePath) {
            if ($DisplayName) { $profiles[$i].DisplayName = $DisplayName }
            if ($AccountName) { $profiles[$i].Account = $AccountName }
            if ($null -ne $AppID) { $profiles[$i].AppID = if ($AppID) { [int]$AppID } else { $null } }
            break
        }
    }
    Save-ProfileManifest -Profiles $profiles
}

# =====================================================================
#  [1] ADD GAME PROFILE
# =====================================================================
function Add-GameProfile {
    Show-Header -Title "NEW GAME PROFILE"
    Write-Host ">>> NEW GAME PROFILE" -ForegroundColor Yellow
    Write-Host ""

    $name = (Read-Host "Enter game name").Trim()
    if ([string]::IsNullOrWhiteSpace($name)) {
        Write-Host "[-] Game name cannot be empty!" -ForegroundColor Red
        Read-Host "Press Enter to return..."
        return
    }

    $safeName = $name -replace '[\\/:*?"<>|]', '_'

    while ($true) {
        Show-Header -Title "GAME: $name"
        Write-Host ">>> GAME: $name" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  [1] Generate new game script" -ForegroundColor White
        Write-Host "  [2] Back" -ForegroundColor White
        Write-Host ("-" * 56) -ForegroundColor Cyan

        $action = (Read-Host "Choose an action [1-2]").Trim()
        switch ($action) {
            "1" {
                $account = (Read-Host "Enter Steam account name").Trim()
                if ([string]::IsNullOrWhiteSpace($account)) {
                    Write-Host "[-] Account name cannot be empty!" -ForegroundColor Red
                    Read-Host "Press Enter to continue..."
                    continue
                }

                $appId = (Read-Host "Enter Steam AppID (optional)").Trim()
                if ($appId -and (-not ($appId -match '^\d+$'))) {
                    Write-Host "[-] AppID must be a number!" -ForegroundColor Red
                    Read-Host "Press Enter to continue..."
                    continue
                }

                Show-Header -Title "GAME: $name"
                Write-Host ">>> GAME: $name" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  [1] Auto-save to current games storage folder" -ForegroundColor White
                Write-Host "  [2] Manual folder path" -ForegroundColor White
                Write-Host ("-" * 56) -ForegroundColor Cyan

                $storageChoice = (Read-Host "Choose storage option [1-2]").Trim()
                $targetFolder = $null
                switch ($storageChoice) {
                    "1" {
                        $targetFolder = Join-Path $GamesFolder $safeName
                    }
                    "2" {
                        $manualFolder = (Read-Host "Enter full folder path for this game profile").Trim()
                        if ([string]::IsNullOrWhiteSpace($manualFolder)) {
                            Write-Host "[-] Folder path cannot be empty!" -ForegroundColor Red
                            Read-Host "Press Enter to continue..."
                            continue
                        }
                        if (-not [System.IO.Path]::IsPathRooted($manualFolder)) {
                            $manualFolder = Join-Path $RootFolder $manualFolder
                        }
                        $targetFolder = Join-Path $manualFolder $safeName
                    }
                    default {
                        Write-Host "[-] Invalid storage option!" -ForegroundColor Red
                        Read-Host "Press Enter to continue..."
                        continue
                    }
                }

                if (Test-Path $targetFolder) {
                    Write-Host "[!] A profile for '$name' already exists at that location!" -ForegroundColor Yellow
                    Read-Host "Press Enter to continue..."
                    continue
                }

                New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null

                $jsonObj = [PSCustomObject]@{
                    AccountName = $account
                    AppID       = if ($appId) { [int]$appId } else { $null }
                }
                $jsonObj | ConvertTo-Json | Set-Content -Path (Join-Path $targetFolder "accountinfo.json") -Encoding UTF8

                $profiles = Get-ProfileManifest
                $profiles += [PSCustomObject]@{
                    DisplayName = $name
                    Name        = $safeName
                    Path        = $targetFolder
                    Account     = $account
                    AppID       = if ($appId) { [int]$appId } else { $null }
                    Json        = (Join-Path $targetFolder "accountinfo.json")
                }
                Save-ProfileManifest -Profiles $profiles

                $null = Write-ProfileLauncherScript -ProfileFolder $targetFolder -ScriptName $safeName -EnginePath $EnginePath

                Write-Host ""
                Write-Host "[+] Game '$name' has been successfully added!" -ForegroundColor Green
                Write-Host "[+] Launcher ready inside: $targetFolder\$safeName.vbs" -ForegroundColor Green
                Read-Host "Press Enter to continue..."
                return
            }
            "2" {
                return
            }
            default {
                Write-Host "[-] Invalid option!" -ForegroundColor Red
                Read-Host "Press Enter to continue..."
            }
        }
    }
}

# =====================================================================
#  [2] GAMES DATABASE LIST / MANAGE
# =====================================================================
function Get-GameProfiles {
    $profiles = @()
    $manifest = Get-ProfileManifest
    foreach ($entry in $manifest) {
        if ($null -eq $entry -or [string]::IsNullOrWhiteSpace($entry.Path)) { continue }
        $jsonFile = if ($entry.Json) { $entry.Json } else { Join-Path $entry.Path "accountinfo.json" }
        if (Test-Path $jsonFile) {
            try {
                $info = Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
                $profiles += [PSCustomObject]@{
                    ID          = $profiles.Count + 1
                    Name        = if ($entry.Name) { $entry.Name } else { [System.IO.Path]::GetFileName($entry.Path) }
                    DisplayName = if ($entry.DisplayName) { $entry.DisplayName } else { if ($entry.Name) { $entry.Name } else { [System.IO.Path]::GetFileName($entry.Path) } }
                    Account     = if ($entry.Account) { $entry.Account } else { $info.AccountName }
                    AppID       = if ($entry.AppID) { $entry.AppID } else { if ($info.AppID) { $info.AppID } else { "None" } }
                    Path        = $entry.Path
                    Json        = $jsonFile
                }
            } catch { }
        }
    }

    if ($profiles.Count -eq 0 -and (Test-Path $GamesFolder)) {
        $subDirs = Get-ChildItem -Path $GamesFolder -Directory -ErrorAction SilentlyContinue
        foreach ($d in $subDirs) {
            $jsonFile = Join-Path $d.FullName "accountinfo.json"
            if (Test-Path $jsonFile) {
                try {
                    $info = Get-Content $jsonFile -Raw -Encoding UTF8 | ConvertFrom-Json
                    $profiles += [PSCustomObject]@{
                        ID          = $profiles.Count + 1
                        Name        = $d.Name
                        DisplayName = $d.Name
                        Account     = $info.AccountName
                        AppID       = if ($info.AppID) { $info.AppID } else { "None" }
                        Path        = $d.FullName
                        Json        = $jsonFile
                    }
                } catch { }
            }
        }
    }

    return $profiles
}

function Show-GamesDatabase {
    while ($true) {
        Show-Header -Title "MANAGE GAMES PROFILES"
        Write-Host ">>> MANAGE GAMES PROFILES" -ForegroundColor Yellow
        Write-Host ""

        $profiles = @(Get-GameProfiles)
        for ($i = 0; $i -lt $profiles.Count; $i++) {
            $profiles[$i].ID = $i + 1
        }

        if ($profiles.Count -eq 0) {
            Write-Host "No games registered yet. Go back and add some!" -ForegroundColor Yellow
            Read-Host "Press Enter to return..."
            return
        }

        Write-Host ("{0,-4} | {1,-22} | {2,-15} | {3,-8}" -f "ID", "Game Profile Name", "Steam Account", "AppID") -ForegroundColor Cyan
        Write-Host ("-" * 56) -ForegroundColor Cyan
        foreach ($p in $profiles) {
            $displayName = if ($p.DisplayName) { $p.DisplayName } else { $p.Name }
            if ($displayName.Length -gt 22) { $displayName = $displayName.Substring(0, 19) + "..." }
            $displayAcc  = if ($p.Account.Length -gt 15) { $p.Account.Substring(0, 12) + "..." } else { $p.Account }
            Write-Host ("{0,-4} | {1,-22} | {2,-15} | {3,-8}" -f $p.ID, $displayName, $displayAcc, $p.AppID) -ForegroundColor White
        }
        Write-Host ("-" * 56) -ForegroundColor Cyan

        $choice = (Read-Host "Select profile number (or 'b' to go back)").Trim()
        if ($choice -eq 'b') { return }

        if ($choice -match '^\d+$') {
            $selected = $profiles | Where-Object { $_.ID -eq [int]$choice } | Select-Object -First 1
            if ($selected) {
                Invoke-GameProfileMenu $selected
            } else {
                Write-Host "[-] Invalid profile number!" -ForegroundColor Red
                Read-Host "Press Enter to continue..."
            }
        } else {
            Write-Host "[-] Invalid input format!" -ForegroundColor Red
            Read-Host "Press Enter to continue..."
        }
    }
}

function Invoke-GameProfileMenu {
    param($Game)
    while ($true) {
        Show-Header -Title "PROFILE: $($Game.DisplayName)"
        Write-Host ">>> PROFILE: $($Game.DisplayName)" -ForegroundColor Yellow
        Write-Host " Account: $($Game.Account)" -ForegroundColor White
        Write-Host " AppID  : $($Game.AppID)" -ForegroundColor White
        Write-Host ("-" * 56) -ForegroundColor Cyan
        Write-Host "  [1] Generate new game script" -ForegroundColor White
        Write-Host "  [2] Edit profile" -ForegroundColor White
        Write-Host "  [3] Delete profile" -ForegroundColor White
        Write-Host "  [4] Back" -ForegroundColor White
        Write-Host ("-" * 56) -ForegroundColor Cyan

        $action = (Read-Host "Choose action [1-4]").Trim()
        switch ($action) {
            "1" {
                $scriptPath = Write-ProfileLauncherScript -ProfileFolder $Game.Path -ScriptName $Game.Name -EnginePath $EnginePath
                Write-Host "[+] Script generated: $scriptPath" -ForegroundColor Green
                Read-Host "Press Enter to continue..."
                return
            }
            "2" {
                $editLoop = $true
                while ($editLoop) {
                    Show-Header -Title "EDIT PROFILE"
                    Write-Host ">>> EDIT PROFILE: $($Game.DisplayName)" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "  [1] Edit game name" -ForegroundColor White
                    Write-Host "  [2] Edit Steam account" -ForegroundColor White
                    Write-Host "  [3] Edit AppID" -ForegroundColor White
                    Write-Host "  [4] Back" -ForegroundColor White
                    Write-Host ("-" * 56) -ForegroundColor Cyan

                    $editAction = (Read-Host "Choose action [1-4]").Trim()
                    switch ($editAction) {
                        "1" {
                            $newName = (Read-Host "Enter new game name").Trim()
                            if ([string]::IsNullOrWhiteSpace($newName)) {
                                Write-Host "[-] Name cannot be empty!" -ForegroundColor Red
                            } else {
                                Update-ProfileManifestEntry -ProfilePath $Game.Path -DisplayName $newName -AccountName $null -AppID $null
                                $Game.DisplayName = $newName
                                Write-Host "[+] Game name updated." -ForegroundColor Green
                            }
                        }
                        "2" {
                            $newAccount = (Read-Host "Enter new Steam account name").Trim()
                            if ([string]::IsNullOrWhiteSpace($newAccount)) {
                                Write-Host "[-] Account name cannot be empty!" -ForegroundColor Red
                            } else {
                                $jsonPath = Join-Path $Game.Path "accountinfo.json"
                                $jsonObj = [PSCustomObject]@{ AccountName = $newAccount; AppID = if ($Game.AppID -and $Game.AppID -ne 'None') { [int]$Game.AppID } else { $null } }
                                $jsonObj | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8
                                Update-ProfileManifestEntry -ProfilePath $Game.Path -DisplayName $null -AccountName $newAccount -AppID $null
                                $Game.Account = $newAccount
                                Write-Host "[+] Steam account updated." -ForegroundColor Green
                            }
                        }
                        "3" {
                            $newAppId = (Read-Host "Enter new Steam AppID (optional)").Trim()
                            if ($newAppId -and (-not ($newAppId -match '^\d+$'))) {
                                Write-Host "[-] AppID must be a number!" -ForegroundColor Red
                            } else {
                                $jsonPath = Join-Path $Game.Path "accountinfo.json"
                                $jsonObj = [PSCustomObject]@{ AccountName = $Game.Account; AppID = if ($newAppId) { [int]$newAppId } else { $null } }
                                $jsonObj | ConvertTo-Json | Set-Content -Path $jsonPath -Encoding UTF8
                                Update-ProfileManifestEntry -ProfilePath $Game.Path -DisplayName $null -AccountName $null -AppID $newAppId
                                $Game.AppID = if ($newAppId) { [int]$newAppId } else { "None" }
                                Write-Host "[+] AppID updated." -ForegroundColor Green
                            }
                        }
                        "4" { $editLoop = $false; break }
                        default { Write-Host "[-] Invalid option." -ForegroundColor Red }
                    }
                    if ($editLoop) {
                        Read-Host "Press Enter to continue..."
                    }
                }
                continue
            }
            "3" {
                $confirm = (Read-Host "Are you sure you want to delete '$($Game.DisplayName)'? (y/n)").Trim()
                if ($confirm -eq 'y') {
                    Remove-Item -Path $Game.Path -Recurse -Force

                    $profiles = Get-ProfileManifest
                    $profiles = @($profiles | Where-Object { $_.Path -ne $Game.Path })
                    Save-ProfileManifest -Profiles $profiles

                    Write-Host "[+] Profile deleted completely." -ForegroundColor Green
                    Read-Host "Press Enter to continue..."
                    return
                }
            }
            "4" { return }
            default {
                Write-Host "[-] Invalid option." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

# =====================================================================
#  [3] SETUP PATHS
# =====================================================================
function Set-SteamPathConfig {
    while ($true) {
        Show-Header -Title "SETUP PATHS"
        Write-Host ">>> SETUP PATHS" -ForegroundColor Yellow
        Write-Host ""

        $detected = Find-SteamPath
        $detectedAccount = Get-DetectedSteamAccount
        $settings = Get-AppSettings
        $currentOverride = $settings.SteamPathOverride
        $gamesFolderDisplay = if ($settings.GamesFolderOverride) { $settings.GamesFolderOverride } else { $GamesFolder }

        Write-Host ""
        if ($detected) {
            Write-Host "[+] Auto-detected Steam path: $detected" -ForegroundColor Green
        } else {
            Write-Host "[-] Could not auto-detect a valid Steam installation." -ForegroundColor Red
        }

        if ($detectedAccount) {
            Write-Host "[+] Auto-detected Steam account: $detectedAccount" -ForegroundColor Green
        } else {
            Write-Host "[-] Could not auto-detect a Steam account." -ForegroundColor Yellow
        }

        if ($currentOverride) {
            Write-Host "[i] Manual Steam override: $currentOverride" -ForegroundColor Cyan
        } else {
            Write-Host "[i] Manual Steam override: None (auto-detect)" -ForegroundColor Cyan
        }
        Write-Host "[i] Games storage folder: $gamesFolderDisplay" -ForegroundColor Cyan

        Write-Host ""
        Write-Host "  [1] Enter manual Steam path" -ForegroundColor White
        Write-Host "  [2] Set games script folder" -ForegroundColor White
        Write-Host "  [3] Clear manual overrides" -ForegroundColor White
        Write-Host "  [4] Back to main menu" -ForegroundColor White
        Write-Host ("-" * 56) -ForegroundColor Cyan

        $choice = (Read-Host "Choose an option [1-4]").Trim()
        switch ($choice) {
            "1" {
                $manual = (Read-Host "Enter full path to Steam folder").Trim()
                if ([string]::IsNullOrWhiteSpace($manual)) {
                    Write-Host "[-] Path cannot be empty." -ForegroundColor Red
                } elseif (-not (Test-Path (Join-Path $manual "Steam.exe"))) {
                    Write-Host "[-] Steam.exe was not found in that path!" -ForegroundColor Red
                } else {
                    $settings = Get-AppSettings
                    $settings.SteamPathOverride = $manual
                    Save-AppSettings -Settings $settings
                    $script:Settings = $settings
                    Write-Host "[+] Manual Steam path saved: $manual" -ForegroundColor Green
                }
            }
            "2" {
                $manualFolder = (Read-Host "Enter full path to the folder where game profiles will be stored").Trim()
                if ([string]::IsNullOrWhiteSpace($manualFolder)) {
                    Write-Host "[-] Path cannot be empty." -ForegroundColor Red
                } else {
                    if (-not [System.IO.Path]::IsPathRooted($manualFolder)) {
                        $manualFolder = Join-Path $RootFolder $manualFolder
                    }
                    New-Item -ItemType Directory -Path $manualFolder -Force | Out-Null
                    $settings = Get-AppSettings
                    $settings.GamesFolderOverride = $manualFolder
                    Save-AppSettings -Settings $settings
                    $script:Settings = $settings
                    $GamesFolder = $manualFolder
                    Write-Host "[+] Games storage folder saved: $manualFolder" -ForegroundColor Green
                }
            }
            "3" {
                $settings = New-DefaultAppSettings
                Save-AppSettings -Settings $settings
                $script:Settings = $settings
                $GamesFolder = Join-Path $RootFolder "Games"
                New-Item -ItemType Directory -Path $GamesFolder -Force | Out-Null
                Write-Host "[+] Manual overrides cleared. Auto-detection will be used." -ForegroundColor Green
            }
            "4" { return }
            default { Write-Host "[-] Invalid option." -ForegroundColor Red }
        }
        Read-Host "Press Enter to continue..."
    }
}

# =====================================================================
#  [4] SOFTWARE INFO
# =====================================================================
function Show-SoftwareInfo {
    Show-Header -Title "SOFTWARE INFORMATION"
    Write-Host ">>> SOFTWARE INFORMATION" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SteamSwitcher - Multi-Account Steam Launcher" -ForegroundColor Magenta
    Write-Host ""
    Write-Host " Version : 1.0" -ForegroundColor White
    Write-Host " Author  : Kcpx_" -ForegroundColor White
    Write-Host " GitHub  : https://github.com/kacpix0000" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " This tool helps you manage multiple Steam accounts and" -ForegroundColor White
    Write-Host " quickly switch between them, optionally launching a" -ForegroundColor White
    Write-Host " specific game right after the switch completes." -ForegroundColor White
    Write-Host ("-" * 56) -ForegroundColor Cyan
    Read-Host "Press Enter to return..."
}

# =====================================================================
#  MAIN CONTROLLER LOOP
# =====================================================================
while ($true) {
    Show-Header -Title "MAIN MENU"
    Write-Host "  [1] Create game profile" -ForegroundColor White
    Write-Host "  [2] Manage game profiles" -ForegroundColor White
    Write-Host "  [3] Setup paths" -ForegroundColor White
    Write-Host "  [4] Software Info" -ForegroundColor White
    Write-Host "  [5] Exit Application" -ForegroundColor White
    Write-Host ("-" * 56) -ForegroundColor Cyan

    $sysChoice = (Read-Host "Enter your selection [1-5]").Trim()
    try {
        switch ($sysChoice) {
            "1" {
                Add-GameProfile
            }
            "2" {
                Show-GamesDatabase
            }
            "3" {
                Set-SteamPathConfig
            }
            "4" {
                Show-SoftwareInfo
            }
            "5" {
                Show-Header
                Write-Host "Closing SteamSwitcher. Have a good game session!" -ForegroundColor Cyan
                Start-Sleep -Milliseconds 300
                exit
            }
            default {
                Write-Host "Invalid option chosen! Press Enter to try again..." -ForegroundColor Red
                Read-Host | Out-Null
            }
        }
    } catch {
        Write-Host "[-] An unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host "Press Enter to continue..."
    }
}