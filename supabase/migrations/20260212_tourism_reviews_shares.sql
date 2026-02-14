-- ============================================================================
-- TOURISM EVENT REVIEWS & SHARES TABLES
-- Applied to remote database on 2026-02-12
-- ============================================================================

-- ============================================================================
-- 1. Tourism Event Reviews - Stores passenger reviews after trip completion
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.tourism_event_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL,
  user_id UUID NOT NULL,
  overall_rating INTEGER NOT NULL CHECK (overall_rating >= 1 AND overall_rating <= 5),
  driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5),
  organizer_rating INTEGER CHECK (organizer_rating >= 1 AND organizer_rating <= 5),
  vehicle_rating INTEGER CHECK (vehicle_rating >= 1 AND vehicle_rating <= 5),
  comment TEXT,
  improvement_tags TEXT[] DEFAULT '{}',
  would_recommend BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(event_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_tourism_reviews_event ON public.tourism_event_reviews(event_id);
CREATE INDEX IF NOT EXISTS idx_tourism_reviews_user ON public.tourism_event_reviews(user_id);

ALTER TABLE public.tourism_event_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read reviews" ON public.tourism_event_reviews;
CREATE POLICY "Users can read reviews"
  ON public.tourism_event_reviews FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can submit own review" ON public.tourism_event_reviews;
CREATE POLICY "Users can submit own review"
  ON public.tourism_event_reviews FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own review" ON public.tourism_event_reviews;
CREATE POLICY "Users can update own review"
  ON public.tourism_event_reviews FOR UPDATE
  USING (auth.uid() = user_id);

-- Enable realtime for organizer dashboard live updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.tourism_event_reviews;

-- ============================================================================
-- 2. Tourism Event Shares - Tracks share analytics (QR, WhatsApp, link)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.tourism_event_shares (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id UUID NOT NULL,
  shared_by UUID NOT NULL,
  share_method TEXT NOT NULL CHECK (share_method IN ('qr_code', 'whatsapp', 'link', 'social_media')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_tourism_shares_event ON public.tourism_event_shares(event_id);
CREATE INDEX IF NOT EXISTS idx_tourism_shares_user ON public.tourism_event_shares(shared_by);

ALTER TABLE public.tourism_event_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own shares" ON public.tourism_event_shares;
CREATE POLICY "Users can view own shares"
  ON public.tourism_event_shares FOR SELECT
  USING (auth.uid() = shared_by);

DROP POLICY IF EXISTS "Users can insert own shares" ON public.tourism_event_shares;
CREATE POLICY "Users can insert own shares"
  ON public.tourism_event_shares FOR INSERT
  WITH CHECK (auth.uid() = shared_by);

DROP POLICY IF EXISTS "Organizers can view event shares" ON public.tourism_event_shares;
CREATE POLICY "Organizers can view event shares"
  ON public.tourism_event_shares FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tourism_events te
      WHERE te.id = event_id AND te.organizer_id = auth.uid()
    )
  );
