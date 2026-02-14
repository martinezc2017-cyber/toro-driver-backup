-- ============================================================================
-- Fix public_tourism_events view + create tourism_hidden_events table
-- 2026-02-10
-- ============================================================================

-- Drop existing view and recreate with all needed columns
DROP VIEW IF EXISTS public_tourism_events;

CREATE OR REPLACE VIEW public_tourism_events AS
SELECT
  te.id,
  te.event_name,
  te.event_description as description,
  te.event_type,
  te.status,
  te.event_date,
  te.start_time,
  te.state_code,
  te.itinerary,
  te.route_polyline,
  te.total_distance_km,

  -- ORIGEN (primer stop del itinerario)
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 0
    THEN (te.itinerary->0->>'lat')::double precision
    ELSE te.boarding_lat
  END as origin_lat,
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 0
    THEN (te.itinerary->0->>'lng')::double precision
    ELSE te.boarding_lng
  END as origin_lng,
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 0
    THEN te.itinerary->0->>'name'
    ELSE te.boarding_address
  END as origin_name,

  -- DESTINO (ultimo stop del itinerario)
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 1
    THEN (te.itinerary->jsonb_array_length(te.itinerary)-1->>'lat')::double precision
    ELSE NULL
  END as destination_lat,
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 1
    THEN (te.itinerary->jsonb_array_length(te.itinerary)-1->>'lng')::double precision
    ELSE NULL
  END as destination_lng,
  CASE WHEN jsonb_array_length(COALESCE(te.itinerary, '[]'::jsonb)) > 1
    THEN te.itinerary->jsonb_array_length(te.itinerary)-1->>'name'
    ELSE NULL
  END as destination_name,

  -- Pricing y asientos
  te.price_per_km,
  te.total_base_price as base_price_total,
  te.max_passengers,
  COALESCE((SELECT count(*)::int FROM tourism_invitations ti
   WHERE ti.event_id = te.id AND ti.status IN ('accepted', 'checked_in')), 0) as booked_seats,
  te.max_passengers - COALESCE((SELECT count(*)::int FROM tourism_invitations ti
   WHERE ti.event_id = te.id AND ti.status IN ('accepted', 'checked_in')), 0) as remaining_seats,
  te.allow_late_boarding,
  te.passenger_visibility,
  te.payment_method,
  te.currency,

  -- ORGANIZADOR - Tarjeta de Presentacion Completa
  o.id as organizer_id,
  o.company_name as organizer_name,
  o.phone as organizer_phone,
  o.contact_email as organizer_email,
  o.company_logo_url as organizer_logo_url,
  o.contact_facebook as organizer_facebook,
  o.website as organizer_website,
  o.description as organizer_description,
  o.is_verified as organizer_verified,

  -- CHOFER
  te.driver_id,
  COALESCE(d.full_name, d.name) as driver_name,
  d.phone as driver_phone,
  d.profile_image_url as driver_avatar_url,
  d.rating as driver_rating,

  -- VEHICULO
  bv.id as vehicle_id,
  bv.vehicle_name,
  bv.vehicle_type,
  bv.make as vehicle_make,
  bv.model as vehicle_model,
  bv.year as vehicle_year,
  bv.color as vehicle_color,
  bv.total_seats as vehicle_total_seats,
  bv.image_urls as vehicle_images,
  bv.amenities as vehicle_amenities,

  -- Timestamps
  te.created_at,
  te.updated_at

FROM tourism_events te
LEFT JOIN organizers o ON te.organizer_id = o.id
LEFT JOIN drivers d ON te.driver_id = d.id
LEFT JOIN bus_vehicles bv ON te.vehicle_id = bv.id
WHERE te.passenger_visibility = 'public'
  AND te.status IN ('active', 'in_progress', 'vehicle_accepted')
  AND te.event_date >= CURRENT_DATE;

-- Grant access
GRANT SELECT ON public_tourism_events TO anon, authenticated;

-- ============================================================================
-- Table: tourism_hidden_events (rider hides events they don't want to see)
-- ============================================================================
CREATE TABLE IF NOT EXISTS tourism_hidden_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  event_id uuid NOT NULL REFERENCES tourism_events(id) ON DELETE CASCADE,
  hidden_at timestamptz DEFAULT now(),
  UNIQUE(user_id, event_id)
);

ALTER TABLE tourism_hidden_events ENABLE ROW LEVEL SECURITY;

-- Users can insert/select/delete their own hidden events
CREATE POLICY "Users manage own hidden events"
  ON tourism_hidden_events FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
