# Initialize variables
$FormatDate = Get-Date -UFormat "%Y%m%d_%H%M%S"
$LogPath = "$env:USERPROFILE\Desktop\$FormatDate`_New-FolderGroupPermissions.log"
$FolderName = Read-Host -Prompt "Folder name"
$FolderPath = Read-Host -Prompt "Parent folder FQDN"
$CsvPath = Read-Host -Prompt "Path to users CSV"
$DomainExtension = (Read-Host -Prompt "Domain name (e.g. 'domain.com')").ToUpper()
$FolderFQDN = $FolderPath + "\" + $FolderName
$SplitFP = $FolderPath.ToUpper().Replace(".$DomainExtension","").Replace("\\","").Replace("_","").Replace("$","").Split("\")
$Dname = "DL"
$Gname = "GL"
$Dou = Read-Host -Prompt "Domain Local Group Organizational Unit"
$Gou = Read-Host -Prompt "Global Group Organizational Unit"

# Check FolderFQDN
if (Test-Path $FolderFQDN) {
    Write-Log -Path $LogPath -Level Error -Message "Folder already exists."
    return
}
if (!(Test-Path $FolderFQDN)) {
    Write-Log -Path $LogPath -Level Info -Message "Folder Path is available."
}


# Import CSV
$users = Import-Csv -Path $CsvPath -Delimiter ";"
$usersProperties = $users | Get-Member
if ($usersProperties.Name -notcontains "samAccountName" -or $usersProperties.Name -notcontains "Permissions") {
    Write-Log -Path $LogPath -Message "CSV is missing one or more columns. Make sure 'samAccountName' and 'Permissions' are present." -Level Error
}
$notExist = @()
foreach ($u in $users) {
    try { 
        Get-ADUser $u.samAccountName -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
        $uSam = $u.samAccountName
        $notExist += $uSam
    }
}
if ((!$notExist) -eq $false) {
    Write-Log -Path $LogPath -Message "Found non-existent users in CSV" -Level Error
    foreach ($u in $notExist) {
        Write-Log -Path $LogPath -Message "Account '$u' does not exist" -Level Info
    }
    return
}
else {
    Write-Log -Path $LogPath -Message "CSV information is correct." -Level Info
}


# Create array of groups
for ($i=0;$i -le $SplitFP.Count-1; $i++) {
    $str = "_" + $SplitFP[$i]
    $Dname += $str
}

for ($i=0;$i -le $SplitFP.Count-1; $i++) {
    $str = "_" + $SplitFP[$i]
    $Gname += $str
}

$DCname = $Dname + "_" + $FolderName.Replace(" ","-") + "_CH"
$DRname = $Dname + "_" + $FolderName.Replace(" ","-") + "_RO"
$GCname = $Gname + "_" + $FolderName.Replace(" ","-") + "_CH"
$GRname = $Gname + "_" + $FolderName.Replace(" ","-") + "_RO"

$DCprops = @{
    GroupName           = $DCname
    GroupScope          = "DomainLocal"
    GroupCategory       = "Security"
    OrganizationalUnit  = $Dou
    Permissions         = "Change"
    Members             = $GCname
}
$DRprops = @{
    GroupName           = $DRname
    GroupScope          = "DomainLocal"
    GroupCategory       = "Security"
    OrganizationalUnit  = $Dou
    Permissions         = "Read-only"
    Members             = $GRname
}
$GCprops = @{
    GroupName           = $GCname
    GroupScope          = "Global"
    GroupCategory       = "Security"
    OrganizationalUnit  = $Gou
    Permissions         = ""
    Members             = $users.Where({$_.Permissions -eq "Change"}).samAccountName
}
$GRprops = @{
    GroupName           = $GRname
    GroupScope          = "Global"
    GroupCategory       = "Security"
    OrganizationalUnit  = $Gou
    Permissions         = ""
    Members             = $users.Where({$_.Permissions -eq "Read"}).samAccountName
}

$GroupArray = @()
$DCobj = New-Object -TypeName PSCustomObject -Property $DCprops
$DRobj = New-Object -TypeName PSCustomObject -Property $DRprops
$GCobj = New-Object -TypeName PSCustomObject -Property $GCprops
$GRobj = New-Object -TypeName PSCustomObject -Property $GRprops
$GroupArray += $DCobj
$GroupArray += $DRobj
$GroupArray += $GCobj
$GroupArray += $GRobj


# prompt user to confirm
Start-Sleep 1
Clear-Host
Write-Host -BackgroundColor Black -ForegroundColor Yellow "PLEASE CHECK THE FOLLOWING INFORMATION BEFORE PROCEEDING:"
Write-Host "`n"
Write-Host -BackgroundColor White -ForegroundColor Black "Creating folder:"
Write-Host $FolderFQDN
Write-Host "`n"

Write-Host -BackgroundColor White -ForegroundColor Black "Creating groups:"
$GroupArray | select GroupName,GroupScope,Members,Permissions | ft -AutoSize
#Write-Host "`n"

$Exist = @()
foreach ($g in $GroupArray) {
    $name = $g.GroupName
    if (Get-ADGroup -SearchBase $g.OrganizationalUnit -Filter {Name -eq $name}) {
        $Exist += $name
    }
}
if ($Exist) {
    Write-Host -BackgroundColor Black -ForegroundColor Red "The following groups already exist. Please check:"
    $Exist
    Write-Host "`n"
}


Write-Host -BackgroundColor White -ForegroundColor Black "Setting user permissions:"
$users | Sort-Object Permissions | ft -AutoSize
Write-Host "`n"

Start-Sleep 0.1
$Continue = $false
while ($Continue -eq $false) {
    $Prompt = Read-Host "Continue? [Y/N]"
    switch ($Prompt) {
        y       { $Continue = $true }
        n       { Return }
        default {  }
    }
}


# Create groups
Write-Host -BackgroundColor Cyan -ForegroundColor White "Let's go!"

foreach ($grp in $GroupArray) {
    $GrpName = $grp.GroupName
    try {
        New-ADGroup -Path $grp.OrganizationalUnit -Name $GrpName -GroupCategory $grp.GroupCategory -GroupScope $grp.GroupScope
        Write-Log -Path $LogPath -Level Info -Message "SUCCESS: $GrpName created"
    }
    catch {
        Write-Log -Path $LogPath -Level Error -Message "FAILED: $GrpName not created"
    }
}


# Set group members
foreach ($grp in $GroupArray) {
    foreach ($member in $grp.Members) {
        $GrpName = $grp.GroupName
        try {
            Add-ADGroupMember -Identity $GrpName -Members $member
            Write-Log -Path $LogPath -Level Info -Message "SUCCESS: $member added to $GrpName"
        }
        catch {
            Write-Log -Path $LogPath -Level Error -Message "FAILED: $member NOT added to $GrpName"
        }
    }
}


# Create folder
try {
    New-Item -ItemType Directory $FolderFQDN
    Write-Log -Path $LogPath -Level Info -Message "SUCCESS: created folder '$FolderFQDN'"
}
catch {
    Write-Log -Path $LogPath -Level Error -Message "FAILED: unable to create folder '$FolderFQDN'"
}


# Set NTFS permissions

try {
    $FolderAcl = Get-Acl $FolderFQDN
}
catch {
    Write-Log -Path $LogPath -Level Error -Message "Could not get ACL from folder."
    return
}

$InheritanceFlag     = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$PropagationFlag     = [System.Security.AccessControl.PropagationFlags]::None
$objType             = [System.Security.AccessControl.AccessControlType]::Allow
$ChangePermission    = "$DomainExtension\$DCname","Modify",$InheritanceFlag,$PropagationFlag,$objType
$ReadPermission      = "$DomainExtension\$DRname","ReadAndExecute",$InheritanceFlag,$PropagationFlag,$objType
$ChangeAccessRule    = New-Object System.Security.AccessControl.FileSystemAccessRule $ChangePermission
$ReadAccessRule      = New-Object System.Security.AccessControl.FileSystemAccessRule $ReadPermission

$GroupsExist = $false
while ($GroupsExist -eq $false) {
    try {
        $FolderAcl.SetAccessRule($ChangeAccessRule)
        $FolderAcl.SetAccessRule($ReadAccessRule)
        $GroupsExist = $true
        Write-Log -Path $LogPath -Level Info -Message "Access rules created"
    }
    catch {
        Start-Sleep 1
    }
}
try {
    Set-Acl $FolderFQDN $FolderAcl
    Write-Log -Path $LogPath -Level Info -Message "SUCCESS: updated ACL for folder '$FolderFQDN'"
}
catch {
    Write-Log -Path $LogPath -Level Error -Message $Error[0]
    return
}