dotnet build "$PSScriptRoot/csharp/Profiler.sln"
if (0 -ne $LASTEXITCODE) { 
    throw "Build failed"
}

$destination =  "$PSScriptRoot/Profiler/bin/net452"
$sourceDir = "$PSScriptRoot/csharp/Profiler/bin/Debug/net452"
New-Item $destination -ItemType Directory -Force | Out-Null

Copy-Item -Destination $destination -Path $sourceDir/Profiler.dll -Verbose
Copy-Item -Destination $destination -Path $sourceDir/Profiler.pdb -Verbose

