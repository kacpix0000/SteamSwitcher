#Requires -Version 5.1
param([Parameter(Mandatory = $true)][string]$InfoPath)
$ErrorActionPreference = "Stop"

if (-not (Test-Path $InfoPath)) { throw "accountinfo.json not found: $InfoPath" }

$Info = Get-Content $InfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$AccountName = $Info.AccountName
$AppID = $Info.AppID

Write-Host "[DEBUG] Engine started | Account: $AccountName" -ForegroundColor Cyan

function Find-SteamInstallPath {
    $path = ""
    try { $path = (Get-ItemProperty "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction Stop).SteamPath -replace '/', '\' } catch {}
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

function Close-Steam {
    $procs = Get-Process -Name "steam*" -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

Close-Steam

# BEZPIECZNA EDYCJA VDF
if (Test-Path $VdfPath) {
    # Kopia zapasowa
    Copy-Item -Path $VdfPath -Destination "$VdfPath.bak" -Force

    $content = [System.IO.File]::ReadAllText($VdfPath, [System.Text.Encoding]::UTF8)
    # Zresetuj MostRecent dla wszystkich
    $content = [regex]::Replace($content, '("MostRecent"\s+)"1"', '$1"0"')

    $accPattern = '"AccountName"\s+"' + [regex]::Escape($AccountName) + '"'
    $accMatch = [regex]::Match($content, $accPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    
    if ($accMatch.Success) {
        $base = $accMatch.Index + $accMatch.Length
        $maxLen = [Math]::Min(700, $content.Length - $base)
        $win = $content.Substring($base, $maxLen)
        
        # Ustaw MostRecent na 1
        $mr = [regex]::Match($win, '("MostRecent"\s+)"[01]"')
        if ($mr.Success) {
            $pos = $base + $mr.Index
            $content = $content.Substring(0, $pos) + $mr.Groups[1].Value + '"1"' + $content.Substring($pos + $mr.Length)
        }
        
        # Ustaw RememberPassword na 1 (tylko jeśli istnieje w bloku, bez wpychania go na siłę i psucia pliku!)
        $rp = [regex]::Match($win, '("RememberPassword"\s+)"0"')
        if ($rp.Success) {
            $pos2 = $base + $rp.Index
            $content = $content.Substring(0, $pos2) + $rp.Groups[1].Value + '"1"' + $content.Substring($pos2 + $rp.Length)
        }
        
        [System.IO.File]::WriteAllText($VdfPath, $content, [System.Text.Encoding]::UTF8)
        Write-Host "[DEBUG] VDF Updated for $AccountName" -ForegroundColor Green
    }
}

# REJESTR
try {
    Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "AutoLoginUser" -Value $AccountName -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "RememberPassword" -Value 1 -ErrorAction SilentlyContinue
} catch {}

if ($AppID) {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent -applaunch $AppID" -WindowStyle Hidden
} else {
    Start-Process -FilePath $SteamExe -ArgumentList "-silent" -WindowStyle Hidden
}
exit 0
