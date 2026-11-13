param([switch]$CreateFirstProductionKey)
$ErrorActionPreference = 'Stop'
if (-not $CreateFirstProductionKey) { throw 'Explicit first-key authorization is required.' }
$repo = Split-Path -Parent $PSScriptRoot
$properties = Join-Path $repo 'ByteQuest-Mobile-App/android/key.properties'
$privateDir = Join-Path $env:LOCALAPPDATA 'ByteQuest/Signing/production-20261113'
$keystore = Join-Path $privateDir 'bytequest-production.p12'
$keytool = 'C:/Users/HP/Documents/Tools/jdk-17.0.20.1+1/bin/keytool.exe'
if ((Test-Path -LiteralPath $properties) -or (Test-Path -LiteralPath $keystore)) { throw 'Signing material already exists; inspect it without replacing it.' }
if (-not (Test-Path -LiteralPath $keytool)) { throw 'A supported JDK keytool is required.' }
$ignored = & git -C $repo check-ignore --no-index 'ByteQuest-Mobile-App/android/key.properties'
if ($LASTEXITCODE -ne 0 -or -not $ignored) { throw 'Private signing configuration must be Git ignored.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
function Protect-OwnerOnly($path, $directory) {
    $grant = if ($directory) { "*$($identity.Value):(OI)(CI)F" } else { "*$($identity.Value):F" }
    & icacls $path /inheritance:r /grant:r $grant | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not restrict private signing permissions.' }
    foreach ($entry in @((Get-Acl -LiteralPath $path).Access)) {
        $sid = $entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($sid -ne $identity.Value) {
            & icacls $path /remove:g "*$sid" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw 'Could not remove inherited signing access.' }
        }
    }
    if (@((Get-Acl -LiteralPath $path).Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -ne $identity.Value }).Count) { throw 'Signing ACL verification failed.' }
}
[IO.Directory]::CreateDirectory($privateDir) | Out-Null
Protect-OwnerOnly $privateDir $true
$bytes = New-Object byte[] 48
$random = [Security.Cryptography.RandomNumberGenerator]::Create()
$random.GetBytes($bytes)
$password = [Convert]::ToBase64String($bytes)
$oldStore = $env:BYTEQUEST_RELEASE_STORE_PASSWORD
try {
    $env:BYTEQUEST_RELEASE_STORE_PASSWORD = $password
    $credentialFile = Join-Path $privateDir 'signing-credentials.txt'
    [IO.File]::WriteAllText($credentialFile, "ByteQuest first production signing identity`r`nPackage: com.example.bytequest`r`nAlias: bytequest-release`r`nKeystore: $keystore`r`nStore/key password: $password`r`nKeep an encrypted offline backup of this entire directory. Future updates MUST use this key. Never send it in chat or commit it.`r`nThis key cannot update a debug-signed installation; no existing app was changed.`r`n")
    # keytool writes normal progress to stderr; Windows PowerShell must not turn it into a terminating exception.
    $ErrorActionPreference = 'Continue'
    $result = & $keytool -genkeypair -keystore $keystore -storetype PKCS12 -alias bytequest-release -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=ByteQuest Android Release,O=ByteQuest,C=PH' -storepass:env BYTEQUEST_RELEASE_STORE_PASSWORD -keypass:env BYTEQUEST_RELEASE_STORE_PASSWORD 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Private key generation failed. Inspect the private directory locally.' }
    $certificate = Join-Path $privateDir 'bytequest-production.cer'
    $ErrorActionPreference = 'Continue'
    $result = & $keytool -exportcert -keystore $keystore -alias bytequest-release -storepass:env BYTEQUEST_RELEASE_STORE_PASSWORD -file $certificate 2>&1
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed.' }
    [IO.File]::WriteAllText($properties, '')
    Protect-OwnerOnly $properties $false
    [IO.File]::WriteAllText($properties, "storeFile=$($keystore.Replace('\','/'))`nstorePassword=$password`nkeyAlias=bytequest-release`nkeyPassword=$password`n")
    $fingerprint = (Get-FileHash -LiteralPath $certificate -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $privateDir 'certificate-sha256.txt'), $fingerprint)
    Write-Output "PASS first production key created; owner-only private directory: $privateDir"
    Write-Output "Certificate SHA-256: $fingerprint"
    Write-Output 'No application was installed or removed.'
} finally {
    $env:BYTEQUEST_RELEASE_STORE_PASSWORD = $oldStore
    $password = $null
    $random.Dispose()
    [Array]::Clear($bytes, 0, $bytes.Length)
}
