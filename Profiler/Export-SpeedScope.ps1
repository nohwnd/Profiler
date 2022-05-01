function Export-SpeedScope {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ExportTrace")]
        $Trace,
        [Alias("ExportPath")]
        [string] $Path = '.'
    )

    process {
        Write-Host -ForegroundColor Magenta "Exporting report into speedscope format." -NoNewline
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        $finalPath, $finalName = if (Test-Path $fullPath) {
            $item = Get-Item $fullPath -Force
            if ($item.PSIsContainer) {
                # we are given an existing directory, grab the next available default name
                Get-NextName -Path $item.FullName
            }
            else {
                # we are given an existing file, grab the name so we can check if it has template
                Get-NextName -Path $item.Directory -Name $item.Name
            }
        }
        else {
            if ([IO.Path]::EndsInDirectorySeparator($fullPath)) {
                # the path ends in \ or / which means we are given a directory, get the next name
                Get-NextName -Path $fullPath
            }
            else {
                # we are given a file, it might have an extension or not
                Get-NextName -Path (Split-Path $fullPath) -Name (Split-Path -Leaf $fullPath)
            }
        }

        $exporter = "$($ExecutionContext.SessionState.Module.Name)@$($ExecutionContext.SessionState.Module.Version)"
        $destination = [Profiler.SpeedScope.SpeedScope]::Export($exporter, $Trace, $finalPath, $finalName)
        Write-TimeAndRestart $sw
        Write-Host -ForegroundColor Cyan "Exported for https://speedscope.app/, to: $destination"
    }
}

function Get-NextName {
    param(
        [Parameter(Mandatory)]
        [string] $Path,
        [string] $Name = 'profiler_<id>.speedscope.json'
    )

    $Name = if ($Name -like "*.speedscope.json") { $Name } else { "$Name.speedscope.json" }
    $idTemplate = '<id>'
    $hasIdTemplate = $Name -like "*$idTemplate*"

    if (-not $hasIdTemplate) {
        return $Path, $Name
    }

    for ($id = 0; $id -le 9999; $id++) {
        $candidate = $Name -replace $idTemplate, $id.ToString("d4")
        if (-not (Test-Path -Path (Join-Path $Path $candidate))) {
            return $Path, $candidate
        }
    }

    throw "Could not find next name for $Name, last name candidate: '$candidate'"
}

# This function is internal only for testing
function Convert-SpeedScope {
    param(
        [Parameter(Mandatory)]
        $Name,
        $Events
    )

    
}
