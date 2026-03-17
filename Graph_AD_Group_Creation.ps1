## Connect to Microsoft Graph
Connect-MgGraph -Scopes "Group.ReadWrite.All","User.Read.All","Directory.Read.All"

# Import security group details from CSV file
$CSVRecords = Import-Csv "C:\Users\UserID\"

$TotalItems = $CSVRecords.Count
$i = 0

ForEach ($CSVRecord in $CSVRecords) {

    $GroupName        = $CSVRecord."GroupName"
    $GroupDescription = $CSVRecord."GroupDescription"
    $Owners           = if ($CSVRecord."Owners")  { $CSVRecord."Owners" -split ';' } else { $null }
    $Members          = if ($CSVRecord."Members") { $CSVRecord."Members" -split ';' } else { $null }

    Try {
        $i++
        Write-Progress -Activity "Processing group $GroupName" -Status "$i out of $TotalItems"

        # Check if group exists
        $ExistingGroup = Get-MgGroup -Filter "displayName eq '$GroupName'"

        if ($ExistingGroup) {
            Write-Host "Group '$GroupName' already exists. Skipping creation." -ForegroundColor Yellow
        }
        else {

            # Create new security group
            $NewGroup = New-MgGroup `
                -DisplayName $GroupName `
                -Description $GroupDescription `
                -SecurityEnabled:$true `
                -MailEnabled:$false `
                -MailNickname "NotSet" `
                -GroupTypes @()

            Write-Host "Group '$GroupName' created successfully." -ForegroundColor Green

            # Add owners
            if ($Owners) {
                foreach ($Owner in $Owners) {

                    $OwnerObj = Get-MgUser -UserId $Owner -ErrorAction SilentlyContinue

                    if ($OwnerObj) {

                        $OwnerRef = @{
                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($OwnerObj.Id)"
                        }

                        New-MgGroupOwnerByRef -GroupId $NewGroup.Id -BodyParameter $OwnerRef
                    }
                }
            }

            # Add members
            if ($Members) {
                foreach ($Member in $Members) {

                    $MemberObj = Get-MgUser -UserId $Member -ErrorAction SilentlyContinue

                    if ($MemberObj) {

                        $MemberRef = @{
                            "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$($MemberObj.Id)"
                        }

                        New-MgGroupMemberByRef -GroupId $NewGroup.Id -BodyParameter $MemberRef
                    }
                }
            }

            # Validation
            $CreatedGroup = Get-MgGroup -GroupId $NewGroup.Id
            $CreatedOwners = Get-MgGroupOwner -GroupId $NewGroup.Id | Select-Object -ExpandProperty AdditionalProperties

            Write-Host "`nValidation for group '$($CreatedGroup.DisplayName)':"
            Write-Host " - Group Name: $($CreatedGroup.DisplayName)"
            Write-Host " - Created DateTime: $($CreatedGroup.CreatedDateTime)"
            Write-Host ""
        }
    }
    Catch {
        Write-Host "Error creating group ${GroupName}: $_" -ForegroundColor Red
    }
}
