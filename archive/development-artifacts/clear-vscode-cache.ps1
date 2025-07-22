#!/usr/bin/env pwsh
# Clear VS Code cache and workspace data
# Run this script to clean up VS Code caches

Write-Host "🧹 Clearing VS Code cache and workspace data..." -ForegroundColor Cyan
Write-Host "📅 $(Get-Date)" -ForegroundColor Gray

# VS Code cache locations
$vscodeCache = @(
    "$env:APPDATA\Code\CachedExtensions",
    "$env:APPDATA\Code\logs", 
    "$env:APPDATA\Code\CachedData",
    "$env:APPDATA\Code\Workspaces",
    "$env:APPDATA\Code\User\History",
    "$env:LOCALAPPDATA\Programs\Microsoft VS Code\resources\app\node_modules\.cache"
)

# Clear each cache directory
foreach ($cache in $vscodeCache) {
    if (Test-Path $cache) {
        Write-Host "🗑️  Clearing: $cache" -ForegroundColor Yellow
        try {
            Remove-Item -Path $cache -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   ✅ Cleared successfully" -ForegroundColor Green
        }
        catch {
            Write-Host "   ⚠️  Some files may be in use" -ForegroundColor Orange
        }
    } else {
        Write-Host "   ℹ️  Not found: $cache" -ForegroundColor Gray
    }
}

# Clear Copilot cache
$copilotCache = "$env:APPDATA\Code\User\globalStorage\github.copilot"
if (Test-Path $copilotCache) {
    Write-Host "🤖 Clearing Copilot cache..." -ForegroundColor Yellow
    Remove-Item -Path $copilotCache -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "   ✅ Copilot cache cleared" -ForegroundColor Green
}

# Clear workspace storage
$workspaceStorage = "$env:APPDATA\Code\User\workspaceStorage"
if (Test-Path $workspaceStorage) {
    Write-Host "💼 Clearing workspace storage..." -ForegroundColor Yellow
    Get-ChildItem -Path $workspaceStorage -Directory | Where-Object { $_.Name -match "zabbix|monitor" } | ForEach-Object {
        Write-Host "   🗑️  Removing workspace: $($_.Name)" -ForegroundColor Yellow
        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "   ✅ Workspace storage cleared" -ForegroundColor Green
}

Write-Host ""
Write-Host "✅ VS Code cache clearing completed!" -ForegroundColor Green
Write-Host "🔄 Restart VS Code to complete the cleanup" -ForegroundColor Cyan
