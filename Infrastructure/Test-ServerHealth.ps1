<#
.SYNOPSIS
    Returns a health summary for one or more Windows servers.

.DESCRIPTION
    Collects uptime, memory pressure, low-space volumes, stopped automatic
    services and pending reboot state in a single pass. Written to replace
    the manual round of checks I ran each morning across a site, and to give
    a consistent baseline when taking over an environment with no
    documentation.

.PARAMETER ComputerName
    One or more servers to query. Defaults to the local machine.

.PARAMETER DiskThresholdPercent
    Volumes with less free space than this are reported. Default 15.

.EXAMPLE
    Test-ServerHealth

.EXAMPLE
    Get-Content .\servers.txt | Test-ServerHealth -DiskThresholdPercent 20

.EXAMPLE
    Test-ServerHealth -ComputerName srv01,srv02 |
        Where-Object { $_.PendingReboot -or $_.LowSpaceVolumes }

.NOTES
    Author:  Marko Vuksanovic
    Version: 1.1

    Local queries use DCOM so the script works without WinRM on the machine
    it runs from. Remote targets require WinRM enabled and local administrator
    rights. Unreachable hosts return Reachable = $false with the reason in
    Error rather than stopping the run — the point is a full picture in one
    pass, including what you cannot see.
#>
function Test-ServerHealth {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string[]]$ComputerName = $env:COMPUTERNAME,

        [ValidateRange(1, 99)]
        [int]$DiskThresholdPercent = 15
    )

    process {
        foreach ($computer in $ComputerName) {

            $result = [ordered]@{
                ComputerName    = $computer
                Reachable       = $false
                UptimeDays      = $null
                MemoryUsedPct   = $null
                LowSpaceVolumes = $null
                StoppedServices = $null
                PendingReboot   = $null
                Error           = $null
            }

            $session = $null
            $isLocal = $computer -in @($env:COMPUTERNAME, 'localhost', '.', '127.0.0.1')

            try {
                if ($isLocal) {
                    $session = New-CimSession -ErrorAction Stop
                }
                else {
                    $session = New-CimSession -ComputerName $computer -ErrorAction Stop
                }

                $os = Get-CimInstance Win32_OperatingSystem -CimSession $session -ErrorAction Stop
                $result.Reachable  = $true
                $result.UptimeDays = [math]::Round(
                    ((Get-Date) - $os.LastBootUpTime).TotalDays, 1)

                $usedPct = ($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) /
                           $os.TotalVisibleMemorySize * 100
                $result.MemoryUsedPct = [math]::Round($usedPct, 1)

                $lowDisks = Get-CimInstance Win32_LogicalDisk -CimSession $session -Filter "DriveType=3" |
                    Where-Object { $_.Size -gt 0 -and
                                   ($_.FreeSpace / $_.Size * 100) -lt $DiskThresholdPercent } |
                    ForEach-Object {
                        "{0} {1}% free" -f $_.DeviceID,
                            [math]::Round($_.FreeSpace / $_.Size * 100, 1)
                    }
                $result.LowSpaceVolumes = $lowDisks -join '; '

                $ignoredServices = @('sppsvc', 'gupdate', 'RemoteRegistry', 'edgeupdate', 'MapsBroker')
                $stopped = Get-CimInstance Win32_Service -CimSession $session `
                    -Filter "StartMode='Auto' AND State='Stopped'" |
                    Where-Object { $_.Name -notin $ignoredServices } |
                    Select-Object -ExpandProperty Name
                $result.StoppedServices = $stopped -join '; '

                $rebootKeys = @(
                    'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                    'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
                )

                if ($isLocal) {
                    $result.PendingReboot = [bool](
                        $rebootKeys | Where-Object { Test-Path "HKLM:\$_" })
                }
                else {
                    $baseKey = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey(
                        'LocalMachine', $computer)
                    $result.PendingReboot = [bool](
                        $rebootKeys | Where-Object { $baseKey.OpenSubKey($_) })
                    $baseKey.Close()
                }
            }
            catch {
                $result.Error = $_.Exception.Message
                Write-Warning "$computer - $($_.Exception.Message)"
            }
            finally {
                if ($session) { Remove-CimSession $session -ErrorAction SilentlyContinue }
            }

            [PSCustomObject]$result
        }
    }
}
