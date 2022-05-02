param (
    [ValidateSet("Debug", "Release")]
    $Configuration = "Release"
)
$ErrorActionPreference = "Stop"

$sln = "$PSScriptRoot/csharp/Profiler.sln"

Write-Host "Publish and copy dlls"
$frameworks = "net452", "netstandard2.0"
foreach ($framework in $frameworks) {
    dotnet publish $sln --framework $framework --configuration $Configuration

    if (0 -ne $LASTEXITCODE) { 
        throw "Publish failed"
    }

    $destination =  "$PSScriptRoot/Profiler/bin/$framework"
    $sourceDir = "$PSScriptRoot/csharp/Profiler/bin/$Configuration/$framework/publish"
    New-Item $destination -ItemType Directory -Force | Out-Null
    Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll
    Copy-Item -Destination $destination -Path $sourceDir/Newtonsoft.Json.dll
}
