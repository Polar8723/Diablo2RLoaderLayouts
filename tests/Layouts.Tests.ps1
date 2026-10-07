$LoadLayoutFunctions = {
# Load function definitions only: never run launcher initialization, elevation or games.
$LoaderPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'D2Loader.ps1'
$Tokens = $Null
$ParseErrors = $Null
$LoaderAst = [System.Management.Automation.Language.Parser]::ParseFile($LoaderPath, [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count){throw ($ParseErrors.Message -join "`n")}
$LoaderAst.FindAll({param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $False) |
	ForEach-Object {. ([scriptblock]::Create($_.Extent.Text))}

}
Describe 'Saved layouts' {
	if ((Get-Module Pester).Version.Major -ge 5){BeforeAll $LoadLayoutFunctions}else{. $LoadLayoutFunctions}
	BeforeEach {
function AssertLayoutValue {
    param([Parameter(ValueFromPipeline=$True)]$Actual, $Expected)
    process {if ($Actual -ne $Expected){throw "Expected '$Expected', got '$Actual'."}}
}
		$Script:WorkingDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
		$Null = New-Item -ItemType Directory -Path $Script:WorkingDirectory
		$Script:SettingsProfilePath = Join-Path $Script:WorkingDirectory 'settings'
		$Null = New-Item -ItemType Directory -Path $Script:SettingsProfilePath -Force
		Set-Content -LiteralPath (Join-Path $Script:SettingsProfilePath 'Settings.json') -Value '{"profile":"current"}'
		Set-Content -LiteralPath (Join-Path $Script:SettingsProfilePath 'Settings1.json') -Value '{"profile":"one"}'
		Set-Content -LiteralPath (Join-Path $Script:SettingsProfilePath 'Settings2.json') -Value '{"profile":"two"}'
		Set-Content -LiteralPath (Join-Path $Script:SettingsProfilePath 'Settings.manual1.json') -Value '{"profile":"manual"}'
		Set-Content -LiteralPath (Join-Path $Script:SettingsProfilePath 'unrelated.json') -Value '{}'
		$Script:Config = [pscustomobject]@{DefaultRegion='2'; GamePath=$TestDrive; LayoutModeEnabled='True'}
		$Script:AccountOptionsCSV = @(
			[pscustomobject]@{ID='1'; AccountLabel='First'; CustomLaunchArguments=''; AuthenticationMethod='Parameter'},
			[pscustomobject]@{ID='2'; AccountLabel='Second'; CustomLaunchArguments=''; AuthenticationMethod='Token'}
		)
		$Script:AccountOptionsCSV | Export-Csv -LiteralPath (Join-Path $Script:WorkingDirectory 'Accounts.csv') -NoTypeInformation
		$Script:ActiveAccountsList = @()
		$Script:OpenBatches = $False
		$Script:OpenAllAccounts = $False
		$Script:AccountID = 'original'
		$Script:Region = 'original-region'
		$Script:LayoutEntry = $Null
		$Script:Launches = @()
		$Script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
		$Script:Rows = @(
			[pscustomobject]@{LayoutId='1'; LayoutName='Two windows'; WindowIndex=2; AccountId='2'; WindowXCoordinates=100; WindowYCoordinates=200; WindowHeight=600; WindowWidth=800; SettingFile='Settings.json'; LaunchRegion='Asia'},
			[pscustomobject]@{LayoutId='1'; LayoutName='Two windows'; WindowIndex=1; AccountId='1'; WindowXCoordinates=-800; WindowYCoordinates=-10; WindowHeight=600; WindowWidth=800; SettingFile='Settings1.json'; LaunchRegion='Europe'}
		)
		Mock CheckActiveAccounts {}
		Mock PressTheAnyKey {}
		Mock Read-Host {if ($Script:Answers.Count){$Script:Answers.Dequeue()}else{''}}
		Mock ReadLayoutWindowBounds {[pscustomobject]@{WindowXCoordinates=-800; WindowYCoordinates=20; WindowHeight=600; WindowWidth=800}}
		Mock Processing {
			[System.IO.File]::WriteAllBytes($Script:LayoutSettingsPath, $Script:LayoutSettingsContent)
			$Script:Launches += [pscustomobject]@{AccountId=$Script:AccountID; Region=$Script:Region; Label=$Script:RegionLabel;
				Bounds=$Script:LayoutEntry; Content=(Get-Content -LiteralPath $Script:LayoutSettingsPath -Raw | ConvertFrom-Json).profile}
			$Script:LayoutLaunchSucceeded = $True
		}
	}

	It 'disables the layout menu when the optional setting is absent or false' {
		Mock ReadKeyTimeout {throw 'Disabled menu must not prompt'}
		$Script:Config = [pscustomobject]@{}
		LayoutMenu
		$Script:Config = [pscustomobject]@{LayoutModeEnabled='False'}
		LayoutMenu
		Assert-MockCalled ReadKeyTimeout -Times 0 -Exactly -Scope It
	}
	It 'offers current, numbered and manual settings files only' {
		$Files = @(GetLayoutSettingsFiles -Account $Script:AccountOptionsCSV[0])
		($Files.Name -join ',') | AssertLayoutValue -Expected 'Settings.json,Settings1.json,Settings2.json,Settings.manual1.json'
	}
	It 'returns no layouts when the file does not exist' {
		@(ReadLayouts).Count | AssertLayoutValue -Expected 0
	}
	It 'does not save when no windows are open' {
		SaveLayout
		Test-Path (Join-Path $Script:WorkingDirectory 'layouts.csv') | AssertLayoutValue -Expected $False
		Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
	}
	It 'saves all window fields, uses the default region and appends distinct layouts' {
		$Script:ActiveAccountsList = @([pscustomobject]@{ID='1'; ProcessID=123},[pscustomobject]@{ID='2'; ProcessID=456})
		foreach ($Answer in @('Name, with comma','2','','4','3')){$Script:Answers.Enqueue($Answer)}
		SaveLayout
		$Saved = @(ReadLayouts)
		$Saved.Count | AssertLayoutValue -Expected 2
		$Saved[0].LayoutId | AssertLayoutValue -Expected '1'
		$Saved[1].LayoutId | AssertLayoutValue -Expected '1'
		$Saved[0].LayoutName | AssertLayoutValue -Expected 'Name, with comma'
		$Saved[0].WindowXCoordinates | AssertLayoutValue -Expected '-800'
		$Saved[0].WindowYCoordinates | AssertLayoutValue -Expected '20'
		$Saved[0].WindowWidth | AssertLayoutValue -Expected '800'
		$Saved[0].WindowHeight | AssertLayoutValue -Expected '600'
		$Saved[0].SettingFile | AssertLayoutValue -Expected 'Settings1.json'
		$Saved[0].LaunchRegion | AssertLayoutValue -Expected 'Europe'
		$Saved[1].SettingFile | AssertLayoutValue -Expected 'Settings.manual1.json'
		$Saved[1].LaunchRegion | AssertLayoutValue -Expected 'Asia'
		foreach ($Answer in @('Name, with comma','1','1','1','2')){$Script:Answers.Enqueue($Answer)}
		SaveLayout
		$Saved = @(ReadLayouts)
		$Saved.Count | AssertLayoutValue -Expected 4
		$Saved[2].LayoutId | AssertLayoutValue -Expected '2'
		@($Saved.LayoutId | Select-Object -Unique).Count | AssertLayoutValue -Expected 2
	}
	It 'does not write a partial layout if a window cannot be read' {
		$Script:ActiveAccountsList = @([pscustomobject]@{ID='1'; ProcessID=123},[pscustomobject]@{ID='2'; ProcessID=456})
		Mock ReadLayoutWindowBounds {throw 'Window closed'} -ParameterFilter {$ProcessId -eq 456}
		foreach ($Answer in @('Incomplete','1','2')){$Script:Answers.Enqueue($Answer)}
		SaveLayout
		Test-Path (Join-Path $Script:WorkingDirectory 'layouts.csv') | AssertLayoutValue -Expected $False
	}
	It 'accepts c as the layout name instead of cancelling setup' {
		$Script:ActiveAccountsList = @([pscustomobject]@{ID='1'; ProcessID=123})
		foreach ($Answer in @('c','1','2')){$Script:Answers.Enqueue($Answer)}
		SaveLayout
		$Saved = @(ReadLayouts)
		$Saved.Count | AssertLayoutValue -Expected 1
		$Saved[0].LayoutName | AssertLayoutValue -Expected 'c'
	}
	It 'launches in saved order and preserves current settings before any copies' {
		InvokeSavedLayout -Rows $Script:Rows
		($Script:Launches.AccountId -join ',') | AssertLayoutValue -Expected '1,2'
		$Script:Launches[0].Region | AssertLayoutValue -Expected 'eu.actual.battle.net'
		$Script:Launches[0].Label | AssertLayoutValue -Expected 'EU'
		$Script:Launches[1].Region | AssertLayoutValue -Expected 'kr.actual.battle.net'
		$Script:Launches[0].Bounds.WindowXCoordinates | AssertLayoutValue -Expected -800
		$Script:Launches[0].Content | AssertLayoutValue -Expected 'one'
		$Script:Launches[1].Content | AssertLayoutValue -Expected 'current'
		$Script:AccountID | AssertLayoutValue -Expected 'original'
		$Script:Region | AssertLayoutValue -Expected 'original-region'
		$Script:OpenBatches | AssertLayoutValue -Expected $False
		($Null -eq $Script:LayoutEntry) | AssertLayoutValue -Expected $True
		Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
	}
	It 'rejects a missing settings file before launching any windows' {
		$Script:Rows[0].SettingFile = 'Settings.missing.json'
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
	It 'rejects a missing account before launching any windows' {
		$Script:Rows[0].AccountId = '99'
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
	It 'rejects invalid dimensions and duplicate window indices' {
		$Script:Rows[0].WindowWidth = 0
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		$Script:Rows[0].WindowWidth = 800
		$Script:Rows[0].WindowIndex = 1
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
	It 'rejects accounts already open before launching any windows' {
		$Script:ActiveAccountsList = @([pscustomobject]@{ID='2'; ProcessID=456})
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
	It 'stops subsequent launches and restores state when a launch fails' {
		Mock Processing {$Script:LayoutLaunchSucceeded = $False}
		$Failure = try {InvokeSavedLayout -Rows $Script:Rows; $False} catch {$True}
		$Failure | AssertLayoutValue -Expected $True
		Assert-MockCalled Processing -Times 1 -Exactly -Scope It
		$Script:AccountID | AssertLayoutValue -Expected 'original'
		$Script:Region | AssertLayoutValue -Expected 'original-region'
		$Script:OpenBatches | AssertLayoutValue -Expected $False
	}
	It 'launches subsequent windows automatically without consuming input' {
		$Script:Answers.Enqueue('c')
		InvokeSavedLayout -Rows $Script:Rows
		Assert-MockCalled Processing -Times 2 -Exactly -Scope It
		Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
		$Script:Answers.Count | AssertLayoutValue -Expected 1
		$Script:AccountID | AssertLayoutValue -Expected 'original'
	}
	It 'uses a mod custom save folder when choosing settings' {
		$ModFolder = Join-Path $TestDrive 'Mods/example/example.mpq'
		$Null = New-Item -ItemType Directory -Path $ModFolder -Force
		Set-Content -LiteralPath (Join-Path $ModFolder 'Modinfo.json') -Value '{"savepath":"custom/"}'
		$ModSettings = Join-Path $Script:SettingsProfilePath 'mods/custom'
		$Null = New-Item -ItemType Directory -Path $ModSettings -Force
		Set-Content -LiteralPath (Join-Path $ModSettings 'Settings.json') -Value '{}'
		$Script:AccountOptionsCSV[0].CustomLaunchArguments = '-mod example -txt'
		@(GetLayoutSettingsFiles -Account $Script:AccountOptionsCSV[0]).Count | AssertLayoutValue -Expected 1
		(GetLayoutSettingsPath -Account $Script:AccountOptionsCSV[0]) | AssertLayoutValue -Expected $ModSettings
	}
	It 'launches only the requested layout without menu prompts' {
		$Other = [pscustomobject]@{LayoutId='2'; LayoutName='Other'; WindowIndex=1; AccountId='99'; WindowXCoordinates=0; WindowYCoordinates=0; WindowHeight=600; WindowWidth=800; SettingFile='Settings.missing.json'; LaunchRegion='Americas'}
		@($Script:Rows + $Other) | Export-Csv -LiteralPath (Join-Path $Script:WorkingDirectory 'layouts.csv') -NoTypeInformation
		LaunchLayoutParameter -LayoutId '1'
		($Script:Launches.AccountId -join ',') | AssertLayoutValue -Expected '1,2'
		Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
		Assert-MockCalled PressTheAnyKey -Times 0 -Exactly -Scope It
	}
	It 'rejects a missing command-line layout without prompting or launching' {
		$Script:Rows | Export-Csv -LiteralPath (Join-Path $Script:WorkingDirectory 'layouts.csv') -NoTypeInformation
		$Message = try {LaunchLayoutParameter -LayoutId '99'; ''} catch {$_.Exception.Message}
		$Message | AssertLayoutValue -Expected "Layout '99' was not found in layouts.csv."
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
		Assert-MockCalled PressTheAnyKey -Times 0 -Exactly -Scope It
	}
	It 'requires layout mode for command-line launching including older configs' {
		$Script:Rows | Export-Csv -LiteralPath (Join-Path $Script:WorkingDirectory 'layouts.csv') -NoTypeInformation
		foreach ($Configuration in @([pscustomobject]@{}, [pscustomobject]@{LayoutModeEnabled='False'})){
			$Script:Config = $Configuration
			$Message = try {LaunchLayoutParameter -LayoutId '1'; ''} catch {$_.Exception.Message}
			$Message | AssertLayoutValue -Expected 'Enable LayoutModeEnabled in config.xml before using -layout.'
		}
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
	It 'allocates above the highest existing ID even when there are gaps' {
		GetNextLayoutId -Rows @() | AssertLayoutValue -Expected 1
		GetNextLayoutId -Rows @([pscustomobject]@{LayoutId='9'},[pscustomobject]@{LayoutId='2'},[pscustomobject]@{LayoutId='9'}) | AssertLayoutValue -Expected 10
	}
	It 'uses the actual numeric ID in the layout menu when IDs have gaps' {
		$Script:Rows[0].LayoutId = '5'
		$Script:Rows[1].LayoutId = '5'
		$Script:Rows | Export-Csv -LiteralPath (Join-Path $Script:WorkingDirectory 'layouts.csv') -NoTypeInformation
		$Script:Answers.Enqueue('5')
		LoadLayout
		Assert-MockCalled Processing -Times 2 -Exactly -Scope It
		Assert-MockCalled PressTheAnyKey -Times 0 -Exactly -Scope It
	}
	It 'rejects nonnumeric command-line layout IDs' {
		foreach ($Id in @('0','-1','abc','12345678-1234-1234-1234-123456789abc')){
			$Message = try {LaunchLayoutParameter -LayoutId $Id; ''} catch {$_.Exception.Message}
			$Message | AssertLayoutValue -Expected 'Use a positive numeric layout ID with -layout.'
		}
		Assert-MockCalled Processing -Times 0 -Exactly -Scope It
	}
}
