<#
.SYNOPSIS
    Checks TLS certificate expiry across a list of endpoints.

.DESCRIPTION
    Connects to each endpoint, retrieves the served certificate and reports
    days remaining until expiry. Written after an avoidable outage caused by
    an expired certificate on an internally managed service.

.PARAMETER Endpoint
    Hostname or hostname:port. Defaults to port 443.

.PARAMETER WarningDays
    Threshold in days below which an endpoint is flagged. Default 30.

.EXAMPLE
    Get-CertificateExpiry -Endpoint 'portal.example.com','vpn.example.com:8443'

.EXAMPLE
    Get-Content .\endpoints.txt | Get-CertificateExpiry -WarningDays 60 |
        Where-Object Status -ne 'OK' | Export-Csv .\expiring.csv -NoTypeInformation

.NOTES
    Author:  Marko Vuksanovic
    Version: 1.0

    Certificate chain validation is intentionally bypassed so that expired,
    self-signed and hostname-mismatched certificates can still be read —
    those are exactly the cases this script exists to find. As a result the
    script reports on expiry only, not on chain validity or hostname match.
#>
function Get-CertificateExpiry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Endpoint,

        [ValidateRange(1, 365)]
        [int]$WarningDays = 30
    )

    process {
        foreach ($e in $Endpoint) {
            $parts = $e.Split(':')
            $hostName = $parts[0]
            $port = if ($parts.Count -gt 1) { [int]$parts[1] } else { 443 }

            $tcpClient = $null
            $sslStream = $null

            try {
                $tcpClient = [System.Net.Sockets.TcpClient]::new()
                if (-not $tcpClient.ConnectAsync($hostName, $port).Wait(5000)) {
                    throw "Connection timed out after 5s"
                }

                $sslStream = [System.Net.Security.SslStream]::new(
                    $tcpClient.GetStream(), $false, { $true })
                $sslStream.AuthenticateAsClient($hostName)

                $cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    $sslStream.RemoteCertificate)
                $daysLeft = [math]::Floor(($cert.NotAfter - (Get-Date)).TotalDays)

                [PSCustomObject]@{
                    Endpoint = $e
                    Subject  = $cert.Subject
                    Issuer   = $cert.Issuer
                    NotAfter = $cert.NotAfter
                    DaysLeft = $daysLeft
                    Status   = if ($daysLeft -lt 0)                { 'EXPIRED' }
                               elseif ($daysLeft -lt $WarningDays) { 'WARNING' }
                               else                                { 'OK' }
                }
            }
            catch {
                Write-Warning "$e - $($_.Exception.Message)"
                [PSCustomObject]@{
                    Endpoint = $e
                    Subject  = $null
                    Issuer   = $null
                    NotAfter = $null
                    DaysLeft = $null
                    Status   = 'ERROR'
                }
            }
            finally {
                if ($sslStream) { $sslStream.Dispose() }
                if ($tcpClient) { $tcpClient.Dispose() }
            }
        }
    }
}
