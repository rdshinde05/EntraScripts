#Use this script to update Group Ownership when we have multiple groups to update in single tenant
#input file structure:
 
#DisplayName	Owner1	Owner2
#Groupname   email1  email 2


Connect-MgGraph
 
$groups = Import-Csv "C:\tmp\Bulk_Group_Update.csv"
 
foreach ($group in $groups) {
 
    try {
        Write-Host "`nProcessing group: $($group.DisplayName)" -ForegroundColor Cyan
 
        $mgGroup = Get-MgGroup -Filter "displayName eq '$($group.DisplayName)'" -ConsistencyLevel eventual
 
        if (-not $mgGroup) {
            Write-Warning "Group not found: $($group.DisplayName)"
            continue
        }
 
        Write-Host "Group found (ID: $($mgGroup.Id))" -ForegroundColor Green
 

        $existingOwners = Get-MgGroupOwner -GroupId $mgGroup.Id -All
 
        # Collect new owners from file
        $csvOwners = $group.PSObject.Properties |
                     Where-Object { $_.Name -match "^Owner\d+$" -and $_.Value }
 
        if ($csvOwners.Count -eq 0) {
            Write-Warning "No new owners provided. Skipping group."
            continue
        }
 
        $newOwnerIds = @()
 
        # Add new owners
        Write-Host "Adding new owner(s)..." -ForegroundColor Cyan
 
        foreach ($owner in $csvOwners) {
            try {
                $user = Get-MgUser -UserId $owner.Value -ErrorAction Stop
 
                New-MgGroupOwnerByRef `
                    -GroupId $mgGroup.Id `
                    -BodyParameter @{
                        "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
                    }
 
                $newOwnerIds += $user.Id
                Write-Host "Owner added: $($owner.Value)" -ForegroundColor Green
            }
            catch {
                Write-Warning "Failed to add owner: $($owner.Value)"
            }
        }
 
        # Remove old owners
        Write-Host "Removing old owner(s)..." -ForegroundColor Yellow
 
        foreach ($oldOwner in $existingOwners) {
 
            if ($newOwnerIds -contains $oldOwner.Id) {
                Write-Host "Skipping removal of newly added owner $($oldOwner.Id)" -ForegroundColor DarkGray
                continue
            }
 
            try {
                Remove-MgGroupOwnerByRef `
                    -GroupId $mgGroup.Id `
                    -DirectoryObjectId $oldOwner.Id `
                    -ErrorAction Stop
 
                Write-Host "Removed owner: $($oldOwner.Id)"
            }
            catch {
                Write-Warning "Failed to remove owner $($oldOwner.Id)"
            }
        }
 
        Write-Host "Completed processing for group: $($group.DisplayName)" -ForegroundColor Green
    }
    catch {
        Write-Error "Fatal error processing group $($group.DisplayName): $_"
    }
}
 
