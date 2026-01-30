# Resumen de Implementaciones - Sistema Toro Driver
**Fecha:** 2026-01-15

---

## 📊 SISTEMA DE RANKINGS DE CONDUCTORES

### Objetivo
Crear un sistema automático de rankings que clasifique a los conductores por estado y a nivel nacional basándose en su `acceptance_rate` (tasa de aceptación de viajes).

### Base de Datos - Campos en `drivers`
```sql
state_rank INTEGER       -- Ranking dentro del estado (ej: #1 en Arizona)
usa_rank INTEGER         -- Ranking nacional (ej: #45 en USA)
acceptance_rate DECIMAL  -- Tasa de aceptación de viajes (base del ranking)
state TEXT               -- Estado del conductor (ej: 'AZ', 'CA', 'TX')
```

### Funciones SQL Creadas

#### 1. **Recalcular Rankings Manualmente**
```sql
CREATE OR REPLACE FUNCTION public.manual_recalculate_rankings()
RETURNS void AS $$
BEGIN
  -- USA RANK - Ranking nacional
  WITH ranked_drivers AS (
    SELECT id,
           ROW_NUMBER() OVER (
             ORDER BY acceptance_rate DESC, total_rides DESC
           ) as new_rank
    FROM drivers
    WHERE acceptance_rate IS NOT NULL
  )
  UPDATE drivers d
  SET usa_rank = rd.new_rank
  FROM ranked_drivers rd
  WHERE d.id = rd.id;

  -- STATE RANK - Ranking por estado
  WITH state_ranked AS (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY state
             ORDER BY acceptance_rate DESC, total_rides DESC
           ) as new_state_rank
    FROM drivers
    WHERE acceptance_rate IS NOT NULL
      AND state IS NOT NULL
  )
  UPDATE drivers d
  SET state_rank = sr.new_state_rank
  FROM state_ranked sr
  WHERE d.id = sr.id;
END;
$$ LANGUAGE plpgsql;
```

**Uso:**
```sql
SELECT public.manual_recalculate_rankings();
```

#### 2. **Trigger Automático al Actualizar acceptance_rate**
```sql
CREATE OR REPLACE FUNCTION public.trigger_recalculate_rankings()
RETURNS TRIGGER AS $$
BEGIN
  -- Recalcular todos los rankings cuando cambie el acceptance_rate
  PERFORM public.manual_recalculate_rankings();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER auto_recalculate_rankings
  AFTER UPDATE OF acceptance_rate ON public.drivers
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.trigger_recalculate_rankings();
```

**Comportamiento:**
- Cada vez que se actualiza el `acceptance_rate` de un conductor
- El sistema recalcula automáticamente todos los rankings
- Actualiza tanto `state_rank` como `usa_rank` para todos los conductores

### Lógica del Ranking
1. **Ordenamiento Principal:** `acceptance_rate` (mayor a menor)
2. **Criterio de Desempate:** `total_rides` (más viajes = mejor posición)
3. **State Rank:** Agrupado por estado usando `PARTITION BY state`
4. **USA Rank:** Todos los conductores juntos

### Ejemplo de Datos
```
Driver A: acceptance_rate=95%, state=AZ, total_rides=500
  → state_rank = #1 (mejor en Arizona)
  → usa_rank = #3 (tercero nacional)

Driver B: acceptance_rate=93%, state=AZ, total_rides=300
  → state_rank = #2 (segundo en Arizona)
  → usa_rank = #8 (octavo nacional)

Driver C: acceptance_rate=96%, state=CA, total_rides=200
  → state_rank = #1 (mejor en California)
  → usa_rank = #1 (primero nacional)
```

---

## ⭐ SISTEMA DE RESEÑAS DE CONDUCTORES

### Objetivo
Permitir que los clientes califiquen a los conductores después de cada viaje con ratings detallados por categoría.

### Diferencia: Rankings vs Reviews
| Concepto | Rankings | Reviews |
|----------|----------|---------|
| **Fuente** | Sistema automático | Clientes |
| **Basado en** | `acceptance_rate` | Experiencia del viaje |
| **Propósito** | Competencia entre drivers | Calidad del servicio |
| **Actualización** | Trigger automático | Después de cada viaje |

### Base de Datos - Tabla `driver_reviews`

#### Archivo SQL
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro\supabase\migrations\20260115_driver_reviews_simple.sql`

#### Estructura
```sql
CREATE TABLE IF NOT EXISTS public.driver_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  delivery_id TEXT,

  -- Rating general
  rating DECIMAL(3,2) NOT NULL CHECK (rating >= 1.0 AND rating <= 5.0),
  comment TEXT,
  review_type TEXT, -- 'positive', 'neutral', 'negative'

  -- Ratings específicos por categoría (1-5)
  driving_rating INTEGER CHECK (driving_rating >= 1 AND driving_rating <= 5),
  cleanliness_rating INTEGER CHECK (cleanliness_rating >= 1 AND cleanliness_rating <= 5),
  punctuality_rating INTEGER CHECK (punctuality_rating >= 1 AND punctuality_rating <= 5),
  professionalism_rating INTEGER CHECK (professionalism_rating >= 1 AND professionalism_rating <= 5),
  vehicle_condition_rating INTEGER CHECK (vehicle_condition_rating >= 1 AND vehicle_condition_rating <= 5),

  -- Tags positivos y negativos
  positive_tags TEXT[] DEFAULT '{}',
  negative_tags TEXT[] DEFAULT '{}',

  -- Metadata
  is_verified BOOLEAN DEFAULT FALSE,
  is_visible BOOLEAN DEFAULT TRUE,
  admin_notes TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 5 Categorías de Calificación
1. **`driving_rating`** - Calidad de la conducción (1-5)
2. **`cleanliness_rating`** - Limpieza del vehículo (1-5)
3. **`punctuality_rating`** - Puntualidad del conductor (1-5)
4. **`professionalism_rating`** - Profesionalismo y trato (1-5)
5. **`vehicle_condition_rating`** - Condición del vehículo (1-5)

### Triggers Automáticos

#### 1. **Calcular `review_type` según rating**
```sql
CREATE OR REPLACE FUNCTION public.set_review_type()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.rating >= 4.0 THEN
    NEW.review_type = 'positive';
  ELSIF NEW.rating >= 3.0 THEN
    NEW.review_type = 'neutral';
  ELSE
    NEW.review_type = 'negative';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_set_review_type
  BEFORE INSERT OR UPDATE OF rating ON public.driver_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.set_review_type();
```

#### 2. **Actualizar rating del conductor automáticamente**
```sql
CREATE OR REPLACE FUNCTION public.update_driver_rating_from_reviews()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.drivers
  SET
    rating = (
      SELECT COALESCE(ROUND(AVG(rating), 2), 0)
      FROM public.driver_reviews
      WHERE driver_id = NEW.driver_id AND is_visible = TRUE
    ),
    updated_at = NOW()
  WHERE id = NEW.driver_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_driver_rating
  AFTER INSERT OR UPDATE ON public.driver_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_driver_rating_from_reviews();
```

**Comportamiento:**
- Al insertar/actualizar una reseña
- El `rating` del conductor en `drivers` se recalcula automáticamente
- Es el promedio de todas las reseñas visibles (`is_visible = TRUE`)

#### 3. **Prevenir reseñas duplicadas por viaje**
```sql
CREATE OR REPLACE FUNCTION public.prevent_duplicate_review()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.delivery_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.driver_reviews
    WHERE delivery_id = NEW.delivery_id
      AND user_id = NEW.user_id
      AND id != COALESCE(NEW.id, gen_random_uuid())
  ) THEN
    RAISE EXCEPTION 'Ya existe una reseña para este viaje';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Vista Agregada: `driver_reviews_summary`
Proporciona estadísticas resumidas por conductor:

```sql
CREATE OR REPLACE VIEW public.driver_reviews_summary AS
SELECT
  driver_id,
  COUNT(*) as total_reviews,
  COUNT(*) FILTER (WHERE review_type = 'positive') as positive_reviews,
  COUNT(*) FILTER (WHERE review_type = 'neutral') as neutral_reviews,
  COUNT(*) FILTER (WHERE review_type = 'negative') as negative_reviews,
  ROUND(AVG(rating), 2) as avg_rating,
  ROUND(AVG(driving_rating), 2) as avg_driving,
  ROUND(AVG(cleanliness_rating), 2) as avg_cleanliness,
  ROUND(AVG(punctuality_rating), 2) as avg_punctuality,
  ROUND(AVG(professionalism_rating), 2) as avg_professionalism,
  ROUND(AVG(vehicle_condition_rating), 2) as avg_vehicle_condition,
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_type = 'positive') / NULLIF(COUNT(*), 0), 1) as positive_percentage,
  ROUND(100.0 * COUNT(*) FILTER (WHERE review_type = 'negative') / NULLIF(COUNT(*), 0), 1) as negative_percentage,
  MIN(created_at) as first_review_date,
  MAX(created_at) as last_review_date
FROM public.driver_reviews
WHERE is_visible = TRUE
GROUP BY driver_id;
```

### Tags Predefinidos

**Positivos:**
- ✅ Amable
- ✅ Puntual
- ✅ Carro limpio
- ✅ Buena música
- ✅ Conversación agradable
- ✅ Conducción segura
- ✅ Profesional

**Negativos:**
- ❌ Impuntual
- ❌ Mala conducción
- ❌ Carro sucio
- ❌ Grosero
- ❌ Rutas largas
- ❌ Música alta
- ❌ Teléfono mientras conduce

---

## 🔒 SISTEMA DE PRIVACIDAD DE USUARIOS

### Objetivo
Permitir que los clientes oculten su nombre y/o foto de los conductores.

### Base de Datos - Tabla `user_preferences`

#### Archivo SQL
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro\supabase\migrations\20260115_user_privacy_settings_v2.sql`

```sql
CREATE TABLE IF NOT EXISTS public.user_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  hide_name BOOLEAN DEFAULT FALSE,
  hide_photo BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

### RLS Policies
```sql
-- Los usuarios solo pueden ver/editar sus propias preferencias
CREATE POLICY "Users can manage own preferences" ON public.user_preferences
  FOR ALL USING (auth.uid() = user_id);
```

---

## 📱 MODIFICACIONES EN DRIVER APP (toro_driver)

### 1. **Profile Screen - Mostrar Rating en lugar de Trips**

#### Archivo
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro driver flutter\toro_driver\lib\src\screens\profile_screen.dart`

#### Cambios
```dart
// ANTES: Mostraba "Trips: 120"
// AHORA: Muestra "Rating: 4.8" o "No ratings"

Widget _buildStatsCard(DriverModel? driver) {
  final totalRides = driver?.totalRides ?? 0;
  final rating = driver?.rating;
  final stateRank = driver?.stateRank;
  final usaRank = driver?.usaRank;
  final driverState = driver?.state ?? '';

  // Determinar si hay calificaciones
  final hasRatings = totalRides > 0 && rating != null;
  final ratingValue = hasRatings ? rating.toStringAsFixed(1) : '-';
  final ratingLabel = hasRatings ? 'rating'.tr() : 'no_ratings'.tr();

  return GlassCard(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Rating del cliente (antes era "Trips")
        _buildStatItem(
          Icons.star_rounded,
          ratingValue,
          ratingLabel,
          AppColors.star
        ),

        // State Rank
        _buildStatItem(
          Icons.leaderboard_rounded,
          stateRank != null ? '#$stateRank' : '-',
          driverState.isNotEmpty ? driverState : 'state_rank'.tr(),
          AppColors.success,
        ),

        // USA Rank
        _buildStatItem(
          Icons.emoji_events_rounded,
          usaRank != null ? '#$usaRank' : '-',
          'USA',
          AppColors.warning,
        ),
      ],
    ),
  );
}

// Función para etiquetar el rating
String _getRatingLabel(double rating) {
  if (rating >= 4.8) return 'rating_excellent'.tr();
  if (rating >= 4.5) return 'rating_very_good'.tr();
  if (rating >= 4.0) return 'rating_good'.tr();
  if (rating >= 3.5) return 'rating_regular'.tr();
  return 'rating_improve'.tr();
}
```

**Vista:**
```
┌──────────────────────────────────┐
│  4.8        #1         #12       │
│  ⭐        🏆         🏅        │
│ rating     AZ         USA        │
└──────────────────────────────────┘
```

### 2. **RideModel - Soporte para Privacidad**

#### Archivo
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro driver flutter\toro_driver\lib\src\models\ride_model.dart`

#### Cambios
```dart
class RideModel {
  final String passengerName;
  final String? passengerImageUrl;

  // Campos de privacidad
  final bool hidePassengerName;
  final bool hidePassengerPhoto;

  // Getters conscientes de privacidad
  String get displayName =>
    hidePassengerName ? 'Anonymous Customer' : passengerName;

  String? get displayImageUrl =>
    hidePassengerPhoto ? null : passengerImageUrl;

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      passengerName: json['passenger_name'] as String? ?? 'Unknown',
      passengerImageUrl: json['passenger_image_url'] as String?,

      // Soporta múltiples formatos de campo
      hidePassengerName: json['hide_passenger_name'] as bool? ??
                         json['user_hide_name'] as bool? ?? false,
      hidePassengerPhoto: json['hide_passenger_photo'] as bool? ??
                          json['user_hide_photo'] as bool? ?? false,
      // ...
    );
  }
}
```

**Comportamiento:**
- Si `hide_name = true` → el conductor ve "Anonymous Customer"
- Si `hide_photo = true` → el conductor ve avatar genérico
- Los getters `displayName` y `displayImageUrl` manejan la lógica automáticamente

---

## 📱 MODIFICACIONES EN CLIENT APP (toro)

### 1. **Settings Screen - Controles de Privacidad**

#### Archivo
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro\lib\features\settings\settings_screen.dart`

#### Cambios Completos
```dart
class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Estados de privacidad
  bool hideName = false;
  bool hidePhoto = false;
  bool isLoadingPrivacy = true;

  @override
  void initState() {
    super.initState();
    _loadPrivacySettings();
  }

  // Cargar preferencias de privacidad desde Supabase
  Future<void> _loadPrivacySettings() async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) {
        setState(() => isLoadingPrivacy = false);
        return;
      }

      final response = await supabase
          .from('user_preferences')
          .select('hide_name, hide_photo')
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        setState(() {
          hideName = response['hide_name'] as bool? ?? false;
          hidePhoto = response['hide_photo'] as bool? ?? false;
          isLoadingPrivacy = false;
        });
      } else {
        // Crear entrada por defecto
        await supabase.from('user_preferences').insert({
          'user_id': userId,
          'hide_name': false,
          'hide_photo': false,
        });
        setState(() => isLoadingPrivacy = false);
      }
    } catch (e) {
      AppLogger.error('Error loading privacy settings: $e');
      setState(() => isLoadingPrivacy = false);
    }
  }

  // Actualizar configuración individual
  Future<void> _updatePrivacySetting(String field, bool value) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      if (userId == null) return;

      await supabase
          .from('user_preferences')
          .update({field: value})
          .eq('user_id', userId);

      // Mostrar confirmación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10),
              Text('Privacidad actualizada'),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
    } catch (e) {
      AppLogger.error('Error updating privacy: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // ... otras secciones ...

          // Sección de Privacidad
          _buildSettingsCard(
            title: 'Privacidad',
            icon: Icons.shield,
            children: [
              _buildSwitchTile(
                title: 'Ocultar mi nombre',
                subtitle: 'Los conductores verán "Cliente Anónimo"',
                value: hideName,
                icon: Icons.person_off,
                onChanged: (v) async {
                  setState(() => hideName = v);
                  await _updatePrivacySetting('hide_name', v);
                },
                enabled: !isLoadingPrivacy,
              ),
              _buildSwitchTile(
                title: 'Ocultar mi foto',
                subtitle: 'Los conductores verán un avatar genérico',
                value: hidePhoto,
                icon: Icons.hide_image,
                onChanged: (v) async {
                  setState(() => hidePhoto = v);
                  await _updatePrivacySetting('hide_photo', v);
                },
                enabled: !isLoadingPrivacy,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

**Vista UI:**
```
┌─────────────────────────────────────┐
│ 🛡️  Privacidad                     │
│                                     │
│ 🙍  Ocultar mi nombre         [ON]  │
│     Los conductores verán           │
│     "Cliente Anónimo"               │
│                                     │
│ 🖼️  Ocultar mi foto           [OFF] │
│     Los conductores verán un        │
│     avatar genérico                 │
└─────────────────────────────────────┘
```

---

## 🌐 MODIFICACIONES EN ADMIN WEB PANEL

### 1. **Driver Rankings Screen - Columna de Reviews**

#### Archivo
📁 `c:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro\lib\features\admin\admin_driver_rankings_screen.dart`

#### Cambios en `_loadDrivers()`
```dart
Future<void> _loadDrivers() async {
  setState(() => isLoading = true);

  try {
    // 1. Cargar datos de conductores
    final driversResponse = await supabase
        .from('drivers')
        .select('*')
        .order('usa_rank', ascending: true);

    // 2. Cargar datos de reseñas agregadas
    final reviewsResponse = await supabase
        .from('driver_reviews_summary')
        .select('*');

    // 3. Crear mapa de reseñas por driver_id
    final reviewsMap = <String, Map<String, dynamic>>{};
    for (var r in (reviewsResponse as List)) {
      reviewsMap[r['driver_id'] as String] = r;
    }

    // 4. Combinar datos
    final List<Map<String, dynamic>> driversList = [];
    for (var d in (driversResponse as List)) {
      final driverData = Map<String, dynamic>.from(d);
      final reviews = reviewsMap[driverData['id'] as String];

      driverData['total_reviews'] = reviews?['total_reviews'] as int? ?? 0;
      driverData['positive_reviews'] = reviews?['positive_reviews'] as int? ?? 0;
      driverData['negative_reviews'] = reviews?['negative_reviews'] as int? ?? 0;
      driverData['avg_rating'] = reviews?['avg_rating'] as double?;

      driversList.add(driverData);
    }

    setState(() {
      drivers = driversList;
      filteredDrivers = driversList;
      isLoading = false;
    });
  } catch (e) {
    setState(() => isLoading = false);
  }
}
```

#### Nuevo Header de Columna
```dart
DataColumn(
  label: Text('REVIEWS', style: _headerStyle),
),
```

#### Nuevo Cell de Reviews
```dart
Widget _buildReviewsCell(Map<String, dynamic> driver) {
  final totalReviews = driver['total_reviews'] as int? ?? 0;
  final positiveReviews = driver['positive_reviews'] as int? ?? 0;
  final negativeReviews = driver['negative_reviews'] as int? ?? 0;

  return Column(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      // Total de reseñas
      Text(
        '$totalReviews',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),

      if (totalReviews > 0) ...[
        SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Positivas 👍
            Icon(Icons.thumb_up, size: 14, color: Colors.green),
            SizedBox(width: 2),
            Text(
              '$positiveReviews',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
            SizedBox(width: 8),

            // Negativas 👎
            Icon(Icons.thumb_down, size: 14, color: Colors.red),
            SizedBox(width: 2),
            Text(
              '$negativeReviews',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
      ],
    ],
  );
}
```

#### Tabla Final
```dart
DataTable(
  columns: [
    DataColumn(label: Text('RANK')),
    DataColumn(label: Text('DRIVER')),
    DataColumn(label: Text('RATING')),
    DataColumn(label: Text('ACCEPTANCE')),
    DataColumn(label: Text('TOTAL RIDES')),
    DataColumn(label: Text('STATE RANK')),
    DataColumn(label: Text('REVIEWS')),  // ← NUEVO
    DataColumn(label: Text('STATUS')),
  ],
  rows: filteredDrivers.map((driver) {
    return DataRow(
      cells: [
        DataCell(_buildRankCell(driver)),
        DataCell(_buildDriverCell(driver)),
        DataCell(_buildRatingCell(driver)),
        DataCell(_buildAcceptanceCell(driver)),
        DataCell(_buildTotalRidesCell(driver)),
        DataCell(_buildStateRankCell(driver)),
        DataCell(_buildReviewsCell(driver)),  // ← NUEVO
        DataCell(_buildStatusCell(driver)),
      ],
    );
  }).toList(),
)
```

**Vista de Columna REVIEWS:**
```
REVIEWS
───────
   15
👍 12  👎 3

   42
👍 39  👎 3

   8
👍 6   👎 2
```

---

## 📁 ESTRUCTURA DE ARCHIVOS MODIFICADOS

```
toro-rider/
├── toro/  (CLIENT APP)
│   ├── lib/
│   │   └── features/
│   │       ├── settings/
│   │       │   └── settings_screen.dart         ✏️ MODIFICADO - Privacy toggles
│   │       └── admin/
│   │           └── admin_driver_rankings_screen.dart  ✏️ MODIFICADO - REVIEWS column
│   └── supabase/
│       └── migrations/
│           ├── 20260115_user_privacy_settings_v2.sql      ✅ NUEVO
│           ├── 20260115_driver_reviews_simple.sql         ✅ NUEVO
│           └── 20260115_driver_reviews_system_fixed.sql   ✅ NUEVO
│
└── toro_driver/  (DRIVER APP)
    └── lib/
        └── src/
            ├── models/
            │   └── ride_model.dart              ✏️ MODIFICADO - Privacy support
            └── screens/
                └── profile_screen.dart          ✏️ MODIFICADO - Rating display
```

---

## 🔄 FLUJO COMPLETO DE FUNCIONALIDAD

### 1. **Usuario Activa Privacidad**
```
Cliente App (settings_screen.dart)
  ↓
Toggle "Ocultar mi nombre" = ON
  ↓
UPDATE user_preferences SET hide_name = true WHERE user_id = 'xxx'
  ↓
Base de Datos actualizada
```

### 2. **Conductor Recibe Viaje**
```
Driver App recibe nuevo viaje
  ↓
RideModel.fromJson() lee:
  - hide_passenger_name = true
  - hide_passenger_photo = false
  ↓
Getters devuelven:
  - displayName = "Anonymous Customer"
  - displayImageUrl = "https://..."
  ↓
UI muestra "Anonymous Customer" con foto real
```

### 3. **Cliente Deja Reseña**
```
Cliente completa viaje
  ↓
Pantalla de reseña (pendiente implementar)
  ↓
INSERT INTO driver_reviews (
  driver_id, user_id, rating, driving_rating, ...
)
  ↓
Trigger set_review_type() → Calcula 'positive'/'neutral'/'negative'
  ↓
Trigger update_driver_rating_from_reviews() → Actualiza drivers.rating
  ↓
Trigger trigger_recalculate_rankings() → Recalcula rankings
```

### 4. **Admin Ve Rankings**
```
Admin Web Panel
  ↓
admin_driver_rankings_screen.dart
  ↓
Carga drivers + driver_reviews_summary
  ↓
Muestra tabla con columna REVIEWS:
  - Total: 15
  - 👍 12
  - 👎 3
```

---

## 📊 CONSULTAS SQL ÚTILES

### Ver Rankings de Conductores
```sql
SELECT
  full_name,
  state,
  acceptance_rate,
  state_rank,
  usa_rank,
  rating,
  total_rides
FROM drivers
WHERE state = 'AZ'
ORDER BY state_rank ASC;
```

### Ver Resumen de Reseñas de un Conductor
```sql
SELECT *
FROM driver_reviews_summary
WHERE driver_id = 'driver-uuid-here';
```

### Ver Reseñas Detalladas
```sql
SELECT
  dr.*,
  u.email as user_email
FROM driver_reviews dr
LEFT JOIN auth.users u ON dr.user_id = u.id
WHERE dr.driver_id = 'driver-uuid-here'
ORDER BY dr.created_at DESC;
```

### Top 10 Conductores Mejor Calificados
```sql
SELECT
  d.full_name,
  d.state,
  s.avg_rating,
  s.total_reviews,
  s.positive_percentage
FROM drivers d
JOIN driver_reviews_summary s ON d.id = s.driver_id
WHERE s.total_reviews >= 5
ORDER BY s.avg_rating DESC, s.total_reviews DESC
LIMIT 10;
```

### Conductores que Necesitan Atención
```sql
SELECT
  d.full_name,
  s.avg_rating,
  s.negative_percentage,
  s.negative_reviews,
  s.top_negative_tags
FROM drivers d
JOIN driver_reviews_summary s ON d.id = s.driver_id
WHERE s.negative_percentage > 20
  AND s.total_reviews >= 5
ORDER BY s.negative_percentage DESC;
```

---

## ✅ ESTADO DE IMPLEMENTACIÓN

### ✅ COMPLETADO
- [x] Sistema de rankings (state_rank + usa_rank)
- [x] Triggers automáticos para rankings
- [x] Sistema de reseñas (driver_reviews)
- [x] Vista agregada (driver_reviews_summary)
- [x] Triggers para calcular review_type
- [x] Triggers para actualizar rating de conductor
- [x] Sistema de privacidad (user_preferences)
- [x] UI de privacidad en cliente (settings_screen.dart)
- [x] Soporte de privacidad en driver app (ride_model.dart)
- [x] Display de rating en driver profile (profile_screen.dart)
- [x] Columna REVIEWS en admin panel (admin_driver_rankings_screen.dart)

### 🔄 PENDIENTE
- [ ] UI en cliente para enviar reseñas después del viaje
- [ ] Pantalla de detalle de reseñas en driver app
- [ ] Dashboard de analytics de reseñas en admin panel
- [ ] Notificaciones cuando un conductor recibe una reseña
- [ ] Sistema de moderación de reseñas en admin panel

---

## 📚 DOCUMENTACIÓN ADICIONAL

Ver archivos:
- 📄 `DRIVER_REVIEWS_README.md` - Documentación completa del sistema de reseñas
- 📄 `20260115_driver_reviews_simple.sql` - Migración de base de datos
- 📄 `20260115_user_privacy_settings_v2.sql` - Migración de privacidad

---

**Generado:** 2026-01-15
**Autor:** Claude AI Assistant
**Proyecto:** Toro Rider & Driver System
