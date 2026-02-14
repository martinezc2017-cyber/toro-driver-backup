-- ============================================================================
-- MIGRACION: Reportes de Abuso, Registros de Viaje y Credenciales de Usuario
-- Fecha: 2026-02-09
-- Descripcion: Crea las tablas de reportes de abuso para eventos turisticos,
--              registros de viaje detallados y sistema de credenciales/insignias.
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. TABLA DE REPORTES DE ABUSO
-- Permite a los usuarios reportar incidentes durante eventos turisticos.
-- NOTA: La referencia a tourism_events se maneja con ON DELETE SET NULL
--       solo si la tabla existe. Se usa UUID plano como respaldo seguro.
-- ============================================================================

CREATE TABLE IF NOT EXISTS tourism_abuse_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID,  -- Referencia logica a tourism_events(id), FK se agrega cuando exista la tabla
  reporter_id UUID NOT NULL,
  reported_user_id UUID,

  report_type TEXT NOT NULL CHECK (report_type IN (
    'driver_abuse', 'organizer_abuse', 'passenger_abuse',
    'safety_issue', 'pricing_fraud', 'harassment',
    'vehicle_condition', 'route_deviation', 'other'
  )),

  severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'dismissed', 'escalated')),

  description TEXT NOT NULL,
  evidence_urls TEXT[] DEFAULT '{}',

  admin_notes TEXT,
  resolved_by UUID,
  resolved_at TIMESTAMPTZ,
  resolution TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agregar FK a tourism_events si la tabla ya existe
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tourism_events' AND table_schema = 'public') THEN
    ALTER TABLE tourism_abuse_reports
      ADD CONSTRAINT fk_abuse_reports_event
      FOREIGN KEY (event_id) REFERENCES tourism_events(id) ON DELETE SET NULL;
  END IF;
END
$$;


-- ============================================================================
-- 2. TABLA DE REGISTROS DE VIAJE
-- Almacena un registro detallado de cada viaje realizado en eventos turisticos.
-- ============================================================================

CREATE TABLE IF NOT EXISTS tourism_trip_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL,  -- Referencia logica a tourism_events(id), FK se agrega cuando exista la tabla
  user_id UUID NOT NULL,
  user_role TEXT NOT NULL CHECK (user_role IN ('passenger', 'driver', 'organizer')),

  -- Ubicacion de recogida
  pickup_address TEXT,
  pickup_lat DOUBLE PRECISION,
  pickup_lng DOUBLE PRECISION,

  -- Ubicacion de destino
  dropoff_address TEXT,
  dropoff_lat DOUBLE PRECISION,
  dropoff_lng DOUBLE PRECISION,

  -- Metricas del viaje
  km_traveled NUMERIC(8,2),
  price_paid NUMERIC(10,2),
  price_per_km NUMERIC(8,2),

  -- Tiempos del viaje
  boarded_at TIMESTAMPTZ,
  exited_at TIMESTAMPTZ,
  duration_minutes INTEGER,

  -- Notas personales del usuario
  personal_notes TEXT,

  -- Datos desnormalizados del evento para consulta rapida
  event_name TEXT,
  event_date DATE,
  route_summary TEXT,
  driver_name TEXT,
  organizer_name TEXT,
  vehicle_name TEXT,

  -- Referencia a resena (si existe)
  review_id UUID,

  -- Informacion de pago
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'refunded', 'disputed')),
  payment_method TEXT,

  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Agregar FK a tourism_events si la tabla ya existe
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tourism_events' AND table_schema = 'public') THEN
    ALTER TABLE tourism_trip_records
      ADD CONSTRAINT fk_trip_records_event
      FOREIGN KEY (event_id) REFERENCES tourism_events(id) ON DELETE CASCADE;
  END IF;
END
$$;


-- ============================================================================
-- 3. TABLA DE CREDENCIALES / INSIGNIAS DE USUARIO
-- Sistema de gamificacion que otorga insignias por logros en viajes turisticos.
-- ============================================================================

CREATE TABLE IF NOT EXISTS tourism_user_credentials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  user_role TEXT NOT NULL CHECK (user_role IN ('passenger', 'driver', 'organizer')),

  credential_type TEXT NOT NULL CHECK (credential_type IN (
    'trips_completed', 'events_organized', 'events_driven',
    'five_star_rating', 'top_rated_driver', 'top_rated_organizer',
    'frequent_traveler', 'safe_driver', 'verified_organizer',
    'first_trip', 'first_event', 'km_milestone'
  )),

  title TEXT NOT NULL,
  description TEXT,
  icon_name TEXT,
  earned_at TIMESTAMPTZ DEFAULT NOW(),
  stat_value INTEGER DEFAULT 0,
  is_public BOOLEAN DEFAULT true,
  share_code TEXT UNIQUE,

  created_at TIMESTAMPTZ DEFAULT NOW()
);


-- ============================================================================
-- 4. INDICES
-- Indices para optimizar las consultas mas frecuentes.
-- ============================================================================

-- Indices para reportes de abuso
CREATE INDEX idx_abuse_reports_event_id ON tourism_abuse_reports(event_id);
CREATE INDEX idx_abuse_reports_reporter_id ON tourism_abuse_reports(reporter_id);
CREATE INDEX idx_abuse_reports_reported_user ON tourism_abuse_reports(reported_user_id);
CREATE INDEX idx_abuse_reports_status ON tourism_abuse_reports(status);
CREATE INDEX idx_abuse_reports_severity ON tourism_abuse_reports(severity);
CREATE INDEX idx_abuse_reports_created ON tourism_abuse_reports(created_at DESC);

-- Indices para registros de viaje
CREATE INDEX idx_trip_records_event ON tourism_trip_records(event_id);
CREATE INDEX idx_trip_records_user ON tourism_trip_records(user_id);
CREATE INDEX idx_trip_records_role ON tourism_trip_records(user_role);
CREATE INDEX idx_trip_records_date ON tourism_trip_records(event_date DESC);
CREATE INDEX idx_trip_records_created ON tourism_trip_records(created_at DESC);

-- Indices para credenciales de usuario
CREATE INDEX idx_credentials_user ON tourism_user_credentials(user_id);
CREATE INDEX idx_credentials_type ON tourism_user_credentials(credential_type);
CREATE INDEX idx_credentials_share ON tourism_user_credentials(share_code) WHERE share_code IS NOT NULL;


-- ============================================================================
-- 5. POLITICAS DE SEGURIDAD A NIVEL DE FILA (RLS)
-- ============================================================================

-- Habilitar RLS en todas las tablas nuevas
ALTER TABLE tourism_abuse_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE tourism_trip_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE tourism_user_credentials ENABLE ROW LEVEL SECURITY;

-- --- Reportes de abuso ---
-- Los usuarios pueden crear sus propios reportes
CREATE POLICY "Users can create abuse reports" ON tourism_abuse_reports
  FOR INSERT WITH CHECK (auth.uid() = reporter_id);

-- Los usuarios pueden ver sus propios reportes
CREATE POLICY "Users can view own reports" ON tourism_abuse_reports
  FOR SELECT USING (auth.uid() = reporter_id);

-- El rol de servicio puede gestionar todos los reportes
CREATE POLICY "Service role manages all reports" ON tourism_abuse_reports
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- --- Registros de viaje ---
-- Los usuarios pueden ver sus propios viajes
CREATE POLICY "Users can view own trips" ON tourism_trip_records
  FOR SELECT USING (auth.uid() = user_id);

-- Los usuarios pueden actualizar las notas de sus propios viajes
CREATE POLICY "Users can update own trip notes" ON tourism_trip_records
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- El rol de servicio puede gestionar todos los viajes
CREATE POLICY "Service role manages all trips" ON tourism_trip_records
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');

-- --- Credenciales de usuario ---
-- Los usuarios pueden ver sus propias credenciales
CREATE POLICY "Users can view own credentials" ON tourism_user_credentials
  FOR SELECT USING (auth.uid() = user_id);

-- Las credenciales publicas son visibles para todos los usuarios autenticados
CREATE POLICY "Public credentials visible to all" ON tourism_user_credentials
  FOR SELECT USING (is_public = true);

-- El rol de servicio puede gestionar todas las credenciales
CREATE POLICY "Service role manages credentials" ON tourism_user_credentials
  FOR ALL USING (auth.jwt() ->> 'role' = 'service_role');


-- ============================================================================
-- 6. FUNCIONES Y TRIGGERS
-- ============================================================================

-- --------------------------------------------------------------------------
-- 6a. Auto-escalar reportes de abuso criticos
-- Cuando se inserta un reporte con severidad 'critical', se cambia
-- automaticamente su estado a 'escalated' y se notifica a los administradores.
-- NOTA: La tabla notifications usa 'body' (no 'message') y 'driver_id' como
--       referencia al usuario. Se insertan notificaciones para los primeros
--       5 conductores verificados como aproximacion a admins.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_escalate_critical_abuse()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.severity = 'critical' THEN
    NEW.status := 'escalated';

    -- Insertar notificacion para conductores verificados (admins)
    -- NOTA: La tabla drivers no tiene columna 'role'. Se usa is_verified
    -- como criterio de seleccion. Ajustar cuando se agregue un campo de rol.
    INSERT INTO notifications (driver_id, title, body, data, created_at)
    SELECT
      d.id,
      'ALERTA: Reporte Critico',
      'Se ha recibido un reporte de abuso critico que requiere atencion inmediata.',
      jsonb_build_object(
        'type', 'abuse_report',
        'report_id', NEW.id,
        'severity', NEW.severity,
        'report_type', NEW.report_type
      ),
      NOW()
    FROM drivers d
    WHERE d.is_verified = TRUE AND d.is_active = TRUE
    LIMIT 5;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_escalate_critical_abuse
  BEFORE INSERT ON tourism_abuse_reports
  FOR EACH ROW
  EXECUTE FUNCTION fn_escalate_critical_abuse();


-- --------------------------------------------------------------------------
-- 6b. Verificar hitos de credenciales despues de registrar un viaje
-- Al insertar un nuevo registro de viaje, se revisan los hitos acumulados
-- del usuario y se otorgan credenciales automaticamente.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_check_credential_milestones()
RETURNS TRIGGER AS $$
DECLARE
  trip_count INTEGER;
  total_km NUMERIC;
BEGIN
  -- Contar viajes completados para este usuario y rol
  SELECT COUNT(*), COALESCE(SUM(km_traveled), 0)
  INTO trip_count, total_km
  FROM tourism_trip_records
  WHERE user_id = NEW.user_id AND user_role = NEW.user_role;

  -- Credencial de primer viaje
  IF trip_count = 1 THEN
    INSERT INTO tourism_user_credentials (user_id, user_role, credential_type, title, description, icon_name, stat_value)
    VALUES (NEW.user_id, NEW.user_role, 'first_trip', 'Primer Viaje', 'Completaste tu primer viaje de turismo', 'emoji_events', 1)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Credencial de viajero frecuente (10+ viajes)
  IF trip_count >= 10 THEN
    INSERT INTO tourism_user_credentials (user_id, user_role, credential_type, title, description, icon_name, stat_value)
    VALUES (NEW.user_id, NEW.user_role, 'frequent_traveler', 'Viajero Frecuente', 'Has completado 10+ viajes de turismo', 'flight', trip_count)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Hito de kilometros: 100 km
  IF total_km >= 100 THEN
    INSERT INTO tourism_user_credentials (user_id, user_role, credential_type, title, description, icon_name, stat_value)
    VALUES (NEW.user_id, NEW.user_role, 'km_milestone', '100 km Recorridos', 'Has viajado mas de 100 km', 'directions_car', total_km::integer)
    ON CONFLICT DO NOTHING;
  END IF;

  -- Hito de kilometros: 500 km
  IF total_km >= 500 THEN
    INSERT INTO tourism_user_credentials (user_id, user_role, credential_type, title, description, icon_name, stat_value)
    VALUES (NEW.user_id, NEW.user_role, 'km_milestone', '500 km Recorridos', 'Has viajado mas de 500 km', 'explore', total_km::integer)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_credentials
  AFTER INSERT ON tourism_trip_records
  FOR EACH ROW
  EXECUTE FUNCTION fn_check_credential_milestones();


-- --------------------------------------------------------------------------
-- 6c. Triggers de auto-actualizacion de updated_at
-- Reutiliza la funcion update_updated_at_column() ya existente en
-- 001_initial_schema.sql. NO se recrea aqui.
-- --------------------------------------------------------------------------

CREATE TRIGGER update_abuse_reports_updated_at
  BEFORE UPDATE ON tourism_abuse_reports
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trip_records_updated_at
  BEFORE UPDATE ON tourism_trip_records
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();


-- ============================================================================
-- 7. VISTAS ADMINISTRATIVAS
-- Las vistas que dependen de tourism_events se crean condicionalmente.
-- Si tourism_events no existe, se crean versiones sin JOIN que usan los
-- datos desnormalizados de tourism_trip_records.
-- ============================================================================

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'tourism_events' AND table_schema = 'public') THEN
    -- Version completa con JOIN a tourism_events

    -- Vista para el panel de administracion de reportes de abuso
    EXECUTE '
      CREATE OR REPLACE VIEW v_admin_abuse_reports AS
      SELECT
        r.*,
        te.name as event_name,
        te.event_date,
        te.route_name
      FROM tourism_abuse_reports r
      LEFT JOIN tourism_events te ON te.id = r.event_id
      ORDER BY
        CASE r.severity
          WHEN ''critical'' THEN 1
          WHEN ''high'' THEN 2
          WHEN ''medium'' THEN 3
          WHEN ''low'' THEN 4
        END,
        r.created_at DESC
    ';

    -- Vista para estadisticas de viajes por evento
    EXECUTE '
      CREATE OR REPLACE VIEW v_admin_trip_stats AS
      SELECT
        te.id as event_id,
        te.name as event_name,
        te.event_date,
        COUNT(tr.id) as total_trips,
        AVG(tr.km_traveled)::NUMERIC(8,2) as avg_km,
        SUM(tr.price_paid)::NUMERIC(10,2) as total_revenue,
        AVG(tr.price_paid)::NUMERIC(10,2) as avg_price,
        COUNT(CASE WHEN tr.payment_status = ''paid'' THEN 1 END) as paid_count,
        COUNT(CASE WHEN tr.payment_status = ''disputed'' THEN 1 END) as disputed_count
      FROM tourism_events te
      LEFT JOIN tourism_trip_records tr ON tr.event_id = te.id
      GROUP BY te.id, te.name, te.event_date
      ORDER BY te.event_date DESC
    ';

  ELSE
    -- Version sin tourism_events (usa datos desnormalizados)
    RAISE NOTICE 'AVISO: tourism_events no existe aun. Las vistas admin se crean sin JOINs a esa tabla. Recrear cuando tourism_events este disponible.';

    -- Vista de reportes de abuso sin JOIN externo
    EXECUTE '
      CREATE OR REPLACE VIEW v_admin_abuse_reports AS
      SELECT
        r.*,
        NULL::TEXT as event_name,
        NULL::DATE as event_date,
        NULL::TEXT as route_name
      FROM tourism_abuse_reports r
      ORDER BY
        CASE r.severity
          WHEN ''critical'' THEN 1
          WHEN ''high'' THEN 2
          WHEN ''medium'' THEN 3
          WHEN ''low'' THEN 4
        END,
        r.created_at DESC
    ';

    -- Vista de estadisticas usando datos desnormalizados de trip_records
    EXECUTE '
      CREATE OR REPLACE VIEW v_admin_trip_stats AS
      SELECT
        tr.event_id,
        tr.event_name,
        tr.event_date,
        COUNT(tr.id) as total_trips,
        AVG(tr.km_traveled)::NUMERIC(8,2) as avg_km,
        SUM(tr.price_paid)::NUMERIC(10,2) as total_revenue,
        AVG(tr.price_paid)::NUMERIC(10,2) as avg_price,
        COUNT(CASE WHEN tr.payment_status = ''paid'' THEN 1 END) as paid_count,
        COUNT(CASE WHEN tr.payment_status = ''disputed'' THEN 1 END) as disputed_count
      FROM tourism_trip_records tr
      GROUP BY tr.event_id, tr.event_name, tr.event_date
      ORDER BY tr.event_date DESC
    ';
  END IF;
END
$$;

-- Vista de credenciales publicas para compartir (no depende de tourism_events)
CREATE OR REPLACE VIEW v_user_credentials_public AS
SELECT
  c.id,
  c.user_id,
  c.user_role,
  c.credential_type,
  c.title,
  c.description,
  c.icon_name,
  c.earned_at,
  c.stat_value,
  c.share_code
FROM tourism_user_credentials c
WHERE c.is_public = true;


-- ============================================================================
-- 8. HABILITAR REALTIME
-- Permite suscripciones en tiempo real para reportes de abuso y viajes.
-- ============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE tourism_abuse_reports;
ALTER PUBLICATION supabase_realtime ADD TABLE tourism_trip_records;

COMMIT;
