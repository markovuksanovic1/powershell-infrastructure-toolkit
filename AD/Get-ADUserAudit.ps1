<#
.SYNOPSIS
    Audits enabled Active Directory user accounts for stale and risky states.

.DESCRIPTION
    Reports enabled accounts that have not logged on within a cutoff, accounts
    with non-expiring passwords, accounts whose password is older than a
    threshold, and accounts holding privileged group membership. Written after
    taking over an environment with no documentation, where the first question
    was simply who still has access and why.

.PARAMETER StaleDays
    Days of inactivity after which an account is flagged as stale. Default 90.

.PARAMETER PasswordAgeDays
    Password age in days above which an account is flagged. Default 365.

.PARAMETER SearchBase
    Optional distinguished name to limit the search to one OU.

.PARAMETER PrivilegedGroup
    Groups treated as privileged. Defaults to the built-in high-value groups.

.EXAMPLE
    Get-ADUserAudit

.EXAMPLE
    Get-ADUserAudit -StaleDays 60 -SearchBase 'OU=Staff,DC=example,DC=com' |
        Where-Object Findings |
        Export-Csv .\ad_audit.csv -NoTypeInformation -Encoding UTF8

.EXAMPLE
    Get-ADUserAudit | Where-Object { $_.Privileged -and $_.Stale }

.NOTES
    Author:  Marko Vuksanovic
    Version: 1.0

    Requires the ActiveDirectory module (RSAT) and read access to the domain.

    LastLogonDate is derived from lastLogonTimestamp, which replicates on a
    delay of up to 14 days by default. Accounts near the cutoff may therefore
    appear stale when they are not — this is intended as a shortlist to review,
    not an authority to disable on.
#>
function Get-ADUserAudit {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3650)]
        [int]$StaleDays = 90,

        [ValidateRange(1, 3650)]
        [int]$PasswordAgeDays = 365,

        [string]$SearchBase,

        [string[]]$PrivilegedGroup = @(
            'Domain Admins', 'Enterprise Admins', 'Schema Admins',
            'Account Operators', 'Server Operators', 'Backup Operators'
        )
    )

    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw "ActiveDirectory module not found. Install RSAT and retry."
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    $staleCutoff    = (Get-Date).AddDays(-$StaleDays)
    $passwordCutoff = (Get-Date).AddDays(-$PasswordAgeDays)

    # Build the privileged account set once rather than per user
    $privilegedSids = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($group in $PrivilegedGroup) {
        try {
            Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop |
                Where-Object objectClass -eq 'user' |
                ForEach-Object { [void]$privilegedSids.Add($_.SID.Value) }
        }
        catch {
            Write-Warning "Could not read group '$group' - $($_.Exception.Message)"
        }
    }

    $params = @{
        Filter     = { Enabled -eq $true }
        Properties = 'LastLogonDate', 'PasswordLastSet', 'PasswordNeverExpires',
                     'PasswordExpired', 'whenCreated', 'Description', 'SID'
    }
    if ($SearchBase) { $params.SearchBase = $SearchBase }

    Get-ADUser @params | ForEach-Object {

        $findings = [System.Collections.Generic.List[string]]::new()

        $isStale = $_.LastLogonDate -and $_.LastLogonDate -lt $staleCutoff
        $neverLoggedOn = -not $_.LastLogonDate

        if ($isStale)                  { $findings.Add("Stale (${StaleDays}d)") }
        if ($neverLoggedOn)            { $findings.Add('Never logged on') }
        if ($_.PasswordNeverExpires)   { $findings.Add('Password never expires') }
        if ($_.PasswordLastSet -and
            $_.PasswordLastSet -lt $passwordCutoff) { $findings.Add('Password age') }
        if (-not $_.PasswordLastSet)   { $findings.Add('Password never set') }

        $isPrivileged = $privilegedSids.Contains($_.SID.Value)
        if ($isPrivileged -and ($isStale -or $neverLoggedOn)) {
            $findings.Add('PRIVILEGED and inactive')
        }

        [PSCustomObject]@{
            SamAccountName       = $_.SamAccountName
            Name                 = $_.Name
            Enabled              = $_.Enabled
            Privileged           = $isPrivileged
            LastLogonDate        = $_.LastLogonDate
            DaysSinceLogon       = if ($_.LastLogonDate) {
                                       [math]::Floor(((Get-Date) - $_.LastLogonDate).TotalDays)
                                   } else { $null }
            PasswordLastSet      = $_.PasswordLastSet
            PasswordNeverExpires = $_.PasswordNeverExpires
            Created              = $_.whenCreated
            Stale                = $isStale -or $neverLoggedOn
            Findings             = $findings -join '; '
        }
    }
}
