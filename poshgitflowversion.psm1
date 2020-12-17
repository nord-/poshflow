$m = "master"
$d = "develop"
$h = "hotfix"
$r = "release"
$f = "feature"

Function Pause ($Message = "Press any key to continue . . . ") {
    If ($psISE) {
        # The "ReadKey" functionality is not supported in Windows PowerShell ISE.
 
        $Shell = New-Object -ComObject "WScript.Shell"
        $Button = $Shell.Popup("Click OK to continue.", 0, "Script Paused", 0)
 
        Return
    }
 
    Write-Host -NoNewline $Message
 
    $Ignore =
        16,  # Shift (left or right)
        17,  # Ctrl (left or right)
        18,  # Alt (left or right)
        20,  # Caps lock
        91,  # Windows key (left)
        92,  # Windows key (right)
        93,  # Menu key
        144, # Num lock
        145, # Scroll lock
        166, # Back
        167, # Forward
        168, # Refresh
        169, # Stop
        170, # Search
        171, # Favorites
        172, # Start/Home
        173, # Mute
        174, # Volume Down
        175, # Volume Up
        176, # Next Track
        177, # Previous Track
        178, # Stop Media
        179, # Play
        180, # Mail
        181, # Select Media
        182, # Application 1
        183  # Application 2
 
    While ($KeyInfo.VirtualKeyCode -Eq $Null -Or $Ignore -Contains $KeyInfo.VirtualKeyCode) {
        $KeyInfo = $Host.UI.RawUI.ReadKey("NoEcho, IncludeKeyDown")
    }
 
    Write-Host
}

function Set-Branch {
    [cmdletbinding()]
    param(
        [parameter(ValueFromPipeline)]$name
    )
    process {
        Write-Host "git checkout $name" -ForegroundColor Green
        git checkout -q $name
        git pull --rebase -q
    }
}

function Remove-Branch {
    [cmdletbinding()]
    param(
        [parameter(ValueFromPipeline)]$name,
        [switch]$force
    )
    process {
        if ($force) {
            Write-Host "git branch -D $name" -ForegroundColor Green
            git branch -D $name
        }
        else {
            Write-Host "git branch -d $name" -ForegroundColor Green
            git branch -d $name
        }
    }
}

function Update-BranchFrom {
    <#
    .SYNOPSIS
    Updates the current branching using either a rebase or merge strategy
    .DESCRIPTION
    Updates the current branching using either a rebase or merge strategy
    .EXAMPLE
    Update-BranchFrom $d -rebase
    .EXAMPLE
    Update-BranchFrom $d -merge
    .EXAMPLE
    Update-BranchFrom $d -merge -noff
    .PARAMETER branch
    The source branch on where to rebase or merge from
    .PARAMETER rebase
    Sets the update strategy using git rebase
    .PARAMETER merge
    Sets the update strategy using git merge
    #>
    [cmdletbinding()]
    param(
        [Parameter(Position = 0)]$branch,
        [Parameter(ParameterSetName = "rebase", Position = 1)][switch]$rebase,
        [Parameter(ParameterSetName = "merge", Position = 1)][switch]$merge,
        [Parameter(ParameterSetName = "merge", Position = 2)][switch]$noff
    )
    process {
        if ($branch -eq $null) {
            $names = $currentBranch -split "/"
            if ($names[0] -eq $h) {
                $branch = $m
            } elseif ($names[0] -eq $f) {
                $branch = $d
            } elseif ($names[0] -eq $r) {
                $branch = $d
            } else {
                Write-Host "You need to provide a branch name to update from, or be in feature-, release- or hotfix-branch."
                return
            }
        }

        Write-Host "git fetch latest"
        git fetch origin $branch`:$branch

        if ($rebase) {
            Write-Host "git rebase $branch" -ForegroundColor Green
            git rebase $branch
        }
        else {
            if ($noff) {
                Write-Host "git merge --no-ff $branch" -ForegroundColor Green
                git merge --no-ff $branch
            }
            else {
                Write-Host "git merge $branch" -ForegroundColor Green
                git merge $branch
            }
        }
    }
}

function New-Tag  {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory=$true)]$tag
    )
    process {
        Write-Host "git tag -a v$tag -m version v$tag" -ForegroundColor Green
        git tag -a "v$tag" -m "version v$tag" --force
    }
}

function Resume-Rebase {
        git add -A
        git rebase --continue
}

function Start-Feature { 
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$true)]$name
    )
    process {
        Write-Host "Starting new feature $name" -ForegroundColor Green
        $name = $name -replace "$f/", ""
        git checkout -q -b "$f/$name" $d
        return $name
    }
}

function Start-HotFix {
    process {
        Set-Branch $m
        try {
            $version = (gitversion /verbosity Quiet /nofetch /output json | convertFrom-json)
        } catch {
            return
        }
        $major = [int]$version.Major
        $minor = [int]$version.Minor
        $patch = [int]$version.Patch + 1
        $name = "$h/$major`.$minor`.$patch"

        Write-Host "Starting new $name" -ForegroundColor Green
        git checkout -q -b $name $m

        return "$h/$major`.$minor`.$patch"
    }
}

function Complete-HotFix {
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false)]$hotfixBranch
    )
    process { 
        if ($hotfixBranch -eq $null) {
            $currentBranch = (git branch --show-current)
            $names = $currentBranch -split "/"
            if ($names[0] -eq $h) {
                $hotfixBranch = $currentBranch
            }
        } elseif (($hotfixBranch -split "/")[1] -eq $null) {
            $hotfixBranch = "$h/$hotfixBranch" 
        }

        Set-Branch $m
        Update-BranchFrom $hotfixBranch -merge -noff
        Remove-Branch $hotfixBranch
        $tag = ($hotfixBranch -split "/")[1]
        New-Tag $tag

        Write-Host "Will push..."
        Pause
        Write-Host "Continuing..."
        #git push --follow-tags
    }
}

function Start-Release {
    [cmdletbinding()]
    param
    (
        [Parameter(Mandatory=$false)][switch]$majorVersion,
        [Parameter(Mandatory=$false)][switch]$useDate
    )
    process { 
        Set-Branch $d
        try {
            $version = (gitversion /verbosity Quiet /nofetch /output json | convertFrom-json)
        } catch {
            return
        }

        
        if ($useDate) {
            $tday = Get-Date
            $major = "{0}{1:00}" -f $tday.Year,$tday.Month
            $minor = $tday.Day
            $patch = 0
        } else {
            if($majorVersion) {
                $major = [int]$version.Major + 1
                $minor = 0
                $patch = 0
            } else {
                $major = [int]$version.Major
                $minor = [int]$version.Minor
                $patch = [int]$version.Patch
            }
        }
        $name = "$r/$major`.$minor`.$patch"

        Write-Host "Starting new $name" -ForegroundColor Green
        git checkout -q -b $name $d

        return $name;
    }
}

function Complete-Release {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$false)]$releaseBranch
    ) 
    process { 
        if ($releaseBranch -eq $null) {
            $currentBranch = (git branch --show-current)
            $names = $currentBranch -split "/"
            if ($names[0] -eq $r) {
                $releaseBranch = $currentBranch
            }
        }

        Set-Branch $m

        $name = ($releaseBranch -split "/")[1]
        if ($name -eq $null) {
            $name = $releaseBranch
            $releaseBranch = "$r/$releaseBranch"
        }

        Update-BranchFrom $releaseBranch -merge -noff
        New-Tag $name

        Set-Branch $d
        Update-BranchFrom $m -merge
        Remove-Branch $releaseBranch

        Write-Host "Will push all..."
        Pause
        Write-Host "Continuing..."
        #git push --all --follow-tags
    }
}

Export-ModuleMember -Variable *
Export-ModuleMember -Function Complete-HotFix,Complete-Release,New-Tag,Remove-Branch,Reset-Repo,Resume-Rebase,Set-Branch,Start-Feature,Start-HotFix,Start-Release,Test-Rebase,Update-BranchFrom
