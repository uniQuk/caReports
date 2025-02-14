# Required module: ImportExcel

$policiesPath = "/Volumes/Kingston2TB/Dev/cagaps/policies/data"
$outputPath = "/Volumes/Kingston2TB/Dev/cagaps/analysis/excel"
$excelFile = Join-Path $outputPath "CA_Policies_Analysis.xlsx"

# Create output directory if it doesn't exist
if (-not (Test-Path $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath
}

# Helper function to normalize state display
function Format-PolicyState {
    param([string]$state)
    switch ($state) {
        "enabled" { "Enabled" }
        "enabledForReportingButNotEnforced" { "ReportOnly" }
        "disabled" { "Disabled" }
        default { $state }
    }
}

# Helper function to validate policy structure
function Test-PolicyStructure {
    param($policy)
    try {
        $requiredProperties = @('displayName', 'conditions', 'state')
        foreach ($prop in $requiredProperties) {
            if ($null -eq $policy.$prop) {
                Write-Warning "Policy '$($policy.displayName)' is missing required property: $prop"
                return $false
            }
        }
        return $true
    }
    catch {
        Write-Warning "Error validating policy structure: $_"
        return $false
    }
}

try {
    # Get all policy files and validate
    $policyFiles = Get-ChildItem -Path $policiesPath -Filter "*.json" -ErrorAction Stop
    $policies = @()
    
    foreach ($file in $policyFiles) {
        try {
            $policy = Get-Content $file.FullName -Raw | ConvertFrom-Json
            if (Test-PolicyStructure $policy) {
                $policies += $policy
            }
        }
        catch {
            Write-Warning "Error processing file $($file.Name): $_"
        }
    }

    if ($policies.Count -eq 0) {
        throw "No valid policies found to process"
    }

    # Helper function to format array values for Excel
    function Format-ArrayForExcel {
        param([Array]$array)
        if ($null -eq $array -or $array.Count -eq 0) { return $null }
        return ($array | Where-Object { ![string]::IsNullOrWhiteSpace($_) }) -join "`n"
    }

    # Create expanded overview data with all settings
    $overviewData = $policies | Select-Object @{N='Policy Name';E={$_.displayName}}, 
        @{N='State';E={Format-PolicyState $_.state}},
        @{N='Created';E={$_.createdDateTime}},
        @{N='Modified';E={$_.modifiedDateTime}},
        @{N='Include Users';E={Format-ArrayForExcel $_.conditions.users.includeUsers}},
        @{N='Include Groups';E={
            Format-ArrayForExcel ($_.conditions.users.includeGroups.PSObject.Properties.Value.displayName)
        }},
        @{N='Included Group Members';E={
            $members = @()
            foreach ($group in $_.conditions.users.includeGroups.PSObject.Properties.Value) {
                if ($group.members) {
                    $groupMembers = $group.members.PSObject.Properties.Value.userPrincipalName
                    if ($groupMembers) {
                        $members += "$($group.displayName):`n  $(($groupMembers | Sort-Object) -join "`n  ")"
                    }
                }
            }
            Format-ArrayForExcel $members
        }},
        @{N='Include Roles';E={
            Format-ArrayForExcel ($_.conditions.users.includeRoles.PSObject.Properties.Value.displayName | Sort-Object)
        }},
        @{N='Include Guest/External';E={$_.conditions.users.includeGuestsOrExternalUsers}},
        @{N='Exclude Users';E={
            $users = @()
            foreach ($user in $_.conditions.users.excludeUsers.PSObject.Properties.Value) {
                if ($user.userPrincipalName) { 
                    $users += $user.userPrincipalName
                }
            }
            Format-ArrayForExcel ($users | Sort-Object)
        }},
        @{N='Exclude Groups';E={
            Format-ArrayForExcel ($_.conditions.users.excludeGroups.PSObject.Properties.Value.displayName | Sort-Object)
        }},
        @{N='Excluded Group Members';E={
            $members = @()
            foreach ($group in $_.conditions.users.excludeGroups.PSObject.Properties.Value) {
                if ($group.members) {
                    $groupMembers = $group.members.PSObject.Properties.Value.userPrincipalName
                    if ($groupMembers) {
                        $members += "$($group.displayName):`n  $(($groupMembers | Sort-Object) -join "`n  ")"
                    }
                }
            }
            Format-ArrayForExcel $members
        }},
        @{N='Exclude Roles';E={
            Format-ArrayForExcel ($_.conditions.users.excludeRoles.PSObject.Properties.Value.displayName | Sort-Object)
        }},
        @{N='Exclude Guest/External';E={$_.conditions.users.excludeGuestsOrExternalUsers}},
        @{N='Applications';E={
            if ($_.conditions.applications.includeApplications -eq "All") { "All" }
            else { 
                Format-ArrayForExcel ($_.conditions.applications.includeApplications.PSObject.Properties.Value.displayName | Sort-Object)
            }
        }},
        @{N='Exclude Applications';E={
            Format-ArrayForExcel ($_.conditions.applications.excludeApplications.PSObject.Properties.Value.displayName | Sort-Object)
        }},
        @{N='User Actions';E={Format-ArrayForExcel $_.conditions.applications.includeUserActions}},
        @{N='Authentication Context';E={Format-ArrayForExcel $_.conditions.applications.includeAuthenticationContextClassReferences}},
        @{N='Client App Types';E={Format-ArrayForExcel $_.conditions.clientAppTypes}},
        @{N='Device Platforms';E={
            if ($_.conditions.platforms) {
                Format-ArrayForExcel $_.conditions.platforms.includePlatforms
            }
        }},
        @{N='Exclude Platforms';E={
            if ($_.conditions.platforms) {
                Format-ArrayForExcel $_.conditions.platforms.excludePlatforms
            }
        }},
        @{N='Device State';E={
            if ($_.conditions.devices.deviceFilter) {
                $_.conditions.devices.deviceFilter.rule
            }
        }},
        @{N='Locations';E={
            if ($_.conditions.locations) {
                Format-ArrayForExcel $_.conditions.locations.includeLocations
            }
        }},
        @{N='Exclude Locations';E={
            if ($_.conditions.locations) {
                Format-ArrayForExcel $_.conditions.locations.excludeLocations
            }
        }},
        @{N='User Risk Levels';E={Format-ArrayForExcel $_.conditions.userRiskLevels}},
        @{N='Sign-in Risk Levels';E={Format-ArrayForExcel $_.conditions.signInRiskLevels}},
        @{N='Grant Controls';E={Format-ArrayForExcel $_.grantControls.builtInControls}},
        @{N='Grant Operator';E={$_.grantControls.operator}},
        @{N='Session Controls';E={
            if ($_.sessionControls) {
                $controls = @()
                foreach ($control in $_.sessionControls.PSObject.Properties) {
                    if ($null -ne $control.Value) {
                        $controls += "$($control.Name): $($control.Value.isEnabled)"
                    }
                }
                Format-ArrayForExcel $controls
            }
        }}

    # Create conditional formatting rules for states
    $conditionalFormats = @(
        New-ConditionalText -Text "Enabled" -BackgroundColor LightGreen
        New-ConditionalText -Text "ReportOnly" -BackgroundColor LightYellow
        New-ConditionalText -Text "Disabled" -BackgroundColor LightGray
    )

    # Define column widths based on content type
    $columnWidths = @{
        'Policy Name' = 50          # Wider for policy names
        'State' = 15               # Fixed width for states
        'Created' = 20             # DateTime columns
        'Modified' = 20            # DateTime columns
        'Include Users' = 30       # User lists
        'Include Groups' = 30      # Group lists
        'Include Roles' = 40       # Role lists can be long
        'Applications' = 35        # Application names
        'Grant Controls' = 25      # Control lists
        'Device State' = 40        # Device filter rules can be long
        'Default' = 25            # Default width for other columns
    }

    # Export to Excel with formatting parameters
    $excelParams = @{
        Path = $excelFile
        FreezeTopRow = $true
        BoldTopRow = $true
        AutoFilter = $true
        WorksheetName = "Policies"
        ConditionalText = $conditionalFormats
    }

    # Export the data first
    $overviewData | Export-Excel @excelParams

    # Apply column widths after export
    $excel = Open-ExcelPackage -Path $excelFile
    $ws = $excel.Workbook.Worksheets["Policies"]
    
    # Set column widths
    1..$ws.Dimension.End.Column | ForEach-Object {
        $col = $_
        $headerText = $ws.Cells[1, $col].Text
        $width = $columnWidths[$headerText]
        if (-not $width) { $width = $columnWidths['Default'] }
        $ws.Column($col).Width = $width
    }

    Close-ExcelPackage $excel

    Write-Host "Excel report generated at: $excelFile"
    Write-Host "Note: Please open the Excel file manually in your preferred application."
}
catch {
    Write-Error "Critical error: $_"
    Write-Error $_.Exception.StackTrace
}
