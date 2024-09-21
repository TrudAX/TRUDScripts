# Before running this copy C:\Monitoring\Instrumentation\ to C:\Monitoring\Instrumentation\Monitoring
# and check APPROOT value, it should be C:\Monitoring\Instrumentation. PS: Get-ChildItem Env: | Sort-Object Name
$directoryPath = "C:\Monitoring\Instrumentation"

$manFiles = Get-ChildItem -Path $directoryPath -Filter "*.man"

foreach ($file in $manFiles) {
    $filePath = $file.FullName
    
    Write-Host "Processing file: $filePath"
    
    try {
        Write-Host "Uninstalling manifest..."
        wevtutil um $filePath
        
        Write-Host "Installing manifest..."
        wevtutil im $filePath
        
        Write-Host "Successfully processed $filePath"
    }
    catch {
        Write-Host "Error processing $filePath : $_" -ForegroundColor Red
    }
    
    Write-Host "" # Empty line for better readability
}

Write-Host "All .man files have been processed."