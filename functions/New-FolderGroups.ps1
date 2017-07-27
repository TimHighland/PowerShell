function New-FolderGroups { 
    <# 
    .SYNOPSIS 
        Creates a new folder and associated Domain Local groups in Active Directory with respective NTFS permissions (Modify and ReadAndExecute).
    .DESCRIPTION 
        'New-FolderGroups' creates a new folder on a specified network location and subsequently creates separate Modify and Read-Only Domain Local Security groups in the Active Directory domain. 
        
        Group name prefixes and suffixes can be specified, or group names can be generated automatically.

    .CHANGELOG
        Date            Name            Version     Comments
        2017-07-26      Tim Hoogland    1.0         First version.
    .EXAMPLE 
        New-FolderGroups -Path "\\server.domain.com\new folder" -DomainLocalOrganizationalUnit "OU=DomainLocal,OU=Groups,OU=Domain.com,DC=Domain,DC=com" -AutoName

        This example creates the folder "new folder" on server.domain.com. Domain Local groups will be created in the Domain.com/Groups/DomainLocal OU. 
        
        The -AutoName switch toggles automatic group name generation.
    .PARAMETER Path
        Specifies the path to the folder that is to be created by the function.
    .PARAMETER DomainLocalGroupOrganizationalUnit
        
    .PARAMETER AutoName
        Switch that toggles automatically generated security group names.
    .PARAMETER IncludeGlobalGroups
    .PARAMETER NameBase
    .PARAMETER DomainLocalGroupPrefix
    .PARAMETER GlobalGroupPrefix
    .PARAMETER ModifyGroupSuffix
    .PARAMETER ReadOnlyGroupSuffix
    .PARAMETER ReadOnlyGroupSuffix
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$true,Position=0)]
        $Path,

        [parameter(Mandatory=$true,Position=1)]
        [Alias("DLGOU")]
        $DomainLocalGroupOrganizationalUnit,
        
        [parameter(Mandatory=$false)]
        [Alias("GGOU")]
        $GlobalGroupOrganizationalUnit,
        
        [parameter(Mandatory=$false)]
        [switch]$AutoName,
        
        [parameter(Mandatory=$false)]
        [switch]$IncludeGlobalGroups,
        
        [parameter(Mandatory=$false)]
        $NameBase = "",
        
        [parameter(Mandatory=$false)]
        [Alias("DLGPrefix")]
        $DomainLocalGroupPrefix = "DLG_",

        [parameter(Mandatory=$false)]
        [Alias("GGPrefix")]
        $GlobalGroupPrefix = "GG_",
        
        [parameter(Mandatory=$false)]
        [Alias("MGS")]
        $ModifyGroupSuffix = "_CH",
        
        [parameter(Mandatory=$false)]
        [Alias("RGS")]
        $ReadOnlyGroupSuffix = "_RO"
    )

    begin {
        $Path = $Path.TrimEnd("\")
        $DomainName = $env:USERDNSDOMAIN
        
        if ($Path.Contains(":")) {
            Write-Error -Message "Parameter 'Path' does not accept local paths. Please specify a UNC path."
            return
        }

        if (!(Test-Path $Path)) {
            Write-Error -Message "This folder does not exist: $Path"
            return
        }
        if (!$DomainLocalGroupOrganizationalUnit) {
            Write-Error "You must specify a Domain Local Group Organizational Unit."
            return
        }
        if ($DomainLocalGroupOrganizationalUnit) {
            try {
                Get-ADOrganizationalUnit $DomainLocalGroupOrganizationalUnit | Out-Null
            }
            catch {
                Write-Error -Message "Domain Local Group Organizational Unit not found."
                return
            }                
        }
        if ($IncludeGlobalGroups) {
            if (!$GlobalGroupOrganizationalUnit) {
                Write-Error "You must specify a Global Group Organizational Unit."
                return
            }
            else {
                try {
                    Get-ADOrganizationalUnit $GlobalGroupOrganizationalUnit | Out-Null
                }
                catch {
                    Write-Error -Message "Global Group Organizational Unit not found."
                    return
                }
            }
        }
        if ($AutoName) {
            $Split = $Path.Trim("\\").Replace(".$DomainName","") -split "\\"
            $i = $Split.Count - 1
            $Server = $Split[0]
            $Share = $Split[1]
            $Rest = $Split[2..$i]
            $Root = (Get-WmiObject -Class Win32_Share -ComputerName $Server | Where-Object { $_.Name -eq $Share }).Path
            $LocalPath = Join-Path -Path $Root -ChildPath ($Rest -join "\")
            $NameBase = ($Split[1..$i] -join "_").Replace("$","").Replace(" ","-")
        }

        try {
            $FolderAcl = Get-Acl $Path
        }
        catch {
            Write-Error -Message "Could not get ACL from folder."
            return
        }        

        $DlgModifyGroupName = $DomainLocalGroupPrefix + $NameBase.Replace(" ","-").TrimStart("_") + $ModifyGroupSuffix
        $DlgReadOnlyGroupName = $DomainLocalGroupPrefix + $NameBase.Replace(" ","-").TrimStart("_") + $ReadOnlyGroupSuffix

        $DMprops = @{
            GroupName           = $DlgModifyGroupName
            GroupScope          = "DomainLocal"
            GroupCategory       = "Security"
            OrganizationalUnit  = $DomainLocalGroupOrganizationalUnit
            Permissions         = "Modify"
        }
        $DRprops = @{
            GroupName           = $DlgReadOnlyGroupName
            GroupScope          = "DomainLocal"
            GroupCategory       = "Security"
            OrganizationalUnit  = $DomainLocalGroupOrganizationalUnit
            Permissions         = "ReadAndExecute"
        }

        if ($IncludeGlobalGroups) {
            $GgModifyGroupName   = $GlobalGroupPrefix + $NameBase.Replace(" ","-").TrimStart("_") + $ModifyGroupSuffix
            $GgReadOnlyGroupName = $GlobalGroupPrefix + $NameBase.Replace(" ","-").TrimStart("_") + $ReadOnlyGroupSuffix
            $DMprops.Members = $GgModifyGroupName
            $DRprops.Members = $GgReadOnlyGroupName
        }

        $GroupArray = @()
        $DMobj = New-Object -TypeName PSCustomObject -Property $DMprops
        $DRobj = New-Object -TypeName PSCustomObject -Property $DRprops
        
        $GroupArray += $DMobj
        $GroupArray += $DRobj

        if ($IncludeGlobalGroups) {
            $GMprops = @{
                GroupName           = $GgModifyGroupName
                GroupScope          = "Global"
                GroupCategory       = "Security"
                OrganizationalUnit  = $GlobalGroupOrganizationalUnit
                Permissions         = "Modify"
                Members             = ""
            }
            $GRprops = @{
                GroupName           = $GgReadOnlyGroupName
                GroupScope          = "Global"
                GroupCategory       = "Security"
                OrganizationalUnit  = $GlobalGroupOrganizationalUnit
                Permissions         = "ReadAndExecute"
                Members             = ""
            }    
            $GMobj = New-Object -TypeName PSCustomObject -Property $GMprops
            $GRobj = New-Object -TypeName PSCustomObject -Property $GRprops            
            $GroupArray += $GMobj
            $GroupArray += $GRobj
        }

        Write-Output "`n"
        Write-Output "Settings permissions for the following folder:"
        $Path
        Write-Output "`n"

        Write-Output "Current ACL:"
        $FolderAcl.Access | Select-Object IdentityReference,FileSystemRights
        Write-Output "`n"

        Write-Output "Creating the following groups:"
        $GroupArray | Select-Object GroupName,GroupScope,GroupCategory,Members,Permissions,OrganizationalUnit | Format-Table -AutoSize
        $Continue = $false
        while ($Continue -eq $false) {
            $Prompt = Read-Host "Continue? [Y/N]"
            switch ($Prompt) {
                y       { $Continue = $true }
                n       { Return }
                default {  }
            }
        }
    }
     process {
        if ($Continue -eq $true) {
            foreach ($grp in $GroupArray) {
                $GrpName = $grp.GroupName
                try {
                    New-ADGroup -Path $grp.OrganizationalUnit -Name $GrpName -GroupCategory $grp.GroupCategory -GroupScope $grp.GroupScope
                    Write-Output "Successfully created group '$GrpName'"
                }
                catch {
                    Write-Error -Message "FAILED: $GrpName not created."
                }
            }
            
            if ($IncludeGlobalGroups) {
                try {
                    Add-ADGroupMember -Identity $DlgModifyGroupName   -Members $GgModifyGroupName
                    Add-ADGroupMember -Identity $DlgReadOnlyGroupName -Members $GgReadOnlyGroupName
                }
                catch {
                    Write-Error "Unable to add Global Groups to Domain Local Groups."
                }            
            }
            
            $InheritanceFlag     = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
            $PropagationFlag     = [System.Security.AccessControl.PropagationFlags]::None
            $objType             = [System.Security.AccessControl.AccessControlType]::Allow
            $ModifyPermission    = "$DomainName\$DlgModifyGroupName","Modify",$InheritanceFlag,$PropagationFlag,$objType
            $ReadOnlyPermission  = "$DomainName\$DlgReadOnlyGroupName","ReadAndExecute",$InheritanceFlag,$PropagationFlag,$objType
            $ModifyAccessRule    = New-Object System.Security.AccessControl.FileSystemAccessRule $ModifyPermission
            $ReadOnlyAccessRule  = New-Object System.Security.AccessControl.FileSystemAccessRule $ReadOnlyPermission

            $GroupsExist = $false
            while ($GroupsExist -eq $false) {
                try {
                    $FolderAcl.SetAccessRule($ModifyAccessRule)
                    $FolderAcl.SetAccessRule($ReadOnlyAccessRule)
                    $GroupsExist = $true
                    Write-Output "Successfully created access rules"
                }
                catch {
                    Write-Output "Waiting"
                    Start-Sleep 1
                }
            }
            try {
                Set-Acl $Path $FolderAcl
                Write-Output "Successfully updated ACL for folder '$Path'"
            }
            catch {
                Write-Error -Message $Error[0]
                return
            }
        }

    }

    end {
  
    }
}
