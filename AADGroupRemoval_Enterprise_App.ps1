## Input File Structure with 
##Group names
##displayName
##forge-10086-*
##forge-10066-*
####Actual Script for removing groups from Enterprise App###############
param(
    [string]$ServicePrincipalId = "**************************",
    [string]$CsvPath = "C:\tmp\groups.csv"
)
 
Connect-MgGraph
 
Write-Host "Loading CSV from: $CsvPath"
 
try {
    $groupsToRemove = Import-Csv -Path $CsvPath
} catch {
    Write-Error "Failed to read CSV file."
    return
}
 
# Get all assignments from app
Write-Host "Retrieving Enterprise App assignments..."
$assignments = Get-MgServicePrincipalAppRoleAssignedTo `
    -ServicePrincipalId $ServicePrincipalId `
    -All `
    -Property "Id,PrincipalId,PrincipalType,PrincipalDisplayName"
 
foreach ($entry in $groupsToRemove) {
 
    $groupName = $entry.displayName
 
    if (-not $groupName) {
        Write-Warning "Skipping empty row."
        continue
    }
 
    Write-Host "Processing group: $groupName"
 
    try {
        # Find matching assignments
        $matches = $assignments | Where-Object {
            $_.PrincipalType -eq "Group" -and
            $_.PrincipalDisplayName -eq $groupName
        }
 
        if (-not $matches) {
            Write-Warning "Group not found in app: $groupName"
            continue
        }
 
        foreach ($assignment in $matches) {
            try {
                Remove-MgServicePrincipalAppRoleAssignedTo `
                    -ServicePrincipalId $ServicePrincipalId `
                    -AppRoleAssignmentId $assignment.Id
 
                Write-Host "SUCCESS: Removed $groupName (AssignmentId: $($assignment.Id))" -ForegroundColor Green
            }
            catch {
                Write-Error "FAILED: Could not remove $groupName (AssignmentId: $($assignment.Id))"
                Write-Error $_
            }
        }
    }
    catch {
        Write-Error "ERROR processing group: $groupName"
        Write-Error $_
    }
}
 
Write-Host "Bulk removal process completed."
