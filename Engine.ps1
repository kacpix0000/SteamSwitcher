#Requires -Version 5.1
<#
    Engine.ps1
    Shared Steam account-switching backend handler.
#>
param([Parameter(Mandatory = $true)][string]$InfoPath)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $InfoPath)) { throw "accountinfo.json not found: $InfoPath" }

$Info = Get-Content $InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$AccountName = $Info.AccountName
$AppID = $Info.AppID

function Find-SteamInstallPath {
    $path = ""
    try {
        $path = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction Stop).SteamPath -replace '/', '\'
    } catch {}
    if (-not (Test-Path "$path\Steam.exe")) {
        foreach ($candidate in @("C:\Program Files (x86)\Steam", "C:\Program Files\Steam", "D:\Steam", "E:\Steam", "C:\Steam")) {
            if (Test-Path "$candidate\Steam.exe") { $path = $candidate; break }
        }
    }
    return $path
}

$SteamPath = Find-SteamInstallPath
if (-not $SteamPath -or -not (Test-Path "$SteamPath\Steam.exe")) { throw "Steam installation could not be found." }
$SteamExe = Join-Path $SteamPath "Steam.exe"
$VdfPath  = Join-Path $SteamPath "config\loginusers.vdf"

if (Get-Process -Name "steam*" -ErrorAction SilentlyContinue) {
    Get-Process -Name "steam*" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 800
}

if (Test-Path $VdfPath) {
    $content = [System.IO.File]::ReadAllText($VdfPath, [System.Text.Encoding]::UTF8)
    $content = [regex]::Replace($content, '("MostRecent"\s+)"1"', '$1"0"')
    $accPattern = '"AccountName"\s+"' + [regex]::Escape($AccountName) + '"'
    $accMatch = [regex]::Match($content, $accPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($accMatch.Success) {
        $base = $accMatch.Index + $accMatch.Length
        $window = $content.Substring($base, [Math]::Min(700, $content.Length - $base))
        $mr = [regex]::Match($window, '("MostRecent"\s+)"[01]"')
        if ($mr.Success) {
            $pos = $base + $mr.Index
            $content = $content.Substring(0, $pos) + $mr.Groups[1].Value + '"1"' + $content.Substring($pos + $mr.Length)
        }
        [System.IO.File]::WriteAllText($VdfPath, $content, [System.Text.Encoding]::UTF8)
    }
}

Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "AutoLoginUser" -Value $AccountName
Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "RememberPassword" -Value 1

if ($AppID) {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent -applaunch $AppID" -WindowStyle Hidden
} else {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent" -WindowStyle Hidden
}
exit 0