$trace = Trace-Script {
    $words = "Hello", "this", "is", "dog"

    foreach ($word in $words) {
        "text: $word"
    }
}

$trace.Events | Format-Table Index, Text