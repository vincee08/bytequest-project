param([ValidateSet('wrap','unwrap')][string]$Mode)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
$entropyText = 'ByteQuest:rslmteqipxqfifwftugk:archive-key'
$entropy = [Text.Encoding]::UTF8.GetBytes($entropyText)
$inputBytes = [Convert]::FromBase64String([Console]::ReadLine())
$outputBytes = if ($Mode -eq 'wrap') {
  [Security.Cryptography.ProtectedData]::Protect($inputBytes,$entropy,$scope)
} else { [Security.Cryptography.ProtectedData]::Unprotect($inputBytes,$entropy,$scope) }
[Convert]::ToBase64String($outputBytes)
[Array]::Clear($inputBytes,0,$inputBytes.Length)
[Array]::Clear($outputBytes,0,$outputBytes.Length)
