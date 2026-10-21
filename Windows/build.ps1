param([ValidateSet('win-x64', 'win-arm64')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$artifacts = Join-Path $PSScriptRoot 'artifacts'
$publish = Join-Path $artifacts "UsageBar-$Runtime"
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

# Format conversion only: embed the existing 256px app PNG in a Windows ICO.
# No regenerated artwork or third-party icon converter is required.
$png = [IO.File]::ReadAllBytes((Join-Path $root 'Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png'))
$iconPath = Join-Path $artifacts 'UsageBar.ico'
$icon = [IO.BinaryWriter]::new([IO.File]::Create($iconPath))
try {
    $icon.Write([UInt16]0); $icon.Write([UInt16]1); $icon.Write([UInt16]1)
    $icon.Write([byte]0); $icon.Write([byte]0); $icon.Write([byte]0); $icon.Write([byte]0)
    $icon.Write([UInt16]1); $icon.Write([UInt16]32)
    $icon.Write([UInt32]$png.Length); $icon.Write([UInt32]22); $icon.Write($png)
} finally { $icon.Dispose() }

dotnet publish (Join-Path $PSScriptRoot 'UsageBar.Windows/UsageBar.Windows.csproj') `
    -c Release -r $Runtime --self-contained true -o $publish `
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:PublishTrimmed=false -p:DebugType=None -p:ApplicationIcon=$iconPath
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed' }
Copy-Item (Join-Path $PSScriptRoot 'README.md') (Join-Path $publish 'README.md')
$archive = Join-Path $artifacts "UsageBar-$Runtime-preview.zip"
Compress-Archive -Path (Join-Path $publish '*') -DestinationPath $archive -Force
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archive.sha256", "$hash  $([IO.Path]::GetFileName($archive))`n")
Write-Output $archive
