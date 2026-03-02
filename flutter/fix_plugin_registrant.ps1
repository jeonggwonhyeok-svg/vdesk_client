# fix_plugin_registrant.ps1
# flutter pub get 후 실행하여 flutter_inappwebview_windows 충돌 해결

$filePath = "windows\flutter\generated_plugin_registrant.cc"

if (Test-Path $filePath) {
    $content = Get-Content $filePath -Raw

    # flutter_inappwebview_windows include 제거
    $content = $content -replace '#include <flutter_inappwebview_windows/flutter_inappwebview_windows_plugin_c_api.h>\r?\n', ''

    # flutter_inappwebview_windows 등록 코드 제거
    $content = $content -replace '  FlutterInappwebviewWindowsPluginCApiRegisterWithRegistrar\(\r?\n      registry->GetRegistrarForPlugin\("FlutterInappwebviewWindowsPluginCApi"\)\);\r?\n', ''

    Set-Content $filePath $content -NoNewline
    Write-Host "fixed: flutter_inappwebview_windows removed from $filePath" -ForegroundColor Green
} else {
    Write-Host "File not found: $filePath" -ForegroundColor Red
}
