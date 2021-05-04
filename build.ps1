param ([Switch]$Clean)

$destination =  "$PSScriptRoot/Profiler/bin/net452"
if (-not $Clean -and (Test-Path "$destination/Profiler.dll")) { 
    Write-Host -ForegroundColor Yellow "Already built, skipping. Use -Clean to force rebuild."
    return
}

dotnet build "$PSScriptRoot/csharp/Profiler.sln"
if (0 -ne $LASTEXITCODE) { 
    throw "Build failed"
}

$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/net452"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll -Verbose
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb -Verbose

$destination =  "$PSScriptRoot/Profiler/bin/netstandard2.0"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/netstandard2.0"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll -Verbose
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb -Verbose

$destination =  "$PSScriptRoot/Profiler/bin/net451"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/net451"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll -Verbose
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb -Verbose

