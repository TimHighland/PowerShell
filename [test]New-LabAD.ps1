function New-LabAD ($DomainName,$DomainExtension) 
{
    $FullName = $DomainName + "." + $DomainExtension
    $FirstUserPassword = Read-Host "Password:" -AsSecureString
    
    function New-ADOU ($OUName)
    {
        $ObjectParameters = @{
            Path = "OU=$FullName,DC=$DomainName,DC=$DomainExtension"
            Name = $OUName
            ProtectedFromAccidentalDeletion = $false
        }
        New-ADOrganizationalUnit @ObjectParameters
    }

    $NewADOU1 = @{
        Name = $FullName
        ProtectedFromAccidentalDeletion = $false
    }   
    $NewADOU2 = @{
        Path = "OU=$FullName,DC=$DomainName,DC=$DomainExtension"
        Name = 'Users'
        ProtectedFromAccidentalDeletion = $false
    }
    $NewADOU3 = @{
        Path = "OU=$FullName,DC=$DomainName,DC=$DomainExtension"
        Name = 'Computers'
        ProtectedFromAccidentalDeletion = $false
    }
    $NewADOU4

    New-ADOrganizationalUnit @NewADOU1
    New-ADOrganizationalUnit @NewADOU2
    New-ADOrganizationalUnit @NewADOU3

    New-ADOrganizationalUnit `
        -Path "OU=$FullName,DC=$DomainName,DC=$DomainExtension" `
        -Name 'Servers' `
        -ProtectedFromAccidentalDeletion $false
    New-ADOrganizationalUnit `
        -Path "OU=$FullName,DC=$DomainName,DC=$DomainExtension" `
        -Name 'Groups' `
        -ProtectedFromAccidentalDeletion $false
    New-ADUser `
        -SamAccountName "t.hoogland" `
        -DisplayName "Tim Hoogland" `
        -Name "Tim" `
        -Surname "Hoogland" `
        -UserPrincipalName "t.hoogland" `
        -AccountPassword $FirstUserPassword `
        -Path "OU=Users,OU=$FullName,DC=$DomainName,DC=$DomainExtension" `
        -Enabled $true
    Add-AdGroupMember `
        -Identity "Domain Admins" `
        -Members "t.hoogland"
}