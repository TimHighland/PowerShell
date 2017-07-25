function New-FolderGroups { 
    <# 
    .SYNOPSIS 
        Describe the function here.
    .DESCRIPTION 
        Describe the function in more detail.
    .CHANGELOG
        Keep track of version history and information here.
    .EXAMPLE 
        Give an example of how to use it.
    .PARAMETER paramName 
        Describe the function parameter here.
    #>
    [CmdletBinding()]
    param(
        [parameter(Mandatory=$false)]
        $DomainName = $env:USERDNSDOMAIN,

        [parameter(Mandatory=$true)]
        $FolderPath,
        
        [parameter(Mandatory=$false)]
        [switch]$AutoName,
        
        [parameter(Mandatory=$false)]
        [switch]$IncludeGlobalGroups,
        
        [parameter(Mandatory=$false)]
        $NameStub = "",
        
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
        $ReadOnlyGroupSuffix = "_RO",
        
        [parameter(Mandatory=$true)]
        [Alias("DLGOU")]
        $DomainLocalGroupOrganizationalUnit,
        
        [parameter(Mandatory=$false)]
        [Alias("GGOU")]
        $GlobalGroupOrganizationalUnit
    )

    begin {
        $FolderPath = $FolderPath.TrimEnd("\")
        if ($DomainName -ne $env:USERDNSDOMAIN) {
            Write-Warning "Submitted domain '$DomainName' is not equal to user DNS domain '$env:USERDNSDOMAIN'."
        }
        if (Test-Path $FolderPath) {
            Write-Error -Message "This folder already exists: $FolderPath"
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
            $NameStub = ""
            $SplitFP = $FolderPath.ToUpper().Replace(".$DomainName","").Replace("\\","").Replace("_","").Replace("$","").Split("\")
            for ($i=0;$i -le $SplitFP.Count-1; $i++) {
                $str = "_" + $SplitFP[$i]
                $NameStub += $str
            }
        }

        $DlgModifyGroupName = $DomainLocalGroupPrefix + $NameStub.Replace(" ","-").TrimStart("_") + $ModifyGroupSuffix
        $DlgReadOnlyGroupName = $DomainLocalGroupPrefix + $NameStub.Replace(" ","-").TrimStart("_") + $ReadOnlyGroupSuffix

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
            $GgModifyGroupName   = $GlobalGroupPrefix + $NameStub.Replace(" ","-").TrimStart("_") + $ModifyGroupSuffix
            $GgReadOnlyGroupName = $GlobalGroupPrefix + $NameStub.Replace(" ","-").TrimStart("_") + $ReadOnlyGroupSuffix
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

        Write-Host -BackgroundColor Black -ForegroundColor Cyan "Creating the following folder:"
        $FolderPath
        Write-Host "`n"

        Write-Host -BackgroundColor Black -ForegroundColor Cyan "Creating the following groups:"
        $GroupArray | Select-Object GroupName,GroupScope,GroupCategory,Members,Permissions,OrganizationalUnit | ft -AutoSize
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
                    Write-Host -BackgroundColor Black -ForegroundColor Green "Successfully created group '$GrpName'"
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

            try {
                New-Item -ItemType Directory $FolderPath
                Write-Host -BackgroundColor Black -ForegroundColor Green "Successfully created folder '$FolderPath'"
            }
            catch {
                Write-Error -Message "FAILED: unable to create folder '$FolderPath'"
            }
            
            try {
                $FolderAcl = Get-Acl $FolderPath
            }
            catch {
                Write-Error -Message "Could not get ACL from folder."
                return
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
                    Write-Host -BackgroundColor Black -ForegroundColor Green "Successfully created access rules"
                }
                catch {
                    Write-Host -BackgroundColor Black -ForegroundColor Yellow "Waiting"
                    Start-Sleep 1
                }
            }
            try {
                Set-Acl $FolderPath $FolderAcl
                Write-Host -BackgroundColor Black -ForegroundColor Green "Successfully updated ACL for folder '$FolderPath'"
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