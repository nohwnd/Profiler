function Get-Avocado {
    Get-EmojiInternal -Emoji avocado
}

function Get-Unicorn {
    Get-EmojiInternal -Emoji unicorn
}

function Get-EmojiInternal ($Emoji) {
    $ProgressPreference = 'SilentlyContinue'

    $r = Invoke-WebRequest -Method GET -Uri "https://emojipedia.org/$($Emoji.ToLowerInvariant())/" -UseBasicParsing 
    if (200 -ne $r.StatusCode) { 
        throw "Error"
    }

    $match = $r.Content.ToString() -split "`n" | Select-String '<h1><span\s+class="emoji">(.*)</span>'
    $match.Matches.Groups[-1].Value
}

Export-ModuleMember -Function Get-Avocado, Get-Unicorn