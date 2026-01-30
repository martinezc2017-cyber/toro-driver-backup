# Simular movimiento GPS en el emulador para probar navegación
# Ejecutar: .\simulate_gps_route.ps1

# Ruta de ejemplo: Rio Salado Pkwy hacia South Longmore (la ruta del screenshot)
$route = @(
    @{lat=33.4342; lng=-111.901},   # Inicio - Rio Salado Pkwy
    @{lat=33.4335; lng=-111.899},
    @{lat=33.4328; lng=-111.897},
    @{lat=33.4320; lng=-111.895},
    @{lat=33.4312; lng=-111.893},
    @{lat=33.4305; lng=-111.890},
    @{lat=33.4298; lng=-111.888},
    @{lat=33.4290; lng=-111.886},
    @{lat=33.4282; lng=-111.884},
    @{lat=33.4275; lng=-111.882},
    @{lat=33.4268; lng=-111.880},
    @{lat=33.4260; lng=-111.878},
    @{lat=33.4252; lng=-111.876},
    @{lat=33.4245; lng=-111.874},
    @{lat=33.4238; lng=-111.872},
    @{lat=33.4230; lng=-111.870},
    @{lat=33.4222; lng=-111.868},
    @{lat=33.4215; lng=-111.866},   # Fin - cerca de South Longmore
)

Write-Host "Iniciando simulacion GPS..."
Write-Host "Presiona Ctrl+C para detener"
Write-Host ""

$speed = 1.5  # segundos entre puntos (ajustar para mas/menos velocidad)

while ($true) {
    foreach ($point in $route) {
        $cmd = "adb emu geo fix $($point.lng) $($point.lat)"
        Write-Host "GPS: $($point.lat), $($point.lng)"
        Invoke-Expression $cmd 2>$null
        Start-Sleep -Seconds $speed
    }
    Write-Host ""
    Write-Host "--- Reiniciando ruta ---"
    Write-Host ""
}
