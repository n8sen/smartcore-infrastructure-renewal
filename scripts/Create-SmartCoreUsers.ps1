<#
Creates AD users from CSV for ONE selected site only, placing them into Site > Users > Department OUs.

- Run on a machine with RSAT / ActiveDirectory module
- Run with an account that has permission to create OUs and users
- CSV headers must be:
    FirstName, LastName, Department, Division

CSV Division values expected:
    TEL AVIV
    NY

Mapped to site OUs:
    TEL AVIV -> Tel-Aviv
    NY       -> New-York

N8


 ███╗   ██╗███████╗
 ████╗  ██║██╔══██║
 ██╔██╗ ██║███████║  
 ██║╚██╗██║██╔══██║
 ██║ ╚████║███████║
 ╚═╝  ╚═══╝╚══════╝
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$CsvPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Tel-Aviv","New-York")]
    [string]$TargetSite
)

Import-Module ActiveDirectory -ErrorAction Stop



# CONFIG




$DomainFqdn = "smartcore.com"
$DomainDN   = "DC=smartcore,DC=com"
$Company    = "SmartCore"



# CSV Division -> AD Site OU mapping



$DivisionToSiteMap = @{
    "TEL AVIV" = "Tel-Aviv"
    "NY"       = "New-York"
}

$OfficeMap = @{
    "Tel-Aviv" = "Tel-Aviv"
    "New-York" = "New-York"
}

$AllowedDepartments = @(
    "CustomerService",
    "Finance",
    "HumanResources",
    "Logistics",
    "Management",
    "Operations",
    "Sales"
)

$LogFolder = Join-Path -Path $PSScriptRoot -ChildPath "Logs"
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogPath   = Join-Path -Path $LogFolder -ChildPath "UserCreation_$($TargetSite)_$TimeStamp.csv"



# FUNCTIONS



function Remove-InvalidUsernameChars {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputText
    )

    return (($InputText -replace '[^a-zA-Z0-9]', '').ToLower())
}

function Get-BaseUsername {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FirstName,

        [Parameter(Mandatory = $true)]
        [string]$LastName
    )

    $cleanFirst = Remove-InvalidUsernameChars -InputText $FirstName
    $cleanLast  = Remove-InvalidUsernameChars -InputText $LastName

    if ([string]::IsNullOrWhiteSpace($cleanFirst) -or [string]::IsNullOrWhiteSpace($cleanLast)) {
        throw "FirstName or LastName became empty after cleanup."
    }

    $lastPartLength = [Math]::Min(2, $cleanLast.Length)
    $baseUsername   = $cleanFirst + $cleanLast.Substring(0, $lastPartLength)

    return $baseUsername.ToLower()
}

function Get-UniqueSamAccountName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseSam
    )

    $candidate = $BaseSam
    $counter   = 1

    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $candidate = "$BaseSam$counter"
        $counter++
    }

    return $candidate
}

function Get-InitialPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FirstName,

        [Parameter(Mandatory = $true)]
        [string]$LastName
    )

    $firstInitial = ($FirstName.Trim()[0]).ToString().ToUpper()
    $lastInitial  = ($LastName.Trim()[0]).ToString().ToUpper()

    return "$firstInitial$lastInitial" + "sm2026!"
}

function Ensure-OUExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OuName,

        [Parameter(Mandatory = $true)]
        [string]$ParentDn
    )

    $OuDn = "OU=$OuName,$ParentDn"

    $existingOu = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$OuDn)" -ErrorAction SilentlyContinue
    if (-not $existingOu) {
        if ($PSCmdlet.ShouldProcess($OuDn, "Create OU")) {
            New-ADOrganizationalUnit `
                -Name $OuName `
                -Path $ParentDn `
                -ProtectedFromAccidentalDeletion $false `
                -ErrorAction Stop | Out-Null
        }
    }

    return $OuDn
}



# PREP OU STRUCTURE



$SiteOuDn  = Ensure-OUExists -OuName $TargetSite -ParentDn $DomainDN
$UsersOuDn = Ensure-OUExists -OuName "Users" -ParentDn $SiteOuDn

foreach ($dept in $AllowedDepartments) {
    Ensure-OUExists -OuName $dept -ParentDn $UsersOuDn | Out-Null
}



# IMPORT CSV



if (-not (Test-Path $CsvPath)) {
    throw "CSV file not found: $CsvPath"
}

$CsvData = Import-Csv -Path $CsvPath

$RequiredHeaders = @("FirstName","LastName","Department","Division")
$ActualHeaders   = @($CsvData | Select-Object -First 1 | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)

foreach ($header in $RequiredHeaders) {
    if ($header -notin $ActualHeaders) {
        throw "Missing required CSV column: $header"
    }
}

$FilteredUsers = $CsvData | Where-Object {
    $csvDivision = $_.Division.Trim().ToUpper()

    if ($DivisionToSiteMap.ContainsKey($csvDivision)) {
        $DivisionToSiteMap[$csvDivision] -eq $TargetSite
    }
    else {
        $false
    }
}

if (-not $FilteredUsers) {
    Write-Warning "No users found in CSV for site '$TargetSite'."
    return
}



# PROCESS USERS



$Results = foreach ($row in $FilteredUsers) {
    $FirstName   = ($row.FirstName  | ForEach-Object { $_.Trim() })
    $LastName    = ($row.LastName   | ForEach-Object { $_.Trim() })
    $Department  = ($row.Department | ForEach-Object { $_.Trim() })
    $CsvDivision = ($row.Division   | ForEach-Object { $_.Trim().ToUpper() })

    $MappedSite = $null
    if ($DivisionToSiteMap.ContainsKey($CsvDivision)) {
        $MappedSite = $DivisionToSiteMap[$CsvDivision]
    }

    $Result = [ordered]@{
        TimeStamp         = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        CsvDivision       = $CsvDivision
        MappedSite        = $MappedSite
        FirstName         = $FirstName
        LastName          = $LastName
        Department        = $Department
        SamAccountName    = $null
        UserPrincipalName = $null
        OUPath            = $null
        Status            = $null
        Message           = $null
    }

    try {
        if ([string]::IsNullOrWhiteSpace($FirstName) -or
            [string]::IsNullOrWhiteSpace($LastName)  -or
            [string]::IsNullOrWhiteSpace($Department) -or
            [string]::IsNullOrWhiteSpace($CsvDivision)) {
            throw "One or more required values are blank."
        }

        # CHANGED: validate mapped site instead of raw CSV Division text
        if (-not $MappedSite) {
            throw "Unknown Division value in CSV: '$CsvDivision'. Expected 'TEL AVIV' or 'NY'."
        }

        if ($MappedSite -ne $TargetSite) {
            throw "Row maps to site '$MappedSite', not selected site '$TargetSite'."
        }

        $DeptOuDn = Ensure-OUExists -OuName $Department -ParentDn $UsersOuDn

        $DisplayName = "$FirstName $LastName"
        $BaseSam     = Get-BaseUsername -FirstName $FirstName -LastName $LastName
        $Sam         = Get-UniqueSamAccountName -BaseSam $BaseSam
        $Upn         = "$Sam@$DomainFqdn"
        $Password    = Get-InitialPassword -FirstName $FirstName -LastName $LastName
        $SecurePwd   = ConvertTo-SecureString $Password -AsPlainText -Force
        $Description = "$Department user - $MappedSite"
        $Office      = $OfficeMap[$MappedSite]

        $Result.SamAccountName    = $Sam
        $Result.UserPrincipalName = $Upn
        $Result.OUPath            = $DeptOuDn

        if ($PSCmdlet.ShouldProcess($DisplayName, "Create AD user")) {
            New-ADUser `
                -Name $DisplayName `
                -GivenName $FirstName `
                -Surname $LastName `
                -DisplayName $DisplayName `
                -SamAccountName $Sam `
                -UserPrincipalName $Upn `
                -EmailAddress $Upn `
                -AccountPassword $SecurePwd `
                -Enabled $true `
                -ChangePasswordAtLogon $true `
                -PasswordNeverExpires $false `
                -Company $Company `
                -Department $Department `
                -Office $Office `
                -Description $Description `
                -Path $DeptOuDn `
                -ErrorAction Stop

            $Result.Status  = "Created"
            $Result.Message = "User created successfully. Initial password: $Password"
        }
        else {
            $Result.Status  = "Preview"
            $Result.Message = "User would be created. Initial password: $Password"
        }
    }
    catch {
        $Result.Status  = "Failed"
        $Result.Message = $_.Exception.Message
    }

    [pscustomobject]$Result
}



# OUTPUT + LOGGING



$Results | Export-Csv -Path $LogPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Finished processing site: $TargetSite" -ForegroundColor Cyan
Write-Host "Log written to: $LogPath" -ForegroundColor Cyan
Write-Host ""

$Results | Format-Table -AutoSize