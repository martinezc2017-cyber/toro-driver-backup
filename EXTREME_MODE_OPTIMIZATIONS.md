# EXTREME MODE OPTIMIZATIONS FOR MAPBOX LAG
**Date**: 2026-01-24
**Problem**: Mapbox 3D navigation had severe lag (avg 40-114ms frame times)
**Target**: Google Maps level performance (avg <40ms, no spikes >60ms)

---

## PREVIOUS OPTIMIZATIONS (APPLIED)
1. ✅ `flyTo()` → `setCamera()` (no animations)
2. ✅ 3D view (pitch 60°) → 2D view (pitch 0°)
3. ✅ GPS updates every 5m → every 30m
4. ✅ High accuracy → Medium accuracy
5. ✅ Route points reduced by 80% (1 of 5 points)
6. ✅ Simplified markers (no text labels)
7. ✅ DARK map style → STREET (simpler tiles)
8. ✅ UI updates every 20m → every 100m
9. ✅ Fire-and-forget camera updates (`.ignore()`)

**Result**: Average improved but still had spikes to 85-114ms ❌

---

## EXTREME MODE OPTIMIZATIONS (NEW)

### 1. **ROUTE POLYLINE DISABLED** 🔴
**File**: `lib/src/screens/navigation_map_screen.dart:203`
```dart
Future<void> _drawRoute() async {
  // EXTREME MODE: Disable route polyline completely
  // The route line is the most expensive rendering operation
  return; // EXIT EARLY - no route drawing
}
```
**Impact**: Eliminates the most expensive Mapbox rendering operation (blue route line)
**Trade-off**: Driver navigates using instruction panel + destination marker only

---

### 2. **BEARING ROTATION DISABLED** 🔴
**File**: `lib/src/screens/navigation_map_screen.dart:155-165`
```dart
// BEFORE:
bearing: _currentBearing, // Map rotates with driver heading

// AFTER:
bearing: 0, // EXTREME: Always north-up (no rotation)
```
**Impact**: Eliminates expensive map rotation/re-rendering on every GPS update
**Trade-off**: Map always shows north-up (like old-school GPS)

---

### 3. **ZOOM LEVEL REDUCED** ⚠️
**Changed from**: `zoom: 17.5` (very detailed)
**Changed to**: `zoom: 16.0` (less detail)

**Impact**: Fewer map tiles to load and render
**Trade-off**: Slightly less detail when zoomed in

---

### 4. **GPS UPDATE FREQUENCY REDUCED** ⚠️
**Changed from**: `distanceFilter: 30` meters
**Changed to**: `distanceFilter: 50` meters

**Impact**: Fewer camera updates = fewer map redraws
**Trade-off**: Position updates every 50m instead of 30m

---

## WHAT THE DRIVER SEES NOW

### Navigation View:
- ✅ Map centered on driver position
- ✅ **North is always UP** (no rotation)
- ✅ Destination marker visible
- ✅ Top instruction panel shows turn directions
- ❌ No blue route line on map (disabled for performance)

### Navigation relies on:
1. **Top instruction panel** - "Turn right in 500 ft"
2. **Destination marker** - Orange/green pin on map
3. **Distance/time badges** - "2.3 mi - 8 min"

---

## EXPECTED PERFORMANCE

### Before optimizations:
- 50th percentile: 22ms
- 90th percentile: **81ms** ❌
- 99th percentile: **120ms+** ❌

### After STANDARD optimizations:
- Average: 30-50ms (better)
- Spikes: **85-114ms** ❌ (still bad)

### After EXTREME MODE (target):
- Average: **25-35ms** ✅
- Spikes: **<50ms** ✅
- No frame drops during navigation

---

## HOW TO TEST

1. **Hot Restart** the app:
   ```bash
   # Press 'R' in Flutter terminal, or:
   flutter run -d emulator-5554
   ```

2. **Reset performance metrics**:
   ```bash
   adb shell "dumpsys gfxinfo com.example.toro_driver reset"
   ```

3. **Test navigation**:
   - Accept a ride
   - Press "LLEGUÉ" button
   - Navigate for 30-60 seconds
   - Watch for smoothness

4. **Check results**:
   ```bash
   adb shell "dumpsys gfxinfo com.example.toro_driver" | findstr "50th 90th"
   ```

---

## IF STILL LAGGY

### Nuclear Option - Switch to Static Map:
Replace Mapbox dynamic map with static map image + GPS dot

**Trade-offs**:
- ❌ No panning/zooming during navigation
- ❌ No real-time map updates
- ✅ ZERO rendering lag
- ✅ Google Maps-level performance

**Implementation**: Use Mapbox Static Images API
- Generate route image once on navigation start
- Overlay GPS position as simple dot
- Update dot position only (no map redraw)

---

## FILES MODIFIED
- `lib/src/screens/navigation_map_screen.dart`

## COMMITS
Before reverting to Google Maps, these optimizations should be tested.
If performance is acceptable, commit with:
```bash
git add lib/src/screens/navigation_map_screen.dart
git commit -m "perf: EXTREME MODE optimizations for Mapbox navigation

- Disable route polyline rendering (most expensive operation)
- Disable bearing rotation (always north-up)
- Reduce zoom from 17.5 to 16.0
- Increase GPS filter from 30m to 50m
- Target: <50ms frame times, no spikes

Measured before: avg 30-50ms, spikes to 114ms
Expected after: avg 25-35ms, spikes <50ms"
```
