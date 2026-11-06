<#
.SYNOPSIS
    Builds WaveSin.aex for After Effects (Windows).

.DESCRIPTION
    Locates Visual Studio, initialises its C++ environment (needed for the PiPL
    custom build step), then builds Win/Skeleton.sln.

    Environment / parameters:
      -AESdkRoot        Folder that contains Headers/, Resources/ and Util/.
                        Defaults to ..\..\AfterEffectsSDK_26.5_win\Examples when
                        present, otherwise the historical ..\..\.. layout.
      -PluginBuildDir   Folder the .aex is written to. Defaults to <repo>\build.
      -Toolset          v143 (VS2022) or v145 (VS2026). Auto-detected by default.

.EXAMPLE
    .\build.ps1
    .\build.ps1 -Configuration Release -PluginBuildDir "C:\Program Files\Adobe\Adobe After Effects 2026\Support Files\Plug-ins"
#>
[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [ValidateSet('x64', 'Win32')]
    [string]$Platform = 'x64',

    [string]$AESdkRoot = $env:AE_SDK_ROOT,

    [string]$PluginBuildDir = $env:AE_PLUGIN_BUILD_DIR,

    [string]$Toolset = $env:AE_PLUGIN_TOOLSET
)

$ErrorActionPreference = 'Stop'

$winDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $winDir
$solution = Join-Path $winDir 'Skeleton.sln'

# ---- Visual Studio ---------------------------------------------------------
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path $vswhere)) {
    throw 'vswhere.exe not found. Install Visual Studio 2022 or newer with the Desktop development with C++ workload.'
}

$vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsPath) {
    throw 'No Visual Studio installation with the MSVC x86/x64 tools was found.'
}

$vcvars = if ($Platform -eq 'x64') {
    Join-Path $vsPath 'VC\Auxiliary\Build\vcvars64.bat'
} else {
    Join-Path $vsPath 'VC\Auxiliary\Build\vcvars32.bat'
}
$msbuild = Join-Path $vsPath 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path $vcvars)) { throw "vcvars not found: $vcvars" }
if (-not (Test-Path $msbuild)) { throw "MSBuild not found: $msbuild" }

# ---- Toolset auto-detection ------------------------------------------------
if (-not $Toolset) {
    $msvc = Get-ChildItem (Join-Path $vsPath 'VC\Tools\MSVC') -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        Select-Object -First 1
    if ($msvc) {
        $version = [version]$msvc.Name
        if ($version.Major -eq 14 -and $version.Minor -ge 50) {
            $Toolset = 'v145'   # VS2026
        } elseif ($version.Major -eq 14 -and $version.Minor -ge 40) {
            $Toolset = 'v143'   # VS2022
        }
    }
    if (-not $Toolset) { $Toolset = 'v143' }
}

# ---- SDK / output defaults -------------------------------------------------
if (-not $AESdkRoot) {
    $candidate = Join-Path $repoRoot '..\AfterEffectsSDK_26.5_win\Examples'
    if (Test-Path (Join-Path $candidate 'Headers\AE_Effect.h')) {
        $AESdkRoot = $candidate
    }
}
if (-not $PluginBuildDir) { $PluginBuildDir = Join-Path $repoRoot 'build' }

# ---- Build -----------------------------------------------------------------
$buildArgs = @(
    "`"$solution`""
    '/m'
    '/nologo'
    '/v:minimal'
    "/p:Configuration=$Configuration"
    "/p:Platform=$Platform"
    "/p:AE_PLUGIN_TOOLSET=$Toolset"
)
if ($AESdkRoot) { $buildArgs += "/p:AE_SDK_ROOT=`"$AESdkRoot`"" }
if ($PluginBuildDir) { $buildArgs += "/p:AE_PLUGIN_BUILD_DIR=`"$PluginBuildDir`"" }

Write-Host "Visual Studio : $vsPath"
Write-Host "Toolset       : $Toolset"
if ($AESdkRoot) { Write-Host "AE SDK        : $AESdkRoot" }
Write-Host "Output        : $PluginBuildDir"
Write-Host ""

$command = "call `"$vcvars`" >nul && `"$msbuild`" $($buildArgs -join ' ')"
& cmd.exe /c $command
if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE."
}

$aex = Join-Path $PluginBuildDir 'WaveSin.aex'
if (-not (Test-Path $aex)) { throw "Build reported success but $aex was not produced." }

Write-Host ""
Write-Host "Built: $aex" -ForegroundColor Green
Get-Item $aex | Select-Object Name, Length, LastWriteTime | Format-List
