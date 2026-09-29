param(
    [string]$Device = 'emulator-5554',
    [string]$Flutter = 'C:\Users\HP\Tools\flutter\bin\flutter.bat',
    [string]$Adb = 'C:\Users\HP\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    [string]$Supabase = '',
    [string]$Mission = ''
)
$ErrorActionPreference = 'Stop'
$bqRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $bqRoot
$bqUser = $null
$bqOriginalWindows = $env:FLUTTER_WINDOWS
try {
    # Windows PowerShell maps native stderr warnings to error records. Use the
    # process exit code for CLI failures; retain terminating errors for HTTP.
    $ErrorActionPreference = 'Continue'
    $bqLocalJson = if ($Supabase) { & $Supabase status -o json } else { npx --offline --no-install supabase status -o json }
    $bqStatusExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($bqStatusExit -ne 0) { throw 'Local Supabase is unavailable.' }
    $bqLocal = $bqLocalJson | ConvertFrom-Json
    $bqEndpoint = [uri]$bqLocal.API_URL
    if ($bqEndpoint.Host -notin @('localhost', '127.0.0.1') -or $bqEndpoint.Port -ne 57321) {
        throw 'Refusing to run fixture creation against a non-local backend.'
    }
    $bqHeaders = @{ apikey = $bqLocal.SERVICE_ROLE_KEY; Authorization = "Bearer $($bqLocal.SERVICE_ROLE_KEY)" }
    $bqRun = [guid]::NewGuid().ToString('N')
    $bqEmail = "android-runtime-$bqRun@bytequest.invalid"
    $bqPassword = [guid]::NewGuid().ToString('N') + 'aA9!'
    $bqUser = Invoke-RestMethod -Method Post -Uri "$($bqLocal.API_URL)/auth/v1/admin/users" -Headers $bqHeaders -ContentType 'application/json' -Body (@{
        email = $bqEmail; password = $bqPassword; email_confirm = $true
        user_metadata = @{ full_name = 'Disposable Android Runtime QA'; bytequest_test_account = $true; bytequest_test_run = $bqRun }
    } | ConvertTo-Json)
    Invoke-RestMethod -Method Patch -Uri "$($bqLocal.API_URL)/rest/v1/profiles?user_id=eq.$($bqUser.id)" -Headers $bqHeaders -ContentType 'application/json' -Body '{"role":"learner","status":"active"}' | Out-Null
    Set-Location (Join-Path $bqRoot 'ByteQuest-Mobile-App')
    # Android is the target. Avoid changing global Windows Developer Mode just
    # to create unused desktop-plugin symlinks on this test runner.
    $env:FLUTTER_WINDOWS = 'false'
    foreach ($bqStage in @('save', 'resume')) {
        # Keep the installed package between invocations so the second stage
        # is a genuine force-stop/relaunch, not an uninstall that erases app
        # SharedPreferences before restoration can be verified.
        $bqArguments = @('test', 'integration_test/mission_runtime_local_e2e_test.dart', '-d', $Device, '--no-uninstall',
            "--dart-define=BQ_E2E_STAGE=$bqStage", '--dart-define=BQ_E2E_URL=http://10.0.2.2:57321',
            "--dart-define=BQ_E2E_ANON_KEY=$($bqLocal.ANON_KEY)",
            "--dart-define=BQ_E2E_EMAIL=$bqEmail", "--dart-define=BQ_E2E_PASSWORD=$bqPassword")
        if ($Mission) { $bqArguments += "--dart-define=BQ_E2E_MISSION=$Mission" }
        $ErrorActionPreference = 'Continue'
        & $Flutter @bqArguments
        $bqFlutterExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($bqFlutterExit -ne 0) { throw "Android $bqStage stage failed." }
        & $Adb -s $Device shell am force-stop com.example.bytequest
        if ($LASTEXITCODE -ne 0) { throw 'Could not terminate the app between persistence stages.' }
    }
    if ($Mission) {
        Write-Output "PASS: $Mission real-UI save checkpoint and process-restart completion workflow."
    } else {
        Write-Output 'PASS: 20 real-UI save checkpoints and 20 process-restart completion workflows.'
    }
} finally {
    if ($null -ne $bqUser) {
        # Preserve append-only evidence while disabling this exact fixture.
        Invoke-RestMethod -Method Patch -Uri "$($bqLocal.API_URL)/rest/v1/profiles?user_id=eq.$($bqUser.id)" -Headers $bqHeaders -ContentType 'application/json' -Body (@{
            status = 'deactivated'; deactivated_at = [DateTime]::UtcNow.ToString('o')
            deactivation_reason = 'Disposable Android QA fixture retired'
        } | ConvertTo-Json) | Out-Null
        Invoke-RestMethod -Method Put -Uri "$($bqLocal.API_URL)/auth/v1/admin/users/$($bqUser.id)" -Headers $bqHeaders -ContentType 'application/json' -Body '{"ban_duration":"876000h"}' | Out-Null
    }
    $env:FLUTTER_WINDOWS = $bqOriginalWindows
    Pop-Location
}
