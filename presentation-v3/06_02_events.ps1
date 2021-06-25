$trace = Trace-Script {
    $words = "Hello", "this", "is", "dog"

    foreach ($word in $words) {
        "text: $word"
    }
} 

$trace.Events | Format-Table TimeStamp, @{ n = "File"; e = { $_.Path | Split-Path -Leaf } }, Line, Text

