function New-IndexArray {
    [CmdletBinding()]
    param(
        $CsvPath,`
        $Delimiter,`
        $Index
    )

    $Csv = Import-Csv -Path $CsvPath -Delimiter $Delimiter
    $Array = @()
    
    foreach ($i in $Csv) {
        $Category = $i.$Index
        $Props = @{
            Category = $Category
            Count = $Csv.Where({$_.$Index -eq $Category}).Count
        }
        $Object = New-Object -TypeName PSCustomObject -Property $Props
        if ($Array.Category -notcontains $Object.Category) {
            $Array += $Object
        }
    }
    $Array | Select-Object Category,Count
}

