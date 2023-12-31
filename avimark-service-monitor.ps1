<#
.SYNOPSIS
  Checks for avimark service status and if stopped attempts to start. Every 5 minutes.
.DESCRIPTION
  <Brief description of script>
.PARAMETER <Parameter_Name>
    
.INPUTS
  None
.OUTPUTS
  Not much
.NOTES
  Version:        1.11
  Author:         Jason Johnson
  Creation Date:  8.22.2023
  Purpose/Change: To make things work better
  
.EXAMPLE
  Run it via task manager.
#>

$servicePattern = "*avimark*"
$waitInterval = 300  # seconds (5 minutes)
$startupDelay = 300  # additional seconds to wait after system startup (5 minutes)
$outputFile = "C:\avimark-service-monitor"

# Buffer for messages
$bufferedOutput = @()

function AddToBuffer {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    $bufferedOutput += $Message
}

function WriteBufferToFile {
    $bufferedOutput | Out-File -Path $outputFile -Force
}

# Check if the system has been up for less than 5 minutes (300 seconds)
$uptime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
$elapsedTime = New-TimeSpan -Start $uptime -End (Get-Date)
if ($elapsedTime.TotalSeconds -lt 300) {
    AddToBuffer "System recently started. Waiting for $startupDelay seconds to allow delayed services to start..."
    Start-Sleep -Seconds $startupDelay
}

# Find services matching the given pattern
$services = Get-Service | Where-Object { $_.DisplayName -like $servicePattern }

if (-not $services) {
    AddToBuffer "No services found with display name pattern: $servicePattern"
    exit
}

$servicesRunning = $false

foreach ($service in $services) {
    AddToBuffer "Checking service: $($service.DisplayName)"

    while ($true) {  # Endless loop
        if ($service.Status -eq 'Stopped') {
            AddToBuffer "Service $($service.DisplayName) is stopped. Waiting for $waitInterval seconds..."

            Start-Sleep -Seconds $waitInterval
            $service.Refresh()

            if ($service.Status -eq 'Stopped') {
                AddToBuffer "Attempting to start the service $($service.DisplayName)..."

                try {
                    Start-Service -InputObject $service
                    AddToBuffer "Service $($service.DisplayName) started successfully."
                    Start-Sleep -Seconds $waitInterval
                    $service.Refresh()

                    if ($service.Status -eq 'Running') {
                        $servicesRunning = $true
                        AddToBuffer "Service $($service.DisplayName) is running. Exiting loop."
                        break
                    }
                } catch {
                    AddToBuffer "Error starting service $($service.DisplayName): $_"

                    # Log the error to the EventLog
                    $evtHash = @{
                        LogName   = 'Application'
                        Source    = 'ServiceStartScript'
                        EventID   = 1001
                        EntryType = 'Error'
                        Message   = "Service $($service.DisplayName) failed to start. Error: $_"
                    }
                    New-EventLog @evtHash -ErrorAction SilentlyContinue
                    Write-EventLog @evtHash
                }
            }
        } else {
            $servicesRunning = $true
            AddToBuffer "Service $($service.DisplayName) is already running. Exiting loop."
            break
        }
    }
}

# If any services were found running, write output to file
if ($servicesRunning) {
    WriteBufferToFile
}
