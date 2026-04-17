<# 

Creates a new VM in HyprV

N8

███╗   ██╗███████╗
████╗  ██║██╔══██║
██╔██╗ ██║███████║  
██║╚██╗██║██╔══██║
██║ ╚████║███████║
╚═╝  ╚═══╝╚══════╝

#>



# CONFIG



$VMName              = "%vmname%"
$Generation          = 2
$StartupMemoryGB     = 4   # 2 / 4 / 6 / 8 / 12 / 16
$ProcessorCount      = 2   # 2 / 4 / 8 / 10

$VMPath              = "D:\$VMName"    # Adjust path
$VHDPath             = "D:\$VMName.vhdx"    # Adjust path
$VHDSizeGB           = 50   # 50 / 100 / 150 / 200 / 250

$VirtualSwitchName   = "vSwitch EXT-TA"
$ISOPath             = "D:\StudyBenchVM\Ms_Server2025.iso"   # To leave empty "" if not needed
$VlanId              = 0

$EnableDynamicMemory = $true
$MinimumMemoryGB     = 0.5
$MaximumMemoryGB     = 4

$AutoStartAction     = "Nothing"   # Nothing / StartIfRunning / Start
$AutoStopAction      = "ShutDown"   # ShutDown / Save / TurnOff

$CheckpointType              = "Production"   # Production / Standard / Disabled
$EnableAutomaticCheckpoints  = $false         # $true / $false
$DisableDataExchange         = $true          # $true / $false



# PRECHECKS


Write-Host "Starting VM creation..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
    throw "Hyper-V PowerShell module is not installed on this machine."
}

if (-not (Get-VMSwitch -Name $VirtualSwitchName -ErrorAction SilentlyContinue)) {
    throw "Virtual switch '$VirtualSwitchName' was not found."
}

if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
    throw "A VM named '$VMName' already exists."
}

if ($ISOPath -ne "" -and -not (Test-Path $ISOPath)) {
    throw "ISO file not found at: $ISOPath"
}



# FOLDER CREATION



$vmFolder = Split-Path $VMPath -Parent
$vhdFolder = Split-Path $VHDPath -Parent

if (-not (Test-Path $VMPath)) {
    New-Item -Path $VMPath -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $vhdFolder)) {
    New-Item -Path $vhdFolder -ItemType Directory -Force | Out-Null
}



# CONVERSIONS



$StartupMemoryBytes = $StartupMemoryGB * 1GB
$MinimumMemoryBytes = $MinimumMemoryGB * 1GB
$MaximumMemoryBytes = $MaximumMemoryGB * 1GB
$VHDSizeBytes       = $VHDSizeGB * 1GB



# CREATE VHD


Write-Host "Creating VHDX..." -ForegroundColor Yellow
New-VHD -Path $VHDPath -SizeBytes $VHDSizeBytes -Dynamic | Out-Null



# CREATE VM



Write-Host "Creating VM..." -ForegroundColor Yellow
New-VM `
    -Name $VMName `
    -Generation $Generation `
    -MemoryStartupBytes $StartupMemoryBytes `
    -VHDPath $VHDPath `
    -Path $VMPath `
    -SwitchName $VirtualSwitchName | Out-Null



# CPU



Write-Host "Configuring CPU..." -ForegroundColor Yellow
Set-VMProcessor -VMName $VMName -Count $ProcessorCount



# MEMORY



if ($EnableDynamicMemory) {
    Write-Host "Enabling Dynamic Memory..." -ForegroundColor Yellow
    Set-VMMemory `
        -VMName $VMName `
        -DynamicMemoryEnabled $true `
        -StartupBytes $StartupMemoryBytes `
        -MinimumBytes $MinimumMemoryBytes `
        -MaximumBytes $MaximumMemoryBytes
}
else {
    Write-Host "Using Static Memory..." -ForegroundColor Yellow
    Set-VMMemory `
        -VMName $VMName `
        -DynamicMemoryEnabled $false `
        -StartupBytes $StartupMemoryBytes
}



# AUTO START/STOP



Write-Host "Setting automatic start/stop actions..." -ForegroundColor Yellow
Set-VM -Name $VMName -AutomaticStartAction $AutoStartAction -AutomaticStopAction $AutoStopAction



# CHECKPOINT / INTEGRATION CONFIG



Write-Host "Configuring checkpoint and integration settings..." -ForegroundColor Yellow

Set-VM -Name $VMName -CheckpointType $CheckpointType

Set-VM -Name $VMName -AutomaticCheckpointsEnabled $EnableAutomaticCheckpoints

$DataExchangeService = Get-VMIntegrationService -VMName $VMName |
    Where-Object { $_.Name -in @("Data Exchange", "Key-Value Pair Exchange") }

if ($null -ne $DataExchangeService) {
    if ($DisableDataExchange) {
        Disable-VMIntegrationService -VMName $VMName -Name $DataExchangeService.Name
    }
    else {
        Enable-VMIntegrationService -VMName $VMName -Name $DataExchangeService.Name
    }
}
else {
    Write-Warning "Data Exchange / Key-Value Pair Exchange integration service was not found."
}



# VLAN



if ($VlanId -gt 0) {
    Write-Host "Applying VLAN ID $VlanId..." -ForegroundColor Yellow
    Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId $VlanId
}
else {
    Write-Host "No VLAN tagging applied." -ForegroundColor DarkGray
}



# ISO



if ($ISOPath -ne "") {
    Write-Host "Mounting ISO..." -ForegroundColor Yellow
    Add-VMDvdDrive -VMName $VMName -Path $ISOPath

    $dvd = Get-VMDvdDrive -VMName $VMName
    $hdd = Get-VMHardDiskDrive -VMName $VMName

    Set-VMFirmware -VMName $VMName -FirstBootDevice $dvd  
}



# SECURE BOOT


if ($Generation -eq 2) {
    Write-Host "Ensuring Secure Boot is enabled..." -ForegroundColor Yellow
    Set-VMFirmware -VMName $VMName -EnableSecureBoot On
}



# SUMMARY



Write-Host ""
Write-Host "VM created successfully." -ForegroundColor Green
Write-Host "Name:        $VMName"
Write-Host "Generation:  $Generation"
Write-Host "RAM:         $StartupMemoryGB GB"
Write-Host "vCPU:        $ProcessorCount"
Write-Host "VHDX:        $VHDPath ($VHDSizeGB GB)"
Write-Host "Switch:      $VirtualSwitchName"
if ($ISOPath -ne "") { Write-Host "ISO:         $ISOPath" }
if ($VlanId -gt 0)   { Write-Host "VLAN ID:     $VlanId" }