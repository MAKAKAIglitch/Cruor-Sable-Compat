[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $GradleArgs
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ToolsRoot = Join-Path $ProjectRoot ".tools"
$JdkInstallRoot = Join-Path $ToolsRoot "jdk-21-temurin"
$DownloadRoot = Join-Path $ToolsRoot "downloads"

function Write-Info([string] $Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok([string] $Message) {
    Write-Host "[ OK ] $Message" -ForegroundColor Green
}

function Write-Warn([string] $Message) {
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Invoke-NativeVersion([string] $Executable, [string[]] $Arguments) {
    # Capture native stdout/stderr through .NET so PowerShell 5.1 does not
    # render java -version stderr as a misleading NativeCommandError.
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $Executable
    $StartInfo.Arguments = [string]::Join(" ", $Arguments)
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $StartInfo
    try {
        if (!$Process.Start()) {
            return $null
        }

        $StdoutTask = $Process.StandardOutput.ReadToEndAsync()
        $StderrTask = $Process.StandardError.ReadToEndAsync()
        $Process.WaitForExit()

        $Output = $StdoutTask.GetAwaiter().GetResult() +
            [Environment]::NewLine +
            $StderrTask.GetAwaiter().GetResult()
        if ($Process.ExitCode -ne 0) {
            return $null
        }
        return $Output.Trim()
    }
    finally {
        $Process.Dispose()
    }
}

function Get-Jdk21([string] $Candidate) {
    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $Candidate = [Environment]::ExpandEnvironmentVariables($Candidate.Trim().Trim('"'))
    if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
        $Leaf = [IO.Path]::GetFileName($Candidate)
        if ($Leaf -notin @("java.exe", "javaw.exe", "javac.exe")) {
            return $null
        }
        $Candidate = Split-Path (Split-Path $Candidate -Parent) -Parent
    }

    $JavaExe = Join-Path $Candidate "bin\java.exe"
    $JavacExe = Join-Path $Candidate "bin\javac.exe"
    if (!(Test-Path -LiteralPath $JavaExe -PathType Leaf) -or
        !(Test-Path -LiteralPath $JavacExe -PathType Leaf)) {
        return $null
    }

    $JavaVersion = Invoke-NativeVersion $JavaExe @("-version")
    $CompilerVersion = Invoke-NativeVersion $JavacExe @("-version")
    if (!$JavaVersion -or !$CompilerVersion) {
        return $null
    }

    $JavaMatch = [regex]::Match($JavaVersion, 'version\s+"(?<major>\d+)')
    $CompilerMatch = [regex]::Match($CompilerVersion, 'javac\s+(?<major>\d+)')
    if (!$JavaMatch.Success -or !$CompilerMatch.Success) {
        return $null
    }

    if ($JavaMatch.Groups["major"].Value -ne "21" -or
        $CompilerMatch.Groups["major"].Value -ne "21") {
        return $null
    }

    return [PSCustomObject]@{
        Home = (Resolve-Path -LiteralPath $Candidate).Path
        Major = 21
        Version = $JavaVersion
    }
}

function Find-Jdk21 {
    $Candidates = [System.Collections.Generic.List[string]]::new()

    if ($env:JAVA_HOME) {
        $Candidates.Add($env:JAVA_HOME)
    }

    $PathJava = Get-Command java.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PathJava -and $PathJava.Source) {
        $Candidates.Add($PathJava.Source)
    }

    $PathJavac = Get-Command javac.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($PathJavac -and $PathJavac.Source) {
        $Candidates.Add($PathJavac.Source)
    }

    $Candidates.Add($JdkInstallRoot)

    $SearchRoots = @(
        (Join-Path $env:ProgramFiles "Eclipse Adoptium"),
        (Join-Path $env:ProgramFiles "Java"),
        (Join-Path $env:LOCALAPPDATA "Programs\Eclipse Adoptium"),
        (Join-Path $env:APPDATA "PrismLauncher\java"),
        (Join-Path $env:APPDATA "PrismLauncher\runtime"),
        (Join-Path $env:LOCALAPPDATA "Programs\PrismLauncher\runtime")
    )

    foreach ($Root in $SearchRoots) {
        if (Test-Path -LiteralPath $Root -PathType Container) {
            $Candidates.Add($Root)
            Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { $Candidates.Add($_.FullName) }
        }
    }

    $Seen = @{}
    foreach ($Candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) {
            continue
        }
        $Normalized = [Environment]::ExpandEnvironmentVariables($Candidate.Trim().Trim('"'))
        if ($Seen.ContainsKey($Normalized)) {
            continue
        }
        $Seen[$Normalized] = $true

        $Jdk = Get-Jdk21 $Normalized
        if ($Jdk) {
            return $Jdk
        }
    }

    return $null
}

function Install-Temurin21 {
    New-Item -ItemType Directory -Force -Path $ToolsRoot, $DownloadRoot | Out-Null

    $Architecture = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "aarch64" } else { "x64" }
    $ApiUrl = "https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=$Architecture&image_type=jdk&os=windows&vendor=eclipse"

    Write-Info "No complete JDK 21 was found."
    Write-Info "A project-local Eclipse Temurin JDK 21 will be installed under .tools."
    Write-Info "Existing system Java installations and environment variables will not be changed."

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $Assets = Invoke-RestMethod -Uri $ApiUrl -Headers @{ "User-Agent" = "Cruor-Sable-Compat-Builder" }
    $Asset = $Assets | Select-Object -First 1

    if (!$Asset -or !$Asset.binary -or !$Asset.binary.package -or
        !$Asset.binary.package.link -or !$Asset.binary.package.checksum) {
        throw "Adoptium did not return a JDK archive and SHA-256 checksum."
    }

    $Package = $Asset.binary.package
    $ArchivePath = Join-Path $DownloadRoot "temurin-21-windows.zip"
    $ExtractPath = Join-Path $DownloadRoot ("temurin-21-extracted-" + [guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Force -Path $ExtractPath | Out-Null
    Write-Info "Downloading the official Temurin 21 archive..."
    Invoke-WebRequest -Uri $Package.link -OutFile $ArchivePath -UseBasicParsing -Headers @{
        "User-Agent" = "Cruor-Sable-Compat-Builder"
    } | Out-Null

    $ActualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $ExpectedHash = ([string]$Package.checksum).ToLowerInvariant()
    if ($ActualHash -ne $ExpectedHash) {
        throw "JDK SHA-256 mismatch. The downloaded archive was rejected."
    }
    Write-Ok "JDK archive SHA-256 verified."

    Write-Info "Extracting the verified archive..."
    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractPath -Force

    $JavaFile = Get-ChildItem -LiteralPath $ExtractPath -Filter "java.exe" -File -Recurse |
        Where-Object { $_.Directory.Name -ieq "bin" } |
        Select-Object -First 1
    if (!$JavaFile) {
        throw "The verified archive does not contain bin\java.exe."
    }

    $ExtractedHome = Split-Path (Split-Path $JavaFile.FullName -Parent) -Parent
    if (!(Get-Jdk21 $ExtractedHome)) {
        throw "The downloaded archive did not contain a complete JDK 21."
    }

    if (Test-Path -LiteralPath $JdkInstallRoot) {
        $BackupPath = "$JdkInstallRoot.previous-$(Get-Date -Format 'yyyyMMddHHmmss')"
        Move-Item -LiteralPath $JdkInstallRoot -Destination $BackupPath
        Write-Warn "Previous project-local JDK preserved at $BackupPath"
    }

    Move-Item -LiteralPath $ExtractedHome -Destination $JdkInstallRoot
    Remove-Item -LiteralPath $ExtractPath -Recurse -Force
    Remove-Item -LiteralPath $ArchivePath -Force

    $Installed = Get-Jdk21 $JdkInstallRoot
    if (!$Installed) {
        throw "JDK 21 was installed, but its final validation failed."
    }

    return $Installed
}

Push-Location $ProjectRoot
try {
    Write-Host ""
    Write-Host " Cruor Sable Compat automatic builder" -ForegroundColor White
    Write-Host " Minecraft 1.21.1 | NeoForge 21.1.x | Java 21" -ForegroundColor DarkGray
    Write-Host ""

    if (!(Test-Path -LiteralPath (Join-Path $ProjectRoot "gradlew.bat") -PathType Leaf) -or
        !(Test-Path -LiteralPath (Join-Path $ProjectRoot "gradle\wrapper\gradle-wrapper.jar") -PathType Leaf)) {
        throw "Gradle Wrapper files are missing. Clone or download the complete repository."
    }

    $Jdk = Find-Jdk21
    if (!$Jdk) {
        $Jdk = Install-Temurin21
    }

    $env:JAVA_HOME = $Jdk.Home
    $env:Path = (Join-Path $Jdk.Home "bin") + ";" + $env:Path
    Write-Ok "Using JDK 21: $($Jdk.Home)"
    Write-Host $Jdk.Version

    if (!$GradleArgs -or $GradleArgs.Count -eq 0) {
        $GradleArgs = @("build", "--build-cache", "--parallel")
    }
    elseif ($GradleArgs -notcontains "--build-cache") {
        $GradleArgs = @($GradleArgs) + @("--build-cache")
    }

    Write-Info "Starting the pinned Gradle Wrapper..."
    & (Join-Path $ProjectRoot "gradlew.bat") @GradleArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Gradle returned exit code $LASTEXITCODE."
    }

    $JarDirectory = Join-Path $ProjectRoot "build\libs"
    $Jar = Get-ChildItem -LiteralPath $JarDirectory -Filter "*.jar" -File |
        Where-Object { $_.Name -notlike "*-sources.jar" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (!$Jar) {
        throw "Gradle completed, but no distributable mod JAR was found in build\libs."
    }

    Write-Host ""
    Write-Host " ==========================================" -ForegroundColor Green
    Write-Host " BUILD SUCCESSFUL" -ForegroundColor Green
    Write-Host " ==========================================" -ForegroundColor Green
    Write-Ok "Mod: $($Jar.FullName)"
    Write-Ok ("Size: {0:N2} MiB" -f ($Jar.Length / 1MB))
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "[BUILD ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "No system-wide Java installation or environment variables were changed." -ForegroundColor DarkGray
    exit 1
}
finally {
    Pop-Location
}
