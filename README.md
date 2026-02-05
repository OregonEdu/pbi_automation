# Power BI Automation Scripts
Benjamin Barshaw <<benjamin.barshaw@ode.oregon.gov>> - IT Operations & Support Network Team Lead - Oregon Department of Education

Requirements: 

MicrosoftPowerBIMgmt PowerShell Module (Install-Module -Name MicrosoftPowerBIMgmt)

Fabric/PowerBI Administrator PIM Role

Must be connected to the tenant's Power BI space with Login-PowerBIServiceAccount

# PBI Workspace Audit

This script was created to determine which Power BI workspaces in our tenant were no longer being used. We use the Get-PowerBIActivityEvent cmdlet to retrieve activity logs going back as far as we can go. The cmdlet does not allow you to select date ranges -- you MUST
use the same day in the StartDateTime and EndDateTime parameters. To get all logs for a given day we set our StartDateTime for midnight (00:00:00) and our EndDateTime for 1 minute 'til midnight (23:59:59).  The cmdlet is also tricky in that if you select a date out of the 
range that it still has data for, it does not give you any useful sort of error it just fails with "Get-PowerBIActivityEvent: Operation returned an invalid status code 'BadRequest'".  For this reason we set a $tryStartDate variable with how many days we wish to attempt to
go back and then decrement that integer until we get to 0 pulling logs for each date (30 days ago, 29 days ago, 28 days ago, ad nauseam) as we make our way to today's date. We then retrieve all NON-PERSONAL Power BI workspaces in the tenant and query the logs we pulled for
any activity in them. If found, the CSV we export will show the most recent time of the last activity found. We also export any users belonging to the workspace by the access type they possess -- Admin, Contributor, Member, Viewer.  The CSV will be exported to the Current
Working Directory (CWD) as PBI_Workspace_Audit-<MMddyyyy>.csv with MMddyyyy being today's date.

# PBI Workspace Deletion

This script was created as Microsoft does not make it easy for administrator to delete a Power BI Workspace from the Admin Console. You must first add your Administrator account as an Owner, then go to the workspace, go to the settings, scroll down to the bottom and hit
"Remove". They do not have a PowerShell cmdlet (yet) that deletes them either, so you must use the Power BI REST API interface to script any sort of mass deletions. I was quite pleased to find out that they have a cmdlet "Get-PowerBIAccessToken" however as it meant not
having to add in my functions for generating a device code to get a token. Thanks Microsoft! This script is menu-driven and does make you confirm before deleting a Workspace to avoid tears.
