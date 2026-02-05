## Power BI Workspace Deletion Script
## Benjamin Barshaw <benjamin.barshaw@ode.oregon.gov> - IT Operations & Support Network Team Lead - Oregon Department of Education
#
#  Requirements: MicrosoftPowerBIMgmt PowerShell Module (Install-Module -Name MicrosoftPowerBIMgmt)
#                Fabric/PowerBI Administrator PIM Role
#                Must be connected to the tenant's Power BI space with Login-PowerBIServiceAccount
#
#  This script was created as Microsoft does not make it easy for administrator to delete a Power BI Workspace from the Admin Console. You must first add your Administrator account as an Owner, then go to the workspace, go to the settings, scroll down to the bottom and hit
#  "Remove". They do not have a PowerShell cmdlet (yet) that deletes them either, so you must use the Power BI REST API interface to script any sort of mass deletions. I was quite pleased to find out that they have a cmdlet "Get-PowerBIAccessToken" however as it meant not
#  having to add in my functions for generating a device code to get a token. Thanks Microsoft! This script is menu-driven and does make you confirm before deleting a Workspace to avoid tears.
#  
### USER DEFINED VARIABLES SECTION ###
# I wouldn't change this, but here is where we define how far back we would care to try
$paAccount = "<insert_PA_account_UPN>"
### END USER DEFINED VARIABLES SECTION ###

$version = "v1.0"

# Function to add the PA account defined in the above $paAccount variable as an Owner of the PBI Workspace
function addAdminToPBIWorkspace($pbiWorkspaceName, $pbiWorkspaceId)
{    
    Write-Host -ForegroundColor Cyan "Adding $paAccount to $pbiWorkspaceName with workspaceId $pbiWorkspaceId"

    $body = @{
        emailAddress = $paAccount
        groupUserAccessRight = "Admin"
    } | ConvertTo-Json

    Invoke-RestMethod -Method POST -Uri "https://api.powerbi.com/v1.0/myorg/admin/groups/$pbiWorkspaceId/users" -Headers $getHeaders -Body $body -ContentType "application/json"

    Write-Host -ForegroundColor Magenta "Added!"
}

# Function to delete the PBI Workspace with prompting to confirm you really wish to delete it
function deletePBIWorkspace($pbiWorkspaceName, $pbiWorkspaceId)
{
    Write-Host -ForegroundColor DarkYellow "Are you sure you want to delete $workspaceName"
    $yesNo = $null
    while (($yesNo -ne 'y') -and ($yesNo -ne 'n')) 
    {
        $yesNo = Read-Host -Prompt "[Y/N]"
    }
    
    If ($yesNo -eq "y")
    {    
        Write-Host -ForegroundColor Cyan "Deleting $pbiWorkspaceName with workspaceId $pbiWorkspaceId"

        Invoke-RestMethod -Method DELETE -Uri "https://api.powerbi.com/v1.0/myorg/groups/$pbiWorkspaceId" -Headers $getHeaders

        Write-Host -ForegroundColor Magenta "Deleted!"
    }
}

# Display the menu with all our options for deletions
function showMenu
{
    Write-Host -ForegroundColor Cyan "Power BI Workspace Deletion Script $($version) - Benjamin Barshaw <benjamin.barshaw@ode.oregon.gov>"
    Write-Host -ForegroundColor Yellow "Please make your selection:"
    Write-Host -ForegroundColor DarkYellow "1) Delete single Power BI workspace"
    Write-Host -ForegroundColor DarkYellow "2) Delete orphaned Power BI workspaces"
    Write-Host -ForegroundColor DarkYellow "3) Delete all non-personal Power BI workspaces (CAUTION!)"
    Write-Host -ForegroundColor DarkYellow "4) Delete all Power BI workspaces from CSV file (Must have WorkspaceName & WorkspaceId headers)"
    Write-Host -ForegroundColor DarkYellow "5) Show menu"
    Write-Host -ForegroundColor DarkYellow "6) Exit"
}

Write-Host -ForegroundColor Magenta "Checking if we are connected to Power BI..."

# Check to see if we can get PBI token -- if not, login and try again!
try
{
    $getHeaders = Get-PowerBIAccessToken
}
catch
{
    Login-PowerBIServiceAccount
    $getHeaders = Get-PowerBIAccessToken
}

showMenu

do
{
    $menuResponse = (Read-Host -Prompt "Choice (4 to re-display menu; 5 to exit)") -as [int]

    switch($menuResponse)
    {
        # Menu option 1 - delete a single PBI workspace specified by name -- will lookup the ID for you!
        1
        {
            $workspaceName = $(Read-Host -Prompt "Workspace name")
            Write-Host -ForegroundColor Yellow "Looking up workspace ID for $workspaceName)..."
            If (($getWorkspaceId = (Get-PowerBIWorkspace -Name $workspaceName -Scope Organization).Id) -eq $null)
            {
                Write-Host -ForegroundColor Red "Could not find Power BI workspace $workspaceName!"
            }
            Else
            {
                addAdminToPBIWorkspace $workspaceName $getWorkspaceId
                deletePBIWorkspace $workspaceName $getWorkspaceId                
            }
        }
        # Menu option 2 - retrieve all the orphaned PBI workspaces in the tenant -- these are even trickier to do in the webUI
        2
        {
            Write-Host -ForegroundColor Yellow "Retrieving all orphaned Power BI workspaces for tenant..."
            $getOrphanedWorkspaces = Get-PowerBIWorkspace -Scope Organization -Orphaned
            ForEach ($orphanedWorkspace in $getOrphanedWorkspaces)
            {
                addAdminToPBIWorkspace $($orphanedWorkspace).Name $($orphanedWorkspace).Id
                deletePBIWorkspace $($orphanedWorkspace).Name $($orphanedWorkspace).Id
            }
        }
        # Menu option 3 - retrive ALL non-personal and not in state of deletion PBI workspaces in the tenant for deletion -- USE THIS ONE WITH CAUTION!
        3
        {
            Write-Host -ForegroundColor Yellow "Retrieving all non-personal Power BI workspaces for tenant..."
            $getAllNonPersonalWorkspaces = Get-PowerBIWorkspace -Scope Organization -All | Where-Object { $_.Type -ne "PersonalGroup" -and $_.State -ne "Deleted" }
            ForEach ($nonPersonalWorkspace in $getAllNonPersonalWorkspaces)
            {
                addAdminToPBIWorkspace $($nonPersonalWorkspace).Name $($nonPersonalWorkspace).Id
                deletePBIWorkspace $($nonPersonalWorkspace).Name $($nonPersonalWorkspace).Id
            }
        }
        # Meny option 4 - input a CSV file (like the one output from PBI audit script) for mass deletion
        4
        {
            $getCsv = $(Read-Host -Prompt "Workspace CSV (Must have WorkspaceName & WorkspaceId headers)")
            $workspaceCsv = Import-Csv -Path $getCsv -ErrorAction SilentlyContinue
            If ($workspaceCsv -eq $null)
            {
                Write-Host -ForegroundColor Red "Problem importing CSV $getCsv!"
            }
            Else
            {
                Write-Host -ForegroundColor Yellow "Successfully imported $getCsv! Retrieving all Power BI workspaces..."
                ForEach ($pbiWorkspace in $workspaceCsv)
                {
                    addAdminToPBIWorkspace $($pbiWorkspace).WorkspaceName $($pbiWorkspace).WorkspaceId
                    deletePBIWorkspace $($pbiWorkspace).WorkspaceName $($pbiWorkspace).WorkspaceId
                }
            }
        }
        # Menu option 5 - redisplay the menu
        5
        {
            showMenu
        }
        # Menu option 6 - get the hell outta Dodge
        6
        {
            exit
        }
        default
        {
            Write-Host -ForegroundColor Red "Invalid option!"
        }
    }
} 
while ($menuResponse -ne 6)