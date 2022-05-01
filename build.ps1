param (
    [ValidateSet("Debug", "Release")]
    $Configuration = "Release"
)
$ErrorActionPreference = "Stop"

$sln = "$PSScriptRoot/csharp/Profiler.sln"
dotnet build $sln --configuration $Configuration
if (0 -ne $LASTEXITCODE) { 
    throw "Build failed"
}

Write-Host "Publish and copy dlls"
foreach ($framework in @("net452", "netstandard2.0")) {
    dotnet publish $sln --framework $framework --configuration $Configuration
    $destination =  "$PSScriptRoot/Profiler/bin/$framework"
    $sourceDir = "$PSScriptRoot/csharp/Profiler/bin/$Configuration/$framework/publish"
    New-Item $destination -ItemType Directory -Force | Out-Null

    Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll
    Copy-Item -Destination $destination -Path $sourceDir/Newtonsoft.Json.dll
}

