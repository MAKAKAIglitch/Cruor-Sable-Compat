#requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$Repository = "MAKAKAIglitch/Cruor-Sable-Compat"
$Branch = "main"
$ArchiveUrl = "https://codeload.github.com/$Repository/zip/refs/heads/$Branch"
$ExpectedModId = "cruor_sable_compat"
$ManifestName = ".cruor-sable-compat-update-manifest.txt"
$ManifestPath = Join-Path $ProjectRoot $ManifestName
$BackupRoot = Join-Path $ProjectRoot ".cruor-sable-compat-backups"
$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ("CruorSableCompatUpdater-" + [guid]::NewGuid().ToString("N"))
$StageRoot = Join-Path $TempRoot "stage"
$ZipPath = Join-Path $TempRoot "cruor-sable-compat-main.zip"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# Local game data, generated output, caches and user settings are never modified.
$ProtectedTopLevel = @(
    ".git", ".tools", ".gradle", ".idea", ".vscode",
    ".cruor-sable-compat-backups",
    "build", "run", "runs", "mods", "config",
    "saves", "logs", "crash-reports", "screenshots",
    "resourcepacks", "shaderpacks"
)
$ProtectedFiles = @("options.txt", "servers.dat")

function Test-ProtectedPath {
    param([Parameter(Mandatory = $true)][string] $RelativePath)

    $normalized = $RelativePath.Replace("\", "/").TrimStart("/")
    $first = ($normalized -split "/", 2)[0]
    if ($ProtectedTopLevel -contains $first) { return $true }
    if ($ProtectedFiles -contains $normalized) { return $true }
    if ($normalized -eq $ManifestName) { return $true }
    return $false
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string] $Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-SafeDestination {
    param(
        [Parameter(Mandatory = $true)][string] $Root,
        [Parameter(Mandatory = $true)][string] $RelativePath
    )

    $relative = $RelativePath.Replace("/", "\")
    if ([IO.Path]::IsPathRooted($relative) -or $relative -match '(^|\\)\.\.(\\|$)' -or $relative.Contains(":")) {
        throw "Unsafe path received from the GitHub archive or manifest: $RelativePath"
    }

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd("\") + "\"
    $destination = [IO.Path]::GetFullPath((Join-Path $Root $relative))
    if (!$destination.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes the destination folder: $RelativePath"
    }
    return $destination
}

function Get-ModId {
    param([Parameter(Mandatory = $true)][string] $PropertiesPath)

    if (!(Test-Path -LiteralPath $PropertiesPath -PathType Leaf)) {
        return $null
    }

    $line = Get-Content -LiteralPath $PropertiesPath |
        Where-Object { $_ -match '^\s*mod_id\s*=' } |
        Select-Object -First 1
    if (!$line) { return $null }

    return (($line -split "=", 2)[1]).Trim()
}

function Expand-VerifiedArchive {
    param(
        [Parameter(Mandatory = $true)][string] $Archive,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    [IO.Directory]::CreateDirectory($Destination) | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace("\", "/")
            if ([string]::IsNullOrWhiteSpace($name) -or $name.EndsWith("/")) { continue }

            $parts = $name.Split("/")
            if ($parts.Count -lt 2) { continue }
            $relative = ($parts | Select-Object -Skip 1) -join "/"
            if ([string]::IsNullOrWhiteSpace($relative) -or (Test-ProtectedPath -RelativePath $relative)) { continue }

            $target = Get-SafeDestination -Root $Destination -RelativePath $relative
            $parent = Split-Path -Parent $target
            [IO.Directory]::CreateDirectory($parent) | Out-Null

            $inputStream = $entry.Open()
            try {
                $outputStream = [IO.File]::Create($target)
                try { $inputStream.CopyTo($outputStream) }
                finally { $outputStream.Dispose() }
            }
            finally { $inputStream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
}

try {
    Write-Host ""
    Write-Host " Cruor Sable Compat source updater" -ForegroundColor White
    Write-Host " Repository: $Repository | Branch: $Branch" -ForegroundColor DarkGray
    Write-Host " Mode: direct download from GitHub (Git is not required)" -ForegroundColor Cyan
    Write-Host ""

    $localRequired = @("build.bat", "gradlew", "settings.gradle", "build.gradle", "gradle.properties")
    foreach ($file in $localRequired) {
        if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot $file) -PathType Leaf)) {
            throw "Required project file '$file' was not found. Keep update-sources.bat in the Cruor Sable Compat project root."
        }
    }

    $localModId = Get-ModId -PropertiesPath (Join-Path $ProjectRoot "gradle.properties")
    if ($localModId -ne $ExpectedModId) {
        throw "This folder is not the expected Cruor Sable Compat project (mod_id='$localModId'). No files were changed."
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    [IO.Directory]::CreateDirectory($TempRoot) | Out-Null

    Write-Host "[1/4] Downloading the latest main branch from GitHub..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $ZipPath -UseBasicParsing -Headers @{
        "User-Agent" = "Cruor-Sable-Compat-Source-Updater"
        "Accept" = "application/vnd.github+json"
    }

    if (!(Test-Path -LiteralPath $ZipPath) -or (Get-Item -LiteralPath $ZipPath).Length -lt 1024) {
        throw "GitHub returned an empty or unexpectedly small archive."
    }

    Write-Host "[2/4] Extracting and validating the archive..." -ForegroundColor Cyan
    Expand-VerifiedArchive -Archive $ZipPath -Destination $StageRoot

    $required = @("build.bat", "gradlew", "settings.gradle", "build.gradle", "gradle.properties")
    foreach ($file in $required) {
        if (!(Test-Path -LiteralPath (Join-Path $StageRoot $file) -PathType Leaf)) {
            throw "The downloaded archive is incomplete: required file '$file' is missing. Existing sources were not changed."
        }
    }

    $stagedModId = Get-ModId -PropertiesPath (Join-Path $StageRoot "gradle.properties")
    if ($stagedModId -ne $ExpectedModId) {
        throw "The downloaded repository does not identify itself as '$ExpectedModId'. Existing sources were not changed."
    }

    $newFiles = @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -Force | ForEach-Object {
        $_.FullName.Substring($StageRoot.Length).TrimStart("\").Replace("\", "/")
    } | Sort-Object -Unique)

    if ($newFiles.Count -lt 5) {
        throw "The downloaded source archive contains too few files. Existing sources were not changed."
    }

    $oldFiles = @()
    if (Test-Path -LiteralPath $ManifestPath -PathType Leaf) {
        $oldFiles = @(Get-Content -LiteralPath $ManifestPath | Where-Object {
            $_ -and $_ -notmatch '(^/|(^|/)\.\.(/|$)|:)' -and !(Test-ProtectedPath -RelativePath $_)
        })
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDirectory = Join-Path $BackupRoot $stamp
    $changed = 0
    $unchanged = 0
    $removed = 0
    $backedUp = 0

    Write-Host "[3/4] Updating project source files..." -ForegroundColor Cyan
    foreach ($relative in $newFiles) {
        $source = Get-SafeDestination -Root $StageRoot -RelativePath $relative
        $target = Get-SafeDestination -Root $ProjectRoot -RelativePath $relative
        $targetParent = Split-Path -Parent $target
        [IO.Directory]::CreateDirectory($targetParent) | Out-Null

        if (Test-Path -LiteralPath $target -PathType Leaf) {
            if ((Get-Sha256 -Path $source) -eq (Get-Sha256 -Path $target)) {
                $unchanged++
                continue
            }

            $backup = Get-SafeDestination -Root $backupDirectory -RelativePath $relative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            Copy-Item -LiteralPath $target -Destination $backup -Force
            $backedUp++
        }

        $temporaryTarget = "$target.cruor-update-tmp"
        Copy-Item -LiteralPath $source -Destination $temporaryTarget -Force
        Move-Item -LiteralPath $temporaryTarget -Destination $target -Force
        $changed++
    }

    # Remove only source files recorded by an earlier successful update.
    # Back up obsolete files before removing them; unrelated local files are not scanned.
    $newSet = @{}
    foreach ($relative in $newFiles) { $newSet[$relative.ToLowerInvariant()] = $true }

    foreach ($relative in $oldFiles) {
        if ($newSet.ContainsKey($relative.ToLowerInvariant())) { continue }
        $stale = Get-SafeDestination -Root $ProjectRoot -RelativePath $relative
        if (Test-Path -LiteralPath $stale -PathType Leaf) {
            $backup = Get-SafeDestination -Root $backupDirectory -RelativePath $relative
            [IO.Directory]::CreateDirectory((Split-Path -Parent $backup)) | Out-Null
            Copy-Item -LiteralPath $stale -Destination $backup -Force
            Remove-Item -LiteralPath $stale -Force
            $removed++
            $backedUp++
        }
    }

    $manifestTemp = "$ManifestPath.tmp"
    [IO.File]::WriteAllLines($manifestTemp, $newFiles, $Utf8NoBom)
    Move-Item -LiteralPath $manifestTemp -Destination $ManifestPath -Force

    Write-Host "[4/4] Finished." -ForegroundColor Cyan
    Write-Host ""
    Write-Host " ==========================================" -ForegroundColor Green
    Write-Host " CRUOR SABLE COMPAT SOURCES UPDATED" -ForegroundColor Green
    Write-Host " ==========================================" -ForegroundColor Green
    Write-Host "Updated files: $changed" -ForegroundColor Green
    Write-Host "Already current: $unchanged" -ForegroundColor Gray
    Write-Host "Obsolete files removed: $removed" -ForegroundColor Gray
    Write-Host "Backup copies: $backedUp" -ForegroundColor Gray
    if ($backedUp -gt 0) {
        Write-Host "Backup folder: .cruor-sable-compat-backups\$stamp" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Git is not needed. Run build.bat to compile the updated mod." -ForegroundColor White
    Write-Host ""
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[UPDATE ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Local game folders and generated build output are protected." -ForegroundColor DarkGray
    Write-Host "Any changed source files are backed up in .cruor-sable-compat-backups when possible." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}
finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
