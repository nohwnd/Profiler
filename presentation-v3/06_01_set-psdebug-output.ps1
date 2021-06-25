Set-PSDebug -Trace 1
$words = "Hello", "this", "is", "dog"

foreach ($word in $words) {
    "text: $word"
}

Set-PSDebug -Off
