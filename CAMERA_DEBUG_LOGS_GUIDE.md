# CAMERA DEBUG LOGS - GUÍA COMPLETA 📹
**Fecha**: 2026-01-25
**Objetivo**: Logs detallados de ubicación de cámara para debugging en emulador
**Archivo**: `home_screen.dart`

---

## 🎯 LOGS AGREGADOS (7 TIPOS)

### 1. 🛰️ GPS_RECEIVED - Nuevo GPS Recibido

**Formato**:
```
🛰️ GPS_RECEIVED[#123] [14:32:45.678] →
  pos=(33.448420,-112.074012)
  speed=45.2mph
  heading=180.5°
  accuracy=12.3m
  altitude=340.5m
  interval=2045ms
```

**Qué muestra**:
- `#123` - Número de GPS update (incrementa cada vez que llega GPS)
- `[14:32:45.678]` - Timestamp exacto (HH:mm:ss.SSS)
- `pos` - Posición GPS REAL del emulador (lat, lng) con 6 decimales
- `speed` - Velocidad detectada en mph
- `heading` - Rumbo GPS del dispositivo (0-360°)
- `accuracy` - Precisión del GPS en metros
- `altitude` - Altitud en metros
- `interval` - Milisegundos desde último GPS

**Cuándo aparece**: Cada vez que llega un nuevo GPS update (cada ~2 segundos)

**Para qué sirve**:
- Ver si el GPS está enviando coordenadas correctas
- Verificar que el emulador GPS está funcionando
- Ver frecuencia de updates GPS
- Detectar si hay problemas de accuracy o speed

---

### 2. 🔄 GPS_BEARING_CHANGE - Cambio de Dirección GPS

**Formato**:
```
🔄 GPS_BEARING_CHANGE[#123]: Δ25.3° (155.2°→180.5°)
```

**Qué muestra**:
- `#123` - Número de GPS update
- `Δ25.3°` - Cambio de bearing (diferencia angular)
- `155.2°→180.5°` - Bearing ANTES → bearing DESPUÉS

**Cuándo aparece**: Solo cuando el bearing cambia >15° (giro significativo)

**Para qué sirve**:
- Detectar cuándo el emulador GPS gira
- Ver si los giros son smooth o abruptos
- Identificar problemas de bearing jumping

---

### 3. 📹 CAM_UPDATE - Estado ANTES de Actualizar Cámara

**Formato**:
```
📹 CAM_UPDATE[#456] [14:32:45.678] →
  gpsReal=(33.448420,-112.074012)
  smoothed=(33.448410,-112.074008)
  bearingGPS=180.5°
  bearingSmooth=178.2°
  speed=45.2mph
  gpsAge=678ms
  instant=true
  tracking=true
  userInteract=false
```

**Qué muestra**:
- `#456` - Número de camera update (incrementa cada 200ms con timer)
- `[14:32:45.678]` - Timestamp exacto
- `gpsReal` - Posición GPS RAW (sin suavizar)
- `smoothed` - Posición SUAVIZADA que se usará para cámara
- `bearingGPS` - Bearing calculado desde GPS
- `bearingSmooth` - Bearing suavizado que se usará para cámara
- `speed` - Velocidad en mph
- `gpsAge` - Milisegundos desde último GPS (debe ser <3000ms)
- `instant` - Si es instant (true) o animado (false)
- `tracking` - Si está en modo tracking (debería ser true siempre)
- `userInteract` - Si el usuario está tocando el mapa (pausaría auto-nav)

**Cuándo aparece**: CADA camera update (cada 200ms = 5 FPS)

**Para qué sirve**:
- Ver diferencia entre GPS real y posición suavizada
- Detectar lag GPS (gpsAge alto)
- Ver si el smoothing está funcionando
- Detectar si hay user interaction bloqueando camera

---

### 4. 📹 CAM_PARAMS - Parámetros Finales ANTES de setCamera

**Formato**:
```
📹 CAM_PARAMS[#456] →
  pos=(33.448410,-112.074008)
  zoom=15.5
  pitch=60°
  bearing=178.2°
  topPadding=350px
```

**Qué muestra**:
- `#456` - Número de camera update
- `pos` - Posición FINAL que se usará (suavizada + predicha)
- `zoom` - Zoom dinámico calculado (14.5-16.5 según velocidad)
- `pitch` - Pitch dinámico calculado (45-65° según velocidad)
- `bearing` - Bearing final suavizado
- `topPadding` - Padding superior del mapa (para centrar abajo)

**Cuándo aparece**: CADA camera update, justo antes de llamar setCamera()

**Para qué sirve**:
- Ver los valores EXACTOS que se envían a Mapbox
- Verificar que zoom/pitch dinámicos están funcionando
- Detectar si bearing está saltando o suavizando bien
- Ver si el padding es correcto

---

### 5. 📹 CAM_SET_OK - Confirmación setCamera Ejecutado

**Formato**:
```
📹 CAM_SET_OK[#456] → setCamera executed in 5ms
```

**Qué muestra**:
- `#456` - Número de camera update
- `5ms` - Tiempo que tardó setCamera() en ejecutarse

**Cuándo aparece**: CADA camera update, inmediatamente después de setCamera()

**Para qué sirve**:
- Confirmar que setCamera() se ejecutó correctamente
- Detectar si setCamera() está tardando mucho (>20ms es problema)
- Ver si hay spikes de performance en setCamera

---

### 6. 🔄 BEARING_CHANGE - Cambio de Bearing en Cámara

**Formato**:
```
🔄 BEARING_CHANGE[#456]: diff=25.3° smoothed=178.2° target=180.5°
```

**Qué muestra**:
- `#456` - Número de camera update
- `diff` - Diferencia entre bearing actual y target
- `smoothed` - Bearing suavizado ANTES del update
- `target` - Bearing objetivo (del GPS)

**Cuándo aparece**: Solo cuando bearing diff >15° (cambio significativo)

**Para qué sirve**:
- Ver cuándo la cámara está rotando significativamente
- Detectar si el smoothing está suavizando demasiado (o muy poco)
- Identificar problemas de rotación nerviosa

---

### 7. 📷 CAM_SUMMARY - Resumen Periódico

**Formato**:
```
📷 CAM_SUMMARY[#450]: avgGpsAge=678ms updates=450 speed=45.2mph
```

**Qué muestra**:
- `#450` - Número de camera updates totales
- `avgGpsAge` - Edad del último GPS (debe ser <3000ms)
- `updates` - Total de camera updates desde inicio
- `speed` - Velocidad actual

**Cuándo aparece**: Cada 30 camera updates (~6 segundos a 5 FPS)

**Para qué sirve**:
- Ver progreso general de camera updates
- Verificar que no hay stale GPS (gpsAge alto)
- Monitorear velocidad promedio

---

## 🔍 CÓMO INTERPRETAR LOS LOGS

### Secuencia NORMAL (Todo funcionando bien):

```
[14:32:45.000] 🛰️ GPS_RECEIVED[#28] → pos=(33.448420,-112.074012) speed=45.2mph heading=180.5° accuracy=12.3m altitude=340.5m interval=2045ms

[14:32:45.200] 📹 CAM_UPDATE[#140] → gpsReal=(33.448420,-112.074012) smoothed=(33.448418,-112.074011) bearingGPS=180.5° bearingSmooth=179.8° speed=45.2mph gpsAge=200ms instant=true tracking=true userInteract=false
[14:32:45.201] 📹 CAM_PARAMS[#140] → pos=(33.448418,-112.074011) zoom=15.5 pitch=60° bearing=179.8° topPadding=350px
[14:32:45.206] 📹 CAM_SET_OK[#140] → setCamera executed in 5ms

[14:32:45.400] 📹 CAM_UPDATE[#141] → ...
[14:32:45.401] 📹 CAM_PARAMS[#141] → ...
[14:32:45.405] 📹 CAM_SET_OK[#141] → setCamera executed in 4ms

[14:32:45.600] 📹 CAM_UPDATE[#142] → ...
[14:32:45.601] 📹 CAM_PARAMS[#142] → ...
[14:32:45.604] 📹 CAM_SET_OK[#142] → setCamera executed in 3ms

[14:32:47.000] 🛰️ GPS_RECEIVED[#29] → pos=(33.448510,-112.074102) speed=46.1mph heading=181.2° accuracy=11.8m altitude=340.2m interval=2000ms
```

**Interpretación**: ✅ TODO PERFECTO
- GPS llega cada ~2 segundos ✅
- Camera updates cada 200ms (5 FPS) ✅
- setCamera ejecuta en <10ms ✅
- gpsAge <3000ms ✅
- Smooth/GPS positions muy cercanas (smoothing working) ✅

---

### Secuencia PROBLEMÁTICA (Emulador congelado):

```
[14:32:45.000] 🛰️ GPS_RECEIVED[#28] → ...

[14:32:45.200] 📹 CAM_UPDATE[#140] → gpsAge=200ms ...
[14:32:45.201] 📹 CAM_PARAMS[#140] → ...
[14:32:45.206] 📹 CAM_SET_OK[#140] → setCamera executed in 5ms

[SILENCIO TOTAL POR 30 MINUTOS - NO MÁS LOGS]

[15:02:45.000] 🛰️ GPS_RECEIVED[#29] → ... interval=1800000ms
```

**Interpretación**: ❌ FREEZE TOTAL
- GPS NO llega por 30 minutos ❌
- Camera updates NO suceden ❌
- App logic congelada ❌
- Causa: Emulador GPU no puede con Mapbox ❌
- Solución: Dispositivo Android real 📱

---

### Secuencia PROBLEMÁTICA (setCamera lento):

```
[14:32:45.200] 📹 CAM_UPDATE[#140] → ...
[14:32:45.201] 📹 CAM_PARAMS[#140] → ...
[14:32:45.450] 📹 CAM_SET_OK[#140] → setCamera executed in 249ms ⚠️

[14:32:45.600] 📹 CAM_UPDATE[#141] → ...
[14:32:45.601] 📹 CAM_PARAMS[#141] → ...
[14:32:45.980] 📹 CAM_SET_OK[#141] → setCamera executed in 379ms ⚠️
```

**Interpretación**: ⚠️ SETCAMERA MUY LENTO
- setCamera tardando >200ms (debería ser <10ms) ❌
- GPU rendering lag severo ❌
- Posibles causas:
  - pixelRatio muy alto (pero ya está en 0.5) ❌
  - Tiles cargando lento ❌
  - Emulador GPU sobrecargado ❌
- Solución: Dispositivo real 📱

---

### Secuencia PROBLEMÁTICA (GPS Age alto):

```
[14:32:45.000] 🛰️ GPS_RECEIVED[#28] → ...

[14:32:50.200] 📹 CAM_UPDATE[#140] → gpsAge=5200ms ⚠️ ...
[14:32:50.201] 📹 CAM_PARAMS[#140] → ...
[14:32:50.206] 📹 CAM_SET_OK[#140] → setCamera executed in 5ms
```

**Interpretación**: ⚠️ GPS STALE (demasiado viejo)
- GPS Age >5 segundos (debería ser <3s) ❌
- GPS no está llegando frecuentemente ❌
- Posibles causas:
  - Emulador GPS pausado ❌
  - Location simulation stopped ❌
  - App en background (pero log dice userInteract=false) ❌
- Solución: Revisar emulador GPS settings 🛰️

---

### Secuencia PROBLEMÁTICA (Bearing jumping):

```
[14:32:45.200] 📹 CAM_PARAMS[#140] → bearing=180.2° ...
[14:32:45.400] 📹 CAM_PARAMS[#141] → bearing=179.8° ...
[14:32:45.600] 📹 CAM_PARAMS[#142] → bearing=270.5° ⚠️ ...
[14:32:45.800] 📹 CAM_PARAMS[#143] → bearing=181.2° ...
```

**Interpretación**: ⚠️ BEARING JUMPING
- Bearing salta de 180° a 270° abruptamente ❌
- Smoothing NO está funcionando ❌
- Posibles causas:
  - GPS bearing súbitamente cambia (emulador issue) ❌
  - Smoothing factor muy bajo ❌
  - Route recalculation causando bearing reset ❌

---

## 📊 VALORES ESPERADOS (Emulador funcionando BIEN)

| Métrica | Valor Normal | Valor Problema |
|---------|--------------|----------------|
| **GPS Interval** | 1800-2500ms | >5000ms o <500ms |
| **GPS Age** | 200-2500ms | >3000ms |
| **Camera Update Freq** | Cada 200ms | Irregular o >500ms |
| **setCamera Duration** | <10ms | >50ms |
| **Bearing Diff** | <30° por update | >90° (jumping) |
| **GPS Accuracy** | <20m | >50m |
| **Speed** | Consistente | Jumping (0→100→0) |

---

## 🎯 CÓMO USAR LOS LOGS PARA DEBUGGING

### Problema: Mapa no se mueve visualmente

**Busca en logs**:
```bash
# 1. ¿GPS llega?
grep "GPS_RECEIVED" logs.txt
# Si NO hay logs cada ~2s → GPS está pausado en emulador

# 2. ¿Camera updates ejecutan?
grep "CAM_UPDATE" logs.txt
# Si NO hay logs cada 200ms → Camera timer detenido

# 3. ¿setCamera ejecuta?
grep "CAM_SET_OK" logs.txt
# Si NO hay logs → setCamera no se llama

# 4. ¿setCamera tarda mucho?
grep "CAM_SET_OK" logs.txt | grep -E "[0-9]{3,}ms"
# Si >50ms → GPU rendering lag
```

---

### Problema: Mapa rota bruscamente (nervioso)

**Busca en logs**:
```bash
# 1. ¿Bearing salta mucho?
grep "BEARING_CHANGE" logs.txt
# Si hay muchos logs con diff >30° → Bearing jumping

# 2. ¿Bearing smoothed vs target?
grep "CAM_PARAMS" logs.txt
# Compara bearing en logs consecutivos
# Si bearing cambia >45° entre frames → Smoothing no funciona
```

---

### Problema: Zoom demasiado lejos/cerca

**Busca en logs**:
```bash
# 1. ¿Qué zoom se está usando?
grep "CAM_PARAMS" logs.txt
# Busca "zoom=XX.X"

# 2. ¿Zoom cambia con velocidad?
grep "CAM_PARAMS\|GPS_RECEIVED" logs.txt
# Compara zoom vs speed
# Debería ser:
#   speed <15mph → zoom 16.5
#   speed 30-45mph → zoom 15.5
#   speed >60mph → zoom 14.5
```

---

## ✅ LOGS REMOVIDOS/SIMPLIFICADOS

### ANTES (logs antiguos):
```dart
// Log cada 60 frames
if (_cameraUpdateCount % 60 == 0) {
  debugPrint('📷 CAM[#$_cameraUpdateCount]: bearing=... spd=... pos=...');
}
```

### DESPUÉS (nueva estructura):
```dart
// Log CADA frame con detalles completos
debugPrint('📹 CAM_UPDATE[#$_cameraUpdateCount] → ...'); // Cada 200ms
debugPrint('📹 CAM_PARAMS[#$_cameraUpdateCount] → ...'); // Cada 200ms
debugPrint('📹 CAM_SET_OK[#$_cameraUpdateCount] → ...'); // Cada 200ms

// Resumen cada 30 frames
if (_cameraUpdateCount % 30 == 0) {
  debugPrint('📷 CAM_SUMMARY[#$_cameraUpdateCount] → ...');
}
```

**Ventaja**: Logs MÁS detallados, MÁS frecuentes, MEJOR estructurados

---

## 📝 EJEMPLO DE LOG SESSION COMPLETO

```
[14:32:45.000] 🛰️ GPS_RECEIVED[#28] [14:32:45.000] → pos=(33.448420,-112.074012) speed=45.2mph heading=180.5° accuracy=12.3m altitude=340.5m interval=2045ms
[14:32:45.015] 🧭 [14:32:45.015] Step changed to 2 - UI refresh
[14:32:45.016] 🔄 [14:32:45.016] setState LLAMADO - triggering rebuild

[14:32:45.200] 📹 CAM_UPDATE[#140] [14:32:45.200] → gpsReal=(33.448420,-112.074012) smoothed=(33.448418,-112.074011) bearingGPS=180.5° bearingSmooth=179.8° speed=45.2mph gpsAge=200ms instant=true tracking=true userInteract=false
[14:32:45.201] 📹 CAM_PARAMS[#140] → pos=(33.448418,-112.074011) zoom=15.5 pitch=60° bearing=179.8° topPadding=350px
[14:32:45.206] 📹 CAM_SET_OK[#140] → setCamera executed in 5ms

[14:32:45.400] 📹 CAM_UPDATE[#141] [14:32:45.400] → gpsReal=(33.448420,-112.074012) smoothed=(33.448419,-112.074011) bearingGPS=180.5° bearingSmooth=180.0° speed=45.2mph gpsAge=400ms instant=true tracking=true userInteract=false
[14:32:45.401] 📹 CAM_PARAMS[#141] → pos=(33.448419,-112.074011) zoom=15.5 pitch=60° bearing=180.0° topPadding=350px
[14:32:45.405] 📹 CAM_SET_OK[#141] → setCamera executed in 4ms

[14:32:47.000] 🛰️ GPS_RECEIVED[#29] [14:32:47.000] → pos=(33.448510,-112.074102) speed=46.1mph heading=181.2° accuracy=11.8m altitude=340.2m interval=2000ms
[14:32:47.001] 🔄 GPS_BEARING_CHANGE[#29]: Δ0.7° (180.5°→181.2°)

[14:32:47.200] 📹 CAM_UPDATE[#150] [14:32:47.200] → gpsReal=(33.448510,-112.074102) smoothed=(33.448508,-112.074100) bearingGPS=181.2° bearingSmooth=180.8° speed=46.1mph gpsAge=200ms instant=true tracking=true userInteract=false
[14:32:47.201] 📹 CAM_PARAMS[#150] → pos=(33.448508,-112.074100) zoom=15.5 pitch=60° bearing=180.8° topPadding=350px
[14:32:47.206] 📹 CAM_SET_OK[#150] → setCamera executed in 5ms

[14:32:51.000] 📷 CAM_SUMMARY[#150]: avgGpsAge=200ms updates=150 speed=46.1mph
```

**Interpretación**: ✅ PERFECTO
- GPS cada 2 segundos ✅
- Camera cada 200ms ✅
- setCamera <10ms ✅
- Bearing smooth (<1° diff entre GPS y smoothed) ✅
- gpsAge bajo (<500ms) ✅

---

## 🚀 CÓMO ACTIVAR LOS LOGS

```bash
# 1. Hot Restart
flutter run
# Presiona 'R' en terminal

# 2. Abre "Go to map"

# 3. Observa terminal - verás TODOS los logs

# 4. Navega (simula GPS route en emulador)

# 5. Guarda logs si quieres analizarlos:
flutter run > navigation_logs.txt 2>&1
```

---

## 📌 RESUMEN

### Logs Agregados:
1. ✅ **GPS_RECEIVED** - Cada GPS update (~2s)
2. ✅ **GPS_BEARING_CHANGE** - Cuando bearing GPS cambia >15°
3. ✅ **CAM_UPDATE** - Cada camera update (200ms) - Estado inicial
4. ✅ **CAM_PARAMS** - Cada camera update (200ms) - Parámetros finales
5. ✅ **CAM_SET_OK** - Cada camera update (200ms) - Confirmación
6. ✅ **BEARING_CHANGE** - Cuando bearing cámara cambia >15°
7. ✅ **CAM_SUMMARY** - Cada 30 updates (~6s) - Resumen

### Información Capturada:
- ✅ Posición GPS real y suavizada
- ✅ Bearing GPS y bearing suavizado
- ✅ Zoom dinámico (14.5-16.5)
- ✅ Pitch dinámico (45-65°)
- ✅ Speed, heading, accuracy, altitude
- ✅ Timestamps precisos (ms)
- ✅ GPS age (freshness)
- ✅ setCamera execution time
- ✅ Tracking mode status
- ✅ User interaction status

**TOTAL**: LOGS ULTRA-DETALLADOS PARA DEBUGGING COMPLETO ✅

---

**STATUS**: CAMERA DEBUG LOGS READY 🎯

**NEXT**: Press 'R', navigate, read logs, identify issues 🔍
