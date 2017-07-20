function New-RandomString {
    [CmdletBinding()]
    param(
        [parameter(position=0,mandatory=$true)]
        [Alias("L")]
        $Length,`

        [parameter(mandatory=$false)]
        [Alias("ES")]
        [ValidateSet('LowerCase','UpperCase','Numerical','Special')]
        $ExcludeSet,`

        [parameter(mandatory=$false)]
        [Alias("EX")]
        $Exclude
    )

    if ($ExcludeSet -contains "LowerCase" -and $ExcludeSet -contains "UpperCase" -and $ExcludeSet -contains "Numerical" -and $ExcludeSet -contains "Special") {
        Write-Error "All characters have been excluded."
        break
    }
    switch ($ExcludeSet -contains "LowerCase") {
        True  { $LowerCaseString = "" }
        False { $LowerCaseString = "abcdefghijklmnopqrstuvwxyz" }
    }
    switch ($ExcludeSet -contains "UpperCase") {
        True  { $UpperCaseString = "" }
        False { $UpperCaseString = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
    }
    switch ($ExcludeSet -contains "Numerical") {
        True  { $NumericalString = "" }
        False { $NumericalString = "0123456789" }
    }
    switch ($ExcludeSet -contains "Special") {
        True  { $SpecialString = "" }
        False { $SpecialString = "~!@#$%^&*_-+=`|\(){}[]:;`"`'<>,.?/" }
    }
        
    $global:RandomString = ""
    $ComplexityString = $LowerCaseString + $UpperCaseString + $NumericalString + $SpecialString
    
    foreach ($c in $Exclude.ToCharArray()) {
        $ComplexityString = $ComplexityString.Replace($c.ToString(),"")
    }

    for ($i=1; $i -le $Length; $i++) {
        $RandomSelectNumber = Get-Random -Minimum 0 -Maximum $ComplexityString.Length
        $RandomChar = $ComplexityString[$RandomSelectNumber]
        [string]$global:RandomString += $RandomChar
    }
    Write-Output $RandomString
    Remove-Variable RandomString -Scope global
}