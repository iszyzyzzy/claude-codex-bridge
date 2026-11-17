param(
    [string]$NodePath = (& node -p "require('node:fs').realpathSync(process.execPath)")
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$bundle = Join-Path $projectRoot 'dist/server.js'
if (!(Test-Path -LiteralPath $bundle)) { throw '请先运行 npm run build' }
$NodePath = (Resolve-Path -LiteralPath $NodePath).Path
if ($NodePath -match '[\\/]\.version-fox[\\/]temp[\\/]') {
    throw '请通过 -NodePath 指定固定安装目录中的 node.exe'
}

$marketRoot = Join-Path $projectRoot '.runtime/local-marketplace'
$pluginRoot = Join-Path $marketRoot 'plugins/codex-bridge-local'
New-Item -ItemType Directory -Force -Path (Join-Path $marketRoot '.claude-plugin'), (Join-Path $pluginRoot '.claude-plugin'), (Join-Path $pluginRoot 'dist') | Out-Null
Copy-Item -LiteralPath $bundle -Destination (Join-Path $pluginRoot 'dist/server.js')

$plugin = Get-Content -Raw (Join-Path $projectRoot 'plugins/claude-codex-bridge/.claude-plugin/plugin.json') | ConvertFrom-Json
$plugin.name = 'codex-bridge-local'
$plugin.version = "$($plugin.version)-local"
$plugin.mcpServers.'codex-bridge'.command = $NodePath
$plugin.mcpServers.'codex-bridge'.args = @('${CLAUDE_PLUGIN_ROOT}/dist/server.js')
$market = Get-Content -Raw (Join-Path $projectRoot '.claude-plugin/marketplace.json') | ConvertFrom-Json
$market.name = 'codex-bridge-local'
$market.plugins[0].name = 'codex-bridge-local'
$market.plugins[0].source = './plugins/codex-bridge-local'
$market.plugins[0].version = $plugin.version
$utf8 = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText((Join-Path $pluginRoot '.claude-plugin/plugin.json'), ($plugin | ConvertTo-Json -Depth 20), $utf8)
[System.IO.File]::WriteAllText((Join-Path $marketRoot '.claude-plugin/marketplace.json'), ($market | ConvertTo-Json -Depth 20), $utf8)

& claude plugin validate --strict $pluginRoot
if ($LASTEXITCODE -ne 0) { throw '本地插件校验失败' }
& claude plugin validate --strict (Join-Path $marketRoot '.claude-plugin/marketplace.json')
if ($LASTEXITCODE -ne 0) { throw '本地市场校验失败' }

$markets = & claude plugin marketplace list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw '读取插件市场失败' }
if ($markets.name -contains 'codex-bridge-local') {
    & claude plugin marketplace update codex-bridge-local
} else {
    & claude plugin marketplace add $marketRoot --scope user
}
if ($LASTEXITCODE -ne 0) { throw '注册本地 bridge 市场失败' }
$installed = & claude plugin list --json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw '读取插件列表失败' }
if ($installed.id -contains 'codex-bridge-local@codex-bridge-local') {
    & claude plugin uninstall codex-bridge-local@codex-bridge-local --scope user
    if ($LASTEXITCODE -ne 0) { throw '更新本地 bridge 插件失败' }
}
& claude plugin install codex-bridge-local@codex-bridge-local --scope user
if ($LASTEXITCODE -ne 0) { throw '安装本地 bridge 插件失败' }
if ($installed.id -contains 'claude-codex-bridge@claude-codex-bridge') {
    & claude plugin disable claude-codex-bridge@claude-codex-bridge --scope user
    if ($LASTEXITCODE -ne 0) { throw '禁用原版 bridge 失败' }
}
