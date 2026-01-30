-- ============================================
-- TORO - Driver Rankings (Leaderboard)
-- Similar to Tip Rankings but for drivers
-- ============================================

-- ============================================
-- 1. DRIVERS - Add ranking columns
-- ============================================

-- Points for ranking system
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS points INTEGER DEFAULT 0;

-- State ranking position
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS state_rank INTEGER;

-- National (USA) ranking position
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS usa_rank INTEGER;

-- Driver's state for state-based ranking
ALTER TABLE public.drivers
ADD COLUMN IF NOT EXISTS driver_state TEXT;

-- ============================================
-- 2. DRIVER_RANKINGS - Leaderboard table
-- ============================================

CREATE TABLE IF NOT EXISTS public.driver_rankings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID REFERENCES public.drivers(id) ON DELETE CASCADE UNIQUE,

    -- Performance metrics
    total_trips INTEGER DEFAULT 0,
    total_earnings DECIMAL(12,2) DEFAULT 0.00,
    total_tips DECIMAL(10,2) DEFAULT 0.00,
    average_rating DECIMAL(3,2) DEFAULT 5.00,
    acceptance_rate DECIMAL(5,2) DEFAULT 100.00,

    -- Points and ranking
    points INTEGER DEFAULT 0,
    state_rank INTEGER,
    usa_rank INTEGER,
    driver_state TEXT,

    -- Timestamps
    last_trip_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_driver_rankings_points ON public.driver_rankings(points DESC);
CREATE INDEX IF NOT EXISTS idx_driver_rankings_state ON public.driver_rankings(driver_state, points DESC);
CREATE INDEX IF NOT EXISTS idx_driver_rankings_acceptance ON public.driver_rankings(acceptance_rate DESC);

-- ============================================
-- 3. RLS POLICIES
-- ============================================

ALTER TABLE public.driver_rankings ENABLE ROW LEVEL SECURITY;

-- Everyone can view rankings (leaderboard is public)
CREATE POLICY "Anyone can view rankings" ON public.driver_rankings
    FOR SELECT USING (true);

-- ============================================
-- 4. RANKING UPDATE FUNCTION
-- ============================================

CREATE OR REPLACE FUNCTION recalculate_driver_ranks()
RETURNS void AS $$
BEGIN
    -- Update USA ranks (national)
    WITH ranked AS (
        SELECT driver_id, ROW_NUMBER() OVER (ORDER BY points DESC, total_earnings DESC) as rank
        FROM public.driver_rankings
    )
    UPDATE public.driver_rankings dr
    SET usa_rank = r.rank
    FROM ranked r
    WHERE dr.driver_id = r.driver_id;

    -- Update state ranks
    WITH state_ranked AS (
        SELECT driver_id, ROW_NUMBER() OVER (PARTITION BY driver_state ORDER BY points DESC, total_earnings DESC) as rank
        FROM public.driver_rankings
        WHERE driver_state IS NOT NULL
    )
    UPDATE public.driver_rankings dr
    SET state_rank = sr.rank
    FROM state_ranked sr
    WHERE dr.driver_id = sr.driver_id;

    -- Sync ranks back to drivers table
    UPDATE public.drivers d
    SET
        points = dr.points,
        state_rank = dr.state_rank,
        usa_rank = dr.usa_rank
    FROM public.driver_rankings dr
    WHERE d.id = dr.driver_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 5. INITIALIZE RANKINGS FROM EXISTING DRIVERS
-- ============================================

INSERT INTO public.driver_rankings (driver_id, driver_state, total_trips, total_earnings, average_rating, acceptance_rate, points)
SELECT
    d.id,
    d.driver_state,
    d.total_rides,
    d.total_earnings,
    d.rating,
    d.acceptance_rate * 100,
    d.total_rides  -- Initial points = total rides
FROM public.drivers d
WHERE NOT EXISTS (
    SELECT 1 FROM public.driver_rankings dr WHERE dr.driver_id = d.id
)
ON CONFLICT (driver_id) DO NOTHING;

-- Run initial ranking calculation
SELECT recalculate_driver_ranks();
