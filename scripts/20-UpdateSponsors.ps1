# Read the CSV - adjust path as needed
$guests = Import-Csv "path/to/your/file.csv"

foreach ($row in $guests) {
    try {
        # Get Guest ID from UPN
        $guestUser = Get-MgUser -UserId $row.guestUPN -ErrorAction Stop
        $guestId = $guestUser.Id

        # Get Sponsor ID from display name
        $sponsorUser = Get-MgUser -Filter "displayName eq '$($row.Sponsor)'" -ErrorAction Stop
        
        if (-not $sponsorUser) {
            Write-Warning "Sponsor not found: '$($row.Sponsor)' for guest: $($row.guestUPN)"
            continue
        }
        
        $sponsorId = $sponsorUser.Id

        # Get current sponsors
        $currentSponsors = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$guestId/sponsors"

        # Remove sponsors that don't match the intended sponsor
        foreach ($currentSponsor in $currentSponsors.value) {
            if ($currentSponsor.id -ne $sponsorId) {
                Write-Host "Removing sponsor $($currentSponsor.id) from guest $($row.guestUPN)"
                Invoke-MgGraphRequest -Method DELETE -Uri "https://graph.microsoft.com/v1.0/users/$guestId/sponsors/$($currentSponsor.id)/`$ref"
            }
        }

        # Add new sponsor if not already present
        if ($currentSponsors.value.id -notcontains $sponsorId) {
            Write-Host "Adding sponsor $($row.Sponsor) to guest $($row.guestUPN)"
            $body = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/users/$sponsorId"
            } | ConvertTo-Json

            Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$guestId/sponsors/`$ref" -Body $body
        }
    }
    catch {
        Write-Error "Error processing guest: $($row.guestUPN). Error: $_"
        continue
    }
}