# Get all guest users
$guests = Get-MgUser -Filter "userType eq 'Guest'" -All

# Create an array to hold the results
$results = @()

foreach ($guest in $guests) {
    try {
        # Get sponsors for each guest
        $sponsors = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$($guest.Id)/sponsors"
        
        # Get sponsor details for each sponsor ID
        $sponsorDetails = foreach ($sponsorInfo in $sponsors.value) {
            $sponsorUser = Get-MgUser -UserId $sponsorInfo.id
            $sponsorUser.DisplayName
        }

        # Create custom object for each guest
        $results += [PSCustomObject]@{
            GuestUPN = $guest.UserPrincipalName
            GuestDisplayName = $guest.DisplayName
            GuestId = $guest.Id
            SponsorCount = ($sponsors.value).Count
            Sponsors = ($sponsorDetails -join '; ')
            SponsorIds = ($sponsors.value.id -join '; ')
        }

        Write-Host "Processed guest: $($guest.DisplayName)"
    }
    catch {
        Write-Warning "Error processing guest $($guest.UserPrincipalName): $_"
    }
}

# Export to CSV - using timestamp in filename
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$exportPath = "~/Desktop/GuestSponsors_$timestamp.csv"
$results | Export-Csv -Path $exportPath -NoTypeInformation

Write-Host "Export complete: $exportPath"