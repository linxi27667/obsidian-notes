# Obsidian 笔记库整理脚本
# 请在运行前备份整个 Vault！

$vault = "C:\Users\30817\Documents\Obsidian Vault"

# 1. 创建新目录结构
Write-Host "=== 创建新目录结构 ===" -ForegroundColor Cyan
$newDirs = @(
    "00-Inbox",
    "01-工作",
    "01-工作\高昌-举升机",
    "01-工作\kinco显示屏",
    "02-学习",
    "02-学习\嵌入式",
    "02-学习\嵌入式\ESP-IDF",
    "02-学习\嵌入式\FreeRTOS",
    "02-学习\嵌入式\LVGL",
    "02-学习\嵌入式\电路",
    "02-学习\嵌入式\硬件外设",
    "02-学习\嵌入式\GDB调试",
    "02-学习\通信协议",
    "02-学习\网络",
    "02-学习\英语",
    "03-项目",
    "03-项目\智能家居比赛",
    "04-工具",
    "04-工具\提示词",
    "05-日志",
    "05-日志\踩坑日志",
    "05-日志\ai工作日志",
    "06-归档"
)
foreach ($dir in $newDirs) {
    $path = Join-Path $vault $dir
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "  创建: $dir" -ForegroundColor Green
    }
}

# 2. 移动工作相关
Write-Host "`n=== 移动工作相关文件 ===" -ForegroundColor Cyan
$workMoves = @{
    "高昌\*" = "01-工作\高昌-举升机"
    "kinco显示屏\*" = "01-工作\kinco显示屏"
}
foreach ($src in $workMoves.Keys) {
    $srcPath = Join-Path $vault $src
    $dstPath = Join-Path $vault $workMoves[$src]
    if (Test-Path $srcPath) {
        Move-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  移动: $src -> $($workMoves[$src])" -ForegroundColor Yellow
    }
}

# 3. 移动学习笔记 (嵌入式相关)
Write-Host "`n=== 移动学习笔记 ===" -ForegroundColor Cyan
$embeddedMoves = @{
    "笔记\我的学习笔记\ESP-IDF\*" = "02-学习\嵌入式\ESP-IDF"
    "笔记\我的学习笔记\Freertos\*" = "02-学习\嵌入式\FreeRTOS"
    "笔记\我的学习笔记\LVGL\*" = "02-学习\嵌入式\LVGL"
    "笔记\我的学习笔记\电路学习笔记\*" = "02-学习\嵌入式\电路"
    "笔记\我的学习笔记\硬件外设\*" = "02-学习\嵌入式\硬件外设"
    "笔记\我的学习笔记\GDB调试\*" = "02-学习\嵌入式\GDB调试"
}
foreach ($src in $embeddedMoves.Keys) {
    $srcPath = Join-Path $vault $src
    $dstPath = Join-Path $vault $embeddedMoves[$src]
    if (Test-Path $srcPath) {
        Move-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  移动: $src -> $($embeddedMoves[$src])" -ForegroundColor Yellow
    }
}

# 4. 移动通信协议、网络、英语
$otherMoves = @{
    "笔记\通信协议\*" = "02-学习\通信协议"
    "笔记\我的学习笔记\网络笔记\*" = "02-学习\网络"
    "英语笔记\*" = "02-学习\英语"
}
foreach ($src in $otherMoves.Keys) {
    $srcPath = Join-Path $vault $src
    $dstPath = Join-Path $vault $otherMoves[$src]
    if (Test-Path $srcPath) {
        Move-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  移动: $src -> $($otherMoves[$src])" -ForegroundColor Yellow
    }
}

# 5. 移动项目和工具
Write-Host "`n=== 移动项目和工具 ===" -ForegroundColor Cyan
$projectMoves = @{
    "智能家居\*" = "03-项目\智能家居比赛"
    "优秀提示词\*" = "04-工具\提示词"
}
foreach ($src in $projectMoves.Keys) {
    $srcPath = Join-Path $vault $src
    $dstPath = Join-Path $vault $projectMoves[$src]
    if (Test-Path $srcPath) {
        Move-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  移动: $src -> $($projectMoves[$src])" -ForegroundColor Yellow
    }
}

# 6. 移动日志
Write-Host "`n=== 移动日志 ===" -ForegroundColor Cyan
$logMoves = @{
    "踩坑日志\*" = "05-日志\踩坑日志"
    "笔记\ai工作日志记忆\*" = "05-日志\ai工作日志"
}
foreach ($src in $logMoves.Keys) {
    $srcPath = Join-Path $vault $src
    $dstPath = Join-Path $vault $logMoves[$src]
    if (Test-Path $srcPath) {
        Move-Item -Path $srcPath -Destination $dstPath -Force
        Write-Host "  移动: $src -> $($logMoves[$src])" -ForegroundColor Yellow
    }
}

# 7. 清理空目录
Write-Host "`n=== 清理空目录 ===" -ForegroundColor Cyan
$emptyDirs = @(
    "高昌",
    "kinco显示屏",
    "智能家居",
    "优秀提示词",
    "踩坑日志",
    "英语笔记",
    "笔记\我的学习笔记",
    "笔记\通信协议",
    "笔记\ai工作日志记忆"
)
foreach ($dir in $emptyDirs) {
    $path = Join-Path $vault $dir
    if (Test-Path $path) {
        $items = Get-ChildItem $path -Recurse
        if ($items.Count -eq 0) {
            Remove-Item $path -Force
            Write-Host "  删除空目录: $dir" -ForegroundColor Red
        } else {
            Write-Host "  保留非空目录: $dir (还有 $($items.Count) 个文件)" -ForegroundColor DarkYellow
        }
    }
}

# 8. 移动视频笔记
Write-Host "`n=== 移动视频笔记 ===" -ForegroundColor Cyan
$videoSrc = Join-Path $vault "笔记\我的学习笔记（视频）"
if (Test-Path $videoSrc) {
    $videoDst = Join-Path $vault "02-学习\视频笔记"
    if (!(Test-Path $videoDst)) {
        New-Item -ItemType Directory -Path $videoDst -Force | Out-Null
    }
    Move-Item -Path "$videoSrc\*" -Destination $videoDst -Force
    Write-Host "  移动: 我的学习笔记（视频） -> 02-学习\视频笔记" -ForegroundColor Yellow
}

Write-Host "`n=== 整理完成！===" -ForegroundColor Green
Write-Host "请检查新结构，确认无误后可删除旧的空目录" -ForegroundColor Cyan
