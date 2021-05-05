$ErrorActionPreference = "Stop"

dotnet build "$PSScriptRoot/csharp/Profiler.sln"
if (0 -ne $LASTEXITCODE) { 
    throw "Build failed"
}

Write-Host "Copying dlls"
$destination =  "$PSScriptRoot/Profiler/bin/net452"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/net452"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll 
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb 

$destination =  "$PSScriptRoot/Profiler/bin/netstandard2.0"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/netstandard2.0"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll 
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb 

$destination =  "$PSScriptRoot/Profiler/bin/net451"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/net451"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll 
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb 

