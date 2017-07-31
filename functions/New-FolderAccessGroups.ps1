function New-FolderAccessGroups { 
    <# 
    .SYNOPSIS 
        Creates Domain Local groups and sets Modify and ReadAndExecute permissions to a specified folder.
    .DESCRIPTION 
        New-FolderAccessGroups takes a DirectoryInfo-object as pipeline input and creates associated Domain Local groups in Active Directory with respective NTFS permissions (Modify and ReadAndExecute).
        
        Group name prefixes and suffixes can be specified, or group names can be generated automatically.
        
        Can also create associated Global groups as members of the respective Domain Local groups.
    .CHANGELOG
        Date            Name            Version     Comments
        2017-07-26      Tim Hoogland    1.0         First version.
        2017-07-27      Tim Hoogland    1.1         Function no longer creates folders. 'Set-Acl' is now executed remotely.
    .EXAMPLE 
        Get-Item -Path "\\server.domain.com\new folder" | New-FolderAccessGroups -DomainLocalOrganizationalUnit "OU=DomainLocal,OU=Groups,OU=Domain.com,DC=Domain,DC=com" -AutoName

        This example creates the folder "new folder" on server.domain.com. 
        
        Domain Local groups will be created in the Domain.com/Groups/DomainLocal OU. Group names are automatically generated.
    .PARAMETER Folder
        Specifies the path to the folder that is to be created by the function.
    .PARAMETER DomainLocalGroupOrganizationalUnit
        Specifies the Organizational Unit in which to create Domain Local security groups.
    .PARAMETER AutoName
        Switch that toggles automatically generated security group names.
    .PARAMETER IncludeGlobalGroups
        Switch that toggles the creation of Global security groups.
    .PARAMETER NameBase
        Specifies the base of the name for the created security groups.
    .PARAMETER DomainLocalGroupPrefix
        Specifies the prefix for the created Domain Local security groups.
    .PARAMETER GlobalGroupPrefix
        Specifies the prefix for the created Global security groups.
    .PARAMETER ModifyGroupSuffix
        Specifies the suffix for the created Modify groups.
    .PARAMETER ReadOnlyGroupSuffix
        Specifies the suffix for the created ReadOnly groups.
    #>
    [CmdletBinding()]
    param(
        [parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipeline=$true)
        ]
        $Folder,

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
        $DomainName = $env:USERDNSDOMAIN
        $FolderFullName = $Folder.FullName

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
            $Split = $FolderFullName.Trim("\\").Replace(".$DomainName","") -split "\\"
            $i = $Split.Count - 1
            $Server = $Split[0]
            $Share = $Split[1]
            $Rest = $Split[2..$i]
            $Root = (Get-WmiObject -Class Win32_Share -ComputerName $Server | Where-Object { $_.Name -eq $Share }).Path
            $LocalPath = Join-Path -Path $Root -ChildPath ($Rest -join "\")
            $NameBase = ($Split[1..$i] -join "_").Replace("$","").Replace(" ","-")
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
        if (!$FolderExists) {
            Write-Output "`n"
            Write-Output "The following folder does not exist and will be created:"
            $FolderFullName
            Write-Output "`n"
        }        
        elseif ($FolderExists = $true) {
            Write-Output "`n"
            Write-Output "Settings permissions for the following folder:"
            $FolderFullName
            Write-Output "`n"

            Write-Output "Current ACL:"
            $FolderAcl.Access | Select-Object IdentityReference,FileSystemRights
            Write-Output "`n"            
        }


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

            $FolderAcl = $Folder.GetAccessControl()
            $FolderAcl.SetAccessRule($ModifyAccessRule)
            $FolderAcl.SetAccessRule($ReadOnlyAccessRule)            

            try {
                if ($Server -eq $env:COMPUTERNAME) {
                    Set-Acl -Path $FolderFullName -AclObject $FolderAcl
                }
                else {
                    Invoke-Command -ComputerName $Server -ScriptBlock {
                        param(
                            $Path,
                            $NewAcl
                        )
                        Set-Acl -Path $Path -AclObject $NewAcl
                    } -ArgumentList $LocalPath,$FolderAcl                    
                }


                Write-Output "Successfully updated ACL for folder '$FolderFullName'"
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
