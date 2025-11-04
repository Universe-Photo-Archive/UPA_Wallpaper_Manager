param([string]$OldVersion, [string]$NewVersion)

$ErrorActionPreference = "Stop"

function Replace-VersionInFile {
    param([string]$FilePath, [string]$OldPattern, [string]$NewPattern, [string]$Description)
    
    try {
        if (Test-Path $FilePath) {
            Write-Host "  -> $Description" -ForegroundColor Cyan
            $content = Get-Content $FilePath -Raw -Encoding UTF8
            $newContent = $content -replace [regex]::Escape($OldPattern), $NewPattern
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            [System.IO.File]::WriteAllText($FilePath, $newContent, $utf8NoBom)
            Write-Host "    OK" -ForegroundColor Green
            return $true
        } else {
            Write-Host "    ERREUR" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "    ERREUR: $_" -ForegroundColor Red
        return $false
    }
}

Write-Host "Changement: $OldVersion -> $NewVersion"
$success = $true

$success = $success -and (Replace-VersionInFile "src\utils\update_manager.py" "CURRENT_VERSION = ""$OldVersion""" "CURRENT_VERSION = ""$NewVersion""" "update_manager.py")
$success = $success -and (Replace-VersionInFile "langs\fr.json" """app.version"": ""Version $OldVersion""" """app.version"": ""Version $NewVersion""" "fr.json")
$success = $success -and (Replace-VersionInFile "langs\en.json" """app.version"": ""Version $OldVersion""" """app.version"": ""Version $NewVersion""" "en.json")
$success = $success -and (Replace-VersionInFile "installer_setup.iss" "#define MyAppVersion ""$OldVersion""" "#define MyAppVersion ""$NewVersion""" "installer_setup.iss")
$success = $success -and (Replace-VersionInFile "BUILD_INSTALLER.bat" "UPA_Wallpaper_Manager_${OldVersion}_Setup.exe" "UPA_Wallpaper_Manager_${NewVersion}_Setup.exe" "BUILD_INSTALLER.bat")

$OldVersionInfo = "$OldVersion.0"
$NewVersionInfo = "$NewVersion.0"

$success = $success -and (Replace-VersionInFile "version_info.txt" "StringStruct('FileVersion', '$OldVersionInfo')" "StringStruct('FileVersion', '$NewVersionInfo')" "version_info.txt FileVersion")
$success = $success -and (Replace-VersionInFile "version_info.txt" "StringStruct('ProductVersion', '$OldVersionInfo')" "StringStruct('ProductVersion', '$NewVersionInfo')" "version_info.txt ProductVersion")

if ($success) { 
    Write-Host "SUCCES" -ForegroundColor Green
    exit 0 
} else { 
    Write-Host "ECHEC" -ForegroundColor Red
    exit 1 
}
