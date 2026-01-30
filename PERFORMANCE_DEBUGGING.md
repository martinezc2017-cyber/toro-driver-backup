# PERFORMANCE DEBUGGING - IDENTIFICAR BOTTLENECKS
**Date**: 2026-01-24
**Goal**: Identificar EXACTAMENTE qué está causando los spikes de 166-185ms

---

## ❌ APOCALYPSE MODE RESULTS

**RESULTADOS**:
- avg=100.63ms max=**185ms** 😱 (PEOR que NUCLEAR)
- avg=83.78ms max=**185ms** 😱
- avg=83.51ms max=**180ms** 😱
- avg=72.39ms max=**166ms** 😱

**PROBLEMA**: Zoom 12 causó MÁS lag (área 4x mayor = más tiles)

**CAMBIO**: Rollback a zoom 14 + agregar performance logs detallados

---

## 🔍 NUEVOS PERFORMANCE LOGS

Agregamos 5 tipos de logs para identificar el bottleneck:

### 1. **MAP_INIT** - Inicialización del mapa
```dart
⏱️ PERF[MAP_INIT]: Starting...
⏱️ PERF[MAP_INIT]: Completed in 234ms
```

**Qué mide**:
- Cuánto tarda Mapbox en inicializar
- Creación de annotation managers
- Setup inicial del mapa

**Esperado**: 100-300ms (solo ocurre 1 vez)

---

### 2. **CAMERA** - Camera updates
```dart
⏱️ PERF[CAMERA]: 12ms
⏱️ PERF[CAMERA]: 156ms  ← SPIKE!
```

**Qué mide**:
- Cuánto tarda `setCamera()` en ejecutar
- Si está cargando tiles nuevos
- Si hay re-rendering de mapa

**Esperado**: <20ms
**Si hay spike**: Mapbox está cargando/renderizando tiles

---

### 3. **SETSTATE** - Widget rebuilds
```dart
⏱️ PERF[SETSTATE]: 5ms
⏱️ PERF[SETSTATE]: 89ms  ← SPIKE!
```

**Qué mide**:
- Cuánto tarda Flutter en rebuildar widgets
- Si hay widget rendering pesado
- Si RepaintBoundary está funcionando

**Esperado**: <10ms
**Si hay spike**: Widgets pesados o RepaintBoundary no funciona

---

### 4. **GPS_TOTAL** - GPS processing completo
```dart
⏱️ PERF[GPS_TOTAL]: 8ms
⏱️ PERF[GPS_TOTAL]: 15ms
```

**Qué mide**:
- Tiempo total de `_updateDriverLocation()`
- Incluye cálculos de bearing, distancia
- Incluye llamadas a setCamera y setState

**Esperado**: <20ms
**Si hay spike**: Uno de los pasos internos está lento

---

### 5. **BUILD** - Frame rendering
```dart
⏱️ PERF[BUILD]: 18ms (frame #10)
⏱️ PERF[BUILD]: 145ms (frame #20)  ← SPIKE!
```

**Qué mide**:
- Cuánto tarda el build() completo
- Rendering de todo el widget tree
- Incluye MapWidget rendering

**Esperado**: <20ms para 60 FPS
**Si hay spike**: MapWidget está renderizando pesado

---

## 📊 CÓMO INTERPRETAR LOS LOGS

### Ejemplo 1: Spikes en CAMERA
```
⏱️ PERF[CAMERA]: 185ms  ← PROBLEMA AQUÍ
⏱️ PERF[SETSTATE]: 3ms
⏱️ PERF[GPS_TOTAL]: 190ms
⏱️ PERF[BUILD]: 195ms
```

**Diagnóstico**: Mapbox tile loading/rendering
**Solución**:
- Lower zoom level
- Use navigation-optimized style
- Pre-cache tiles
- Switch to static map images

---

### Ejemplo 2: Spikes en SETSTATE
```
⏱️ PERF[CAMERA]: 5ms
⏱️ PERF[SETSTATE]: 120ms  ← PROBLEMA AQUÍ
⏱️ PERF[GPS_TOTAL]: 128ms
⏱️ PERF[BUILD]: 135ms
```

**Diagnóstico**: Widget rebuilds pesados
**Solución**:
- Simplificar instruction panel
- Más RepaintBoundaries
- Reducir widget tree complexity

---

### Ejemplo 3: Spikes en BUILD (pero no en CAMERA/SETSTATE)
```
⏱️ PERF[CAMERA]: 8ms
⏱️ PERF[SETSTATE]: 4ms
⏱️ PERF[GPS_TOTAL]: 15ms
⏱️ PERF[BUILD]: 150ms  ← PROBLEMA AQUÍ (pero los otros son rápidos)
```

**Diagnóstico**: MapWidget rendering (no camera, solo rendering)
**Solución**:
- RepaintBoundary no está aislando
- Map style demasiado complejo
- Usar static map image

---

## 🧪 TESTING PROCEDURE

### 1. Hot Restart con logs
```bash
# Presiona 'R' en Flutter terminal
```

### 2. Navega 30 segundos

### 3. Analiza los logs

Busca patrones como:
```bash
# Filtra solo PERF logs
adb logcat | grep "PERF"

# Busca spikes >100ms
adb logcat | grep "PERF" | grep -E "[1-9][0-9]{2}ms"
```

### 4. Identifica el bottleneck

- **Si CAMERA tiene spikes**: Mapbox tile loading
- **Si SETSTATE tiene spikes**: Widget rebuilds
- **Si BUILD tiene spikes (sin CAMERA/SETSTATE)**: MapWidget rendering
- **Si GPS_TOTAL tiene spikes**: GPS processing overhead

---

## 🎯 PRÓXIMOS PASOS

Basado en los logs, aplicaremos la solución correspondiente:

### Si CAMERA es el problema:
1. Probar estilos más simples
2. Pre-cache tiles
3. **BEST**: Static map images (0ms rendering)

### Si SETSTATE es el problema:
1. Simplificar instruction panel
2. Agregar más RepaintBoundaries
3. Throttle setState aún más

### Si BUILD/MapWidget es el problema:
1. Verificar RepaintBoundary
2. Simplificar map style
3. **BEST**: Static map images

### Si GPS_TOTAL es el problema:
1. Optimizar cálculos de bearing/distance
2. Throttle GPS updates más

---

## 📝 CAMBIOS APLICADOS

1. ✅ Rollback zoom 12 → 14 (zoom 12 causó más lag)
2. ✅ Agregados 5 tipos de performance logs
3. ✅ Log cada 10 frames para BUILD (evitar spam)
4. ✅ Log en tiempo real para CAMERA, SETSTATE, GPS

---

## 🚀 READY FOR TESTING

**Presiona 'R' en Flutter terminal y navega por 30 segundos**

Los logs te mostrarán EXACTAMENTE dónde está el problema.

**STATUS**: Performance debugging ready 🔍⏱️
