<#
    .SYNOPSIS
        Function copy files / directories to other servers and manage services related to the copy.

    .DESCRIPTION
        The function starts a specified command which can have dynamically assigned parameters.
        Any specified services are stopped before the commands are run and started after the commands are done.
        It was written for copying/sync'ing files to other server, but can generally be made to run any command, not just copy commands.

        Switch -WhatIf can be used for a dry-run.

    .PARAMETER DestinationServer
        Specifies which server(s) that will be the receivers.        

    .PARAMETER CopyItems
        Specifies what should be copied.
        This is an array of hashtables on a specific format:
            @(
                @{
                    CopyItem="path";
                    CopyCmd="command";
                 },
                @{
                    CopyItem="path";
                    CopyCmd="command";
                 }
            )
			
        Ex:
            @(
                @{
                    CopyItem="c:\directory";
                    CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E ";
                 },
                 @{
                    CopyItem="c:\windows\system32\drivers\etc\hosts";
                    CopyCmd="copy-item `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" -verbose";
                 },
                 @{
                    CopyItem="d:\inetpub\wwwroot";
                    CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E /DCOPY:T /LOG+:d:\logs\appcopy_%CURRENTDATE%.log /TEE /NP";
                 },
            )

        The following variables must / can be used.
        %SOURCEITEM% - must be specified and will be replaced with the source item (CopyItem).
        %DESTINATIONITEM% - must be specified and will be replaced with the destination path.
        %CURRENTDATE% - can be specified and will be replaced by the current date and time on format "yyyy-MM-dd_HHMMss"
        %CURRENTYEAR% - can be specified and will be replaced by the current year on format "yyyy"

    .PARAMETER StopStartService
        If specified, these services will be stopped and start before/after commands are run.

    .PARAMETER AsJob
        Specifies that the commands will run as background jobs.

    .EXAMPLE
        Sync-OLLFilesToServer -DestinationServer "server1","server2" -CopyItems @( @{CopyItem="c:\directory"; CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E "; }, @{CopyItem="c:\windows\system32\drivers\etc\hosts"; CopyCmd="copy-item `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" -verbose";}, @{CopyItem="d:\inetpub\wwwroot"; CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E /DCOPY:T /LOG+:d:\logs\appcopy_%CURRENTDATE%.log /TEE /NP";} )
        
        Copies c:\directory to servers server1 and server2 using robocopy 
        Copies c:\windows\system32\drivers\etc\hosts to sever1 and server2 using copy-item
        Copies d:\inetpub\wwwroot to server1 and server2 using robocopy

    .EXAMPLE
        Sync-OLLFilesToServer -DestinationServer "server1","server2" -CopyItems @( @{CopyItem="c:\directory"; CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E "; }, @{CopyItem="c:\windows\system32\drivers\etc\hosts"; CopyCmd="copy-item `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" -verbose";}, @{CopyItem="d:\inetpub\wwwroot"; CopyCmd="robocopy `"%SOURCEITEM%`" `"%DESTINATIONITEM%`" /E /DCOPY:T /LOG+:d:\logs\appcopy_%CURRENTDATE%.log /TEE /NP";} ) -AsJob -StopStartService "W3SVC,Spooler"
        
        Stops services W3SVC and spooler

        Copies c:\directory to servers server1 and server2 using robocopy 
        Copies c:\windows\system32\drivers\etc\hosts to sever1 and server2 using copy-item
        Copies d:\inetpub\wwwroot to server1 and server2 using robocopy

        Starts services W3SVC and spooler

    .NOTES

    .LINK

#>
Function Sync-OLLFilesToServer {
    [cmdletBinding(SupportsShouldProcess=$True, ConfirmImpact="Low")]
    Param(
        [Parameter(Mandatory=$False)]
        [string]$SourceServer=$Env:ComputerName

        ,[Parameter(Mandatory=$True)]
        [string[]]$DestinationServer

        ,[Parameter(Mandatory=$True)]
        [hashtable[]]$CopyItems

        ,[Parameter(Mandatory=$False)]
        [string[]]$StopStartService

        ,[Parameter(Mandatory=$False)]
        [switch]$AsJob
    )
    
    # Generated with New-FortikaPSFunction

    BEGIN {
        # If -debug is set, change $DebugPreference so that output is a little less annoying.
        #    http://learn-powershell.net/2014/06/01/prevent-write-debug-from-bugging-you/
        If ($PSBoundParameters['Debug']) {
            $DebugPreference = 'Continue'
        }

        #$SourceServer = $env:COMPUTERNAME

        if($StopStartService) {
            if($PSCmdlet.ShouldProcess("stop services")) {
                Invoke-Command -ComputerName $DestinationServer -ScriptBlock { Stop-Service -Name $using:StopStartService -Force }
            }
        }

        $JobList=@()

        if($AsJob) {
            $JobLogPath = Join-Path -Path $PSScriptRoot -ChildPath "joblogs"
            if(-not $(test-path -path $JobLogPath)) { mkdir $JobLogPath -ErrorAction SilentlyContinue | Out-Null }
        }

        foreach($item in $StuffToCopy) {

            if( (-not $item.CopyItem) -or (-not $Item.CopyCmd) ) {
                Write-Warning "CopyItem or CopyCmd can't be null!"

                Continue
            }

            $VarMappings = @{
                SOURCEITEM=$Item.CopyItem;
                DESTINATIONITEM=$(Join-Path -Path "\\%DESTSERVER%" -ChildPath $Item.copyitem ).Replace(":","$")
                CURRENTYEAR=$(get-date -Format "yyyy");
                CURRENTDATE=$(get-date -Format "yyyy-MM-dd_HHMMss");
            }

            $ExpressionToRun = $item.CopyCmd | _Expand-VariablesInString -VariableMappings $VarMappings


            foreach($server in $DestinationServer) {
    
                $cmd = $ExpressionToRun | _Expand-VariablesInString -VariableMappings @{
                    DESTSERVER=$server
                }

                if($AsJob) {
                    Write-Verbose "Kicking off: $cmd"

                    $JobLogFileName = Join-Path -Path $JobLogPath -ChildPath $( "$([guid]::NewGuid()).log" )
            
                    # redirect using *> to redirect all streams

                    if($PSCmdlet.ShouldProcess($item.CopyItem,"copy")) {
                        $JobList += Start-Job -ScriptBlock { Invoke-Expression -Command $using:cmd *>$using:JobLogFileName  }
                    }
                } else {
                    Write-Verbose "Kicking off: $cmd"
                    Write-Progress -Activity "Performing copy" -Status "$cmd"

                    if($PSCmdlet.ShouldProcess($item.CopyItem,"copy")) {
                        Invoke-Expression -Command $cmd 
                    }
                }
            }    
        }

        # Wait for jobs
        # could use wait-job here, but some user interaction is always nice
        if($AsJob) {
            if($JobList) {
                Do {
                    $jobstats = $JobList | get-job | ? { $_.State -eq "Running" } | measure

                    Write-Progress -Activity "Waiting for jobs" -Status "$($jobstats.Count) / $($JobList.count) still running..." 
                    start-sleep 5

                } while ( $jobstats.Count -gt 0 )
            } else {
                Write-Warning "Switch AsJob specified but there's nothing in the joblist!"
            }
        }

        # Start the services
        if($StopStartService) {
            if($PSCmdlet.ShouldProcess("stop services")) {
                Invoke-Command -ComputerName $DestinationServer -ScriptBlock { Start-Service -Name $using:StopStartService -Force }
            }
        }

    }

    PROCESS {

    }

    END {

    }
}

Function _Expand-VariablesInString {
    [cmdletBinding()]
    Param(
        [Parameter(Mandatory=$True
                    ,ValueFromPipeline=$True)]
        [string]$Inputstring,

        [Parameter(Mandatory=$True)]
        [hashtable]$VariableMappings
    )

    foreach($key in $Variablemappings.Keys) {

        $InputString = $Inputstring.Replace("%"+$key+"%",$VariableMappings[$key])
    }

    return $Inputstring
}



