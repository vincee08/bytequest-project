param([string]$ExpectedCertificateSha256 = 'dc85ef75a3a7adf3429cfa8c23cf460bea6a78ef0ebfa0c6d0e080e8d67e0d68')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $repo 'ByteQuest-Mobile-App/build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path -LiteralPath $apk)) { throw 'A completed release APK is required.' }
$buildTools = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Android/Sdk/build-tools') -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } | Sort-Object Name -Descending | Select-Object -First 1
if (-not $buildTools) { throw 'Android build tools are required.' }
function Native-Output($binary, $arguments) {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $result = & $binary @arguments 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    if ($code -ne 0) { throw 'Android artifact verification command failed.' }
    return ($result -join "`n")
}
$signature = Native-Output (Join-Path $buildTools.FullName 'apksigner.bat') @('verify', '--verbose', '--print-certs', $apk)
$certMatch = [regex]::Match($signature, '(?im)^Signer #1 certificate SHA-256 digest:\s*([0-9a-f]{64})')
if (-not $certMatch.Success -or $certMatch.Groups[1].Value.ToLowerInvariant() -ne $ExpectedCertificateSha256.ToLowerInvariant()) { throw 'The APK is not signed by the approved production certificate.' }
if ($signature -notmatch 'Number of signers: 1') { throw 'Unexpected APK signer count.' }
$badging = Native-Output (Join-Path $buildTools.FullName 'aapt.exe') @('dump', 'badging', $apk)
$packageMatch = [regex]::Match($badging, '(?m)^package: name=''([^'']+)'' versionCode=''([^'']+)'' versionName=''([^'']+)''')
$version = [regex]::Match([IO.File]::ReadAllText((Join-Path $repo 'ByteQuest-Mobile-App/pubspec.yaml')), '(?m)^version:\s*([^+\s]+)\+(\d+)')
if (-not $packageMatch.Success -or $packageMatch.Groups[1].Value -ne 'com.example.bytequest' -or $packageMatch.Groups[2].Value -ne $version.Groups[2].Value -or $packageMatch.Groups[3].Value -ne $version.Groups[1].Value) { throw 'APK package or version does not match the approved Flutter configuration.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($apk)
try {
    $entry = $zip.GetEntry('assets/flutter_assets/.env')
    if (-not $entry -or $entry.Length -gt 32768) { throw 'Expected small public mobile environment asset is missing.' }
    $reader = New-Object IO.StreamReader($entry.Open())
    try { $asset = $reader.ReadToEnd() } finally { $reader.Dispose() }
    $public = @{}
    foreach ($line in ($asset -split "`n")) {
        if ($line -match '^\s*([A-Z0-9_]+)\s*=\s*(.*)$') { $public[$matches[1]] = $matches[2].Trim().Trim([char[]]@([char]34,[char]39)) }
    }
    if (@($public.Keys | Where-Object { $_ -match 'SERVICE|SECRET|PASSWORD|TOKEN|OPENROUTER|PRIVATE' }).Count) { throw 'A server-only setting was packaged in the mobile environment.' }
    if ($public.SUPABASE_URL -ne 'https://rslmteqipxqfifwftugk.supabase.co' -or ([uri]$public.PRACTICE_API_URL).GetLeftPart([UriPartial]::Authority) -ne 'https://bytequest-alpha.vercel.app') { throw 'APK production endpoints do not match ByteQuest.' }
    $key = $public.SUPABASE_ANON_KEY
    if (-not $key.StartsWith('sb_publishable_')) {
        $payload = $key.Split('.')[1].Replace('-','+').Replace('_','/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        if ($claims.role -ne 'anon') { throw 'A privileged mobile key was rejected.' }
    }
} finally { $zip.Dispose() }
$report = [ordered]@{result='PASS'; artifact=$apk; bytes=(Get-Item -LiteralPath $apk).Length; sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant(); package=$packageMatch.Groups[1].Value; versionName=$packageMatch.Groups[3].Value; versionCode=[int]$packageMatch.Groups[2].Value; certificate_sha256=$certMatch.Groups[1].Value.ToLowerInvariant(); production_endpoints_verified=$true; client_environment_has_server_secrets=$false; distributed=$false; owner_installation_modified=$false}
$json = $report | ConvertTo-Json
$out = Join-Path $repo '.tmp/release-20261113/android-artifact-verification.json'
[IO.File]::WriteAllText($out, $json)
Write-Output $json
