-- ============================================
-- SQL PARA SISTEMA DE RANKING EN TORO DRIVER
-- Ejecutar en Supabase SQL Editor
-- ============================================

-- 1. Agregar columnas necesarias a la tabla drivers
ALTER TABLE drivers
ADD COLUMN IF NOT EXISTS points INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS previous_rank INTEGER,
ADD COLUMN IF NOT EXISTS state VARCHAR(50),
ADD COLUMN IF NOT EXISTS state_rank INTEGER,
ADD COLUMN IF NOT EXISTS usa_rank INTEGER;

-- 2. Actualizar puntos basados en datos existentes
-- Fórmula: (total_rides * 50) + (rating * 200) - Solo si hay viajes
UPDATE drivers
SET points = CASE
    WHEN COALESCE(total_rides, 0) > 0
    THEN COALESCE(total_rides, 0) * 50 + COALESCE(rating, 5) * 200
    ELSE 0
END
WHERE points = 0 OR points IS NULL;

-- 3. Función para calcular rankings automáticamente
CREATE OR REPLACE FUNCTION calculate_driver_rankings()
RETURNS void AS $$
BEGIN
    -- Guardar ranking anterior
    UPDATE drivers SET previous_rank = usa_rank;

    -- Calcular ranking nacional USA
    WITH ranked AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY points DESC) as rank
        FROM drivers
        WHERE status = 'active'
    )
    UPDATE drivers d
    SET usa_rank = r.rank
    FROM ranked r
    WHERE d.id = r.id;

    -- Calcular ranking por estado
    WITH state_ranked AS (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY state ORDER BY points DESC) as rank
        FROM drivers
        WHERE status = 'active' AND state IS NOT NULL
    )
    UPDATE drivers d
    SET state_rank = sr.rank
    FROM state_ranked sr
    WHERE d.id = sr.id;
END;
$$ LANGUAGE plpgsql;

-- 4. Ejecutar cálculo inicial
SELECT calculate_driver_rankings();

-- 5. Crear trigger para actualizar puntos cuando cambian los viajes
CREATE OR REPLACE FUNCTION update_driver_points()
RETURNS TRIGGER AS $$
BEGIN
    -- Recalcular puntos del driver (solo si hay viajes)
    UPDATE drivers
    SET points = CASE
        WHEN COALESCE(NEW.total_rides, 0) > 0
        THEN COALESCE(NEW.total_rides, 0) * 50 + COALESCE(NEW.rating, 5) * 200
        ELSE 0
    END
    WHERE id = NEW.id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger que se activa cuando se actualiza un driver
DROP TRIGGER IF EXISTS trigger_update_driver_points ON drivers;
CREATE TRIGGER trigger_update_driver_points
    AFTER UPDATE OF total_rides, rating ON drivers
    FOR EACH ROW
    EXECUTE FUNCTION update_driver_points();

-- 6. Job programado para recalcular rankings (ejecutar diariamente)
-- Puedes crear un cron job en Supabase o llamar manualmente:
-- SELECT calculate_driver_rankings();

-- ============================================
-- VERIFICACIÓN - Ejecutar después de setup
-- ============================================
SELECT id, name, state, points, state_rank, usa_rank, previous_rank
FROM drivers
WHERE status = 'active'
ORDER BY usa_rank ASC
LIMIT 20;
