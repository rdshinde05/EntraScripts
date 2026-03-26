Connect-MgGraph
 
$updates = Import-Csv "C:\tmp\Groups_Desc.csv"
 
foreach ($entry in $updates) {
 
    try {
 
        Write-Host "Processing group: $($entry.Name)"

        $group = Get-MgGroup -Filter "displayName eq '$($entry.Name)'" -ConsistencyLevel eventual
 
        if (-not $group) {
            Write-Warning "Group not found: $($entry.Name)"
            continue
        }
 
        # description update
        try {
            Update-MgGroup `
                -GroupId $group.Id `
                -Description $entry.Description `
                -ErrorAction Stop
 
            Write-Host "Updated description for: $($entry.Name)"
        }
        catch {
            Write-Warning "Failed to update description for $($entry.Name): $_"
        }
 
    }
    catch {
        Write-Error "Unexpected failure while processing $($entry.Name): $_"
    }
 
}
