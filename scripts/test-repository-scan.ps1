[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$validatorPath = Join-Path $PSScriptRoot 'validate-repo.ps1'
$validator = Get-Content -LiteralPath $validatorPath -Raw
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($validator, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Repository validator syntax is invalid.' }

# Execute the validator's actual file-selection section with a temporary root;
# do not invoke the remaining build checks or read the working repository.
$rootAssignment = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$repoRoot'
}, $false)
$rulesAssignment = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$rules'
}, $false)
if (-not $rootAssignment -or -not $rulesAssignment) { throw 'Unable to locate repository file-selection section.' }
$selection = $validator.Substring($rootAssignment.Extent.EndOffset, $rulesAssignment.Extent.StartOffset - $rootAssignment.Extent.EndOffset)
$selectFiles = [scriptblock]::Create('param([string]$repoRoot)' + "`n" + $selection + "`n" + '$files')

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $temporaryRoot ('proxy-scan-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
try {
    & git -C $fixtureRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize the temporary Git fixture.' }
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot '中文 路径') | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureRoot '.env') -Value 'tracked fixture' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fixtureRoot '中文 路径/已跟踪 文件.txt') -Value 'tracked fixture' -Encoding utf8
    & git -C $fixtureRoot add -- .env '中文 路径/已跟踪 文件.txt'
    if ($LASTEXITCODE -ne 0) { throw 'Unable to track the fixture files.' }

    # The ignore rules are introduced after tracking: they must not exempt
    # either tracked file, including the legacy .env special case.
    Set-Content -LiteralPath (Join-Path $fixtureRoot '.gitignore') -Value @('.env', 'ignored backup/', '中文 路径/已跟踪 文件.txt') -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $fixtureRoot 'ignored backup') | Out-Null
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'ignored backup/私有 订阅.txt') -Value 'ignored fixture' -Encoding utf8
    Set-Content -LiteralPath (Join-Path $fixtureRoot '中文 路径/普通 新文件.txt') -Value 'untracked fixture' -Encoding utf8

    $actual = @(& $selectFiles $fixtureRoot | ForEach-Object {
        [IO.Path]::GetRelativePath($fixtureRoot, $_.FullName).Replace('\', '/')
    })
    if ('ignored backup/私有 订阅.txt' -cin $actual) { throw 'Ignored untracked files must not enter the repository scan.' }
    foreach ($expected in @('.gitignore', '.env', '中文 路径/已跟踪 文件.txt', '中文 路径/普通 新文件.txt')) {
        if ($expected -cnotin $actual) { throw "Repository scan missed required fixture path: $expected" }
    }
    if ($actual.Count -ne 4) { throw 'Repository scan included unexpected or duplicate fixture paths.' }
    Write-Output 'Repository scan tests passed: ignored untracked excluded; ordinary untracked and tracked-later-ignored included; Chinese and spaced paths preserved.'
}
finally {
    $resolvedFixture = (Resolve-Path -LiteralPath $fixtureRoot).Path
    $tempPrefix = $temporaryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture -cne [IO.Path]::GetFullPath($fixtureRoot) -or
        -not $resolvedFixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($resolvedFixture) -notmatch '^proxy-scan-[a-f0-9]{32}$') {
        throw 'Refusing to remove a fixture outside its validated temporary directory.'
    }
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
}
