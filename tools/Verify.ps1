param([string]$LuauDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $LuauDirectory) {
    $LuauDirectory = Join-Path $projectRoot '.tools\luau'
    if (-not (Test-Path -LiteralPath (Join-Path $LuauDirectory 'luau.exe'))) {
        $archivePath = Join-Path $projectRoot '.tools\luau-windows.zip'
        New-Item -ItemType Directory -Path (Split-Path $archivePath) -Force | Out-Null
        Invoke-WebRequest -Uri 'https://github.com/luau-lang/luau/releases/download/0.742/luau-windows.zip' -OutFile $archivePath
        $expectedHash = '1114966CD8198F407069F07E8B4E6BACF2DED933E4A57D6DDC75617969278C75'
        if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash -ne $expectedHash) {
            throw 'Luau archive hash does not match the verified 0.742 archive.'
        }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $LuauDirectory -Force
    }
}
$LuauDirectory = [IO.Path]::GetFullPath($LuauDirectory)
Push-Location -LiteralPath $projectRoot
try {
    & (Join-Path $LuauDirectory 'luau.exe') 'tests/run.luau'
    if ($LASTEXITCODE -ne 0) { throw 'Core tests failed.' }
    & node 'tools/test-binding.mjs' (Join-Path $LuauDirectory 'luau.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Binding tests failed.' }
    & (Join-Path $LuauDirectory 'luau-analyze.exe') 'src/Validate.luau' 'src/RateLimiter.luau'
    if ($LASTEXITCODE -ne 0) { throw 'Core type analysis failed.' }
    $sourceFiles = @(Get-ChildItem -LiteralPath src,tests,examples -Recurse -Filter '*.luau' -File | ForEach-Object FullName)
    & (Join-Path $LuauDirectory 'luau-compile.exe') '--null' @sourceFiles
    if ($LASTEXITCODE -ne 0) { throw 'Luau compilation failed.' }
    & node 'tools/build-model.mjs'
    if ($LASTEXITCODE -ne 0) { throw 'Model generation failed.' }
    & node 'tools/build-studio-tests.mjs'
    if ($LASTEXITCODE -ne 0) { throw 'Studio test generation failed.' }
} finally {
    Pop-Location
}
