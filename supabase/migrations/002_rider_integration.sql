-- ============================================
-- TORO RIDER - Integration Schema
-- Extends the driver schema with rider/package delivery
-- ============================================

-- ============================================
-- ADDITIONAL ENUM TYPES
-- ============================================

CREATE TYPE service_type AS ENUM ('normal', 'express', 'carpoolPackage');
CREATE TYPE package_size AS ENUM ('small', 'medium', 'large');
CREATE TYPE delivery_status AS ENUM ('draft', 'pending', 'accepted', 'driverEnRoute', 'pickedUp', 'inTransit', 'delivered', 'cancelled');
CREATE TYPE payment_status AS ENUM ('pending', 'authorized', 'captured', 'failed', 'refunded');
CREATE TYPE delivery_location AS ENUM ('frontDoor', 'backDoor', 'sideDoor', 'lobby', 'mailroom', 'other');

-- ============================================
-- PROFILES TABLE (for riders/users)
-- ============================================

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    phone TEXT,
    avatar_url TEXT,
    mood_emoji TEXT,
    mood_text TEXT,
    mood_percentage INTEGER DEFAULT 50,
    rank_state INTEGER DEFAULT 0,
    rank_usa INTEGER DEFAULT 0,
    total_deliveries INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PACKAGE DELIVERIES TABLE (Main table for package rides)
-- ============================================

CREATE TABLE public.package_deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    visa_trip_number TEXT UNIQUE, -- TORO-XXXXXX format for IRS
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    service_type service_type DEFAULT 'normal',

    -- Pickup info
    pickup_address TEXT NOT NULL,
    pickup_lat DOUBLE PRECISION NOT NULL,
    pickup_lng DOUBLE PRECISION NOT NULL,
    pickup_time TIMESTAMPTZ NOT NULL,

    -- Destination info
    destination_address TEXT NOT NULL,
    destination_lat DOUBLE PRECISION NOT NULL,
    destination_lng DOUBLE PRECISION NOT NULL,

    -- Package info
    package_description TEXT,
    photo_url TEXT,
    size package_size DEFAULT 'medium',
    package_quantity INTEGER DEFAULT 1,
    driver_notes TEXT,
    delivery_location delivery_location DEFAULT 'frontDoor',
    other_location_details TEXT,
    sender_name TEXT NOT NULL,
    recipient_name TEXT NOT NULL,

    -- Driver info (when assigned)
    driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
    driver_lat DOUBLE PRECISION,
    driver_lng DOUBLE PRECISION,
    eta_minutes INTEGER,

    -- Pricing (for IRS reporting)
    estimated_price DECIMAL(10,2) NOT NULL,
    final_price DECIMAL(10,2),
    distance_miles DECIMAL(10,2) NOT NULL,
    estimated_minutes INTEGER NOT NULL,
    tip_amount DECIMAL(10,2) DEFAULT 0.00,
    platform_fee DECIMAL(10,2) DEFAULT 0.00,
    driver_earnings DECIMAL(10,2) DEFAULT 0.00,
    cancellation_fee DECIMAL(10,2) DEFAULT 0.00,

    -- Payment
    payment_status payment_status DEFAULT 'pending',
    stripe_payment_intent_id TEXT,
    stripe_charge_id TEXT,

    -- Status
    status delivery_status DEFAULT 'draft',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    picked_up_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason TEXT,

    -- Customer mood (for driver visibility)
    customer_mood_emoji TEXT,
    customer_mood_text TEXT,
    customer_mood_percentage INTEGER,
    customer_rank_state INTEGER,
    customer_rank_usa INTEGER,

    -- Route polyline
    route_points JSONB DEFAULT '[]'::jsonb,

    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Generate visa_trip_number automatically
CREATE OR REPLACE FUNCTION generate_visa_trip_number()
RETURNS TRIGGER AS $$
BEGIN
    NEW.visa_trip_number := 'TORO-' || UPPER(SUBSTRING(NEW.id::text, 1, 6));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_visa_trip_number
    BEFORE INSERT ON public.package_deliveries
    FOR EACH ROW
    WHEN (NEW.visa_trip_number IS NULL)
    EXECUTE FUNCTION generate_visa_trip_number();

-- Calculate fees automatically (20% platform, 80% driver)
CREATE OR REPLACE FUNCTION calculate_delivery_fees()
RETURNS TRIGGER AS $$
BEGIN
    NEW.platform_fee := NEW.estimated_price * 0.20;
    NEW.driver_earnings := NEW.estimated_price * 0.80;
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_fees
    BEFORE INSERT OR UPDATE ON public.package_deliveries
    FOR EACH ROW
    EXECUTE FUNCTION calculate_delivery_fees();

-- ============================================
-- DRIVER TICKETS TABLE (for driver app)
-- ============================================

CREATE TABLE public.driver_tickets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    delivery_id UUID REFERENCES public.package_deliveries(id) ON DELETE CASCADE,
    driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,

    -- Ticket info (snapshot for driver)
    pickup_address TEXT NOT NULL,
    pickup_lat DOUBLE PRECISION NOT NULL,
    pickup_lng DOUBLE PRECISION NOT NULL,
    destination_address TEXT NOT NULL,
    destination_lat DOUBLE PRECISION NOT NULL,
    destination_lng DOUBLE PRECISION NOT NULL,

    distance_miles DECIMAL(10,2) NOT NULL,
    estimated_minutes INTEGER NOT NULL,
    driver_earnings DECIMAL(10,2) NOT NULL,
    tip_amount DECIMAL(10,2) DEFAULT 0.00,

    package_size package_size,
    package_quantity INTEGER DEFAULT 1,
    notes TEXT,

    -- Customer mood (only if 50%+)
    customer_mood_emoji TEXT,
    customer_mood_text TEXT,

    status TEXT DEFAULT 'available',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ
);

-- ============================================
-- DELIVERY MESSAGES (chat between rider/driver)
-- ============================================

CREATE TABLE public.delivery_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    delivery_id UUID REFERENCES public.package_deliveries(id) ON DELETE CASCADE,
    sender_type TEXT NOT NULL, -- 'rider' or 'driver'
    sender_id UUID NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- IRS REPORTING TABLE (1099-K tracking)
-- ============================================

CREATE TABLE public.driver_earnings_report (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID REFERENCES public.drivers(id) ON DELETE CASCADE,
    year INTEGER NOT NULL,
    month INTEGER NOT NULL,
    total_deliveries INTEGER DEFAULT 0,
    gross_earnings DECIMAL(12,2) DEFAULT 0.00,
    tips_received DECIMAL(12,2) DEFAULT 0.00,
    platform_fees_paid DECIMAL(12,2) DEFAULT 0.00,
    net_earnings DECIMAL(12,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(driver_id, year, month)
);

-- ============================================
-- BANK ACCOUNTS TABLE (for payouts)
-- ============================================

CREATE TABLE public.bank_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    stripe_bank_account_id TEXT,
    last_four TEXT NOT NULL,
    bank_name TEXT,
    account_holder_name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- DRIVER STRIPE ACCOUNTS (Connect accounts)
-- ============================================

CREATE TABLE public.driver_stripe_accounts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID UNIQUE NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    stripe_account_id TEXT UNIQUE,
    charges_enabled BOOLEAN DEFAULT false,
    payouts_enabled BOOLEAN DEFAULT false,
    onboarding_completed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- PAYOUTS TABLE
-- ============================================

CREATE TABLE public.payouts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
    amount DECIMAL(10,2) NOT NULL,
    status TEXT DEFAULT 'pending',
    stripe_payout_id TEXT,
    bank_account_id UUID REFERENCES public.bank_accounts(id),
    processed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INDEXES for performance
-- ============================================

CREATE INDEX idx_profiles_phone ON public.profiles(phone);

CREATE INDEX idx_deliveries_user_id ON public.package_deliveries(user_id);
CREATE INDEX idx_deliveries_driver_id ON public.package_deliveries(driver_id);
CREATE INDEX idx_deliveries_status ON public.package_deliveries(status);
CREATE INDEX idx_deliveries_created_at ON public.package_deliveries(created_at DESC);
CREATE INDEX idx_deliveries_visa_trip ON public.package_deliveries(visa_trip_number);

CREATE INDEX idx_tickets_delivery_id ON public.driver_tickets(delivery_id);
CREATE INDEX idx_tickets_driver_id ON public.driver_tickets(driver_id);
CREATE INDEX idx_tickets_status ON public.driver_tickets(status);

CREATE INDEX idx_delivery_messages_delivery_id ON public.delivery_messages(delivery_id);

CREATE INDEX idx_bank_accounts_driver_id ON public.bank_accounts(driver_id);
CREATE INDEX idx_payouts_driver_id ON public.payouts(driver_id);

-- ============================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_earnings_report ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_stripe_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Package deliveries policies
CREATE POLICY "Users can view own deliveries" ON public.package_deliveries
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create deliveries" ON public.package_deliveries
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own deliveries" ON public.package_deliveries
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Drivers can view assigned deliveries" ON public.package_deliveries
    FOR SELECT USING (
        driver_id IN (SELECT id FROM public.drivers WHERE id = auth.uid())
    );

CREATE POLICY "Drivers can view pending deliveries" ON public.package_deliveries
    FOR SELECT USING (status = 'pending' AND driver_id IS NULL);

CREATE POLICY "Drivers can update assigned deliveries" ON public.package_deliveries
    FOR UPDATE USING (
        driver_id IN (SELECT id FROM public.drivers WHERE id = auth.uid())
    );

-- Driver tickets policies
CREATE POLICY "Drivers can view available tickets" ON public.driver_tickets
    FOR SELECT USING (status = 'available' OR driver_id = auth.uid());

CREATE POLICY "Drivers can update own tickets" ON public.driver_tickets
    FOR UPDATE USING (driver_id = auth.uid());

-- Messages policies
CREATE POLICY "Participants can view messages" ON public.delivery_messages
    FOR SELECT USING (
        delivery_id IN (
            SELECT id FROM public.package_deliveries
            WHERE user_id = auth.uid()
            OR driver_id = auth.uid()
        )
    );

CREATE POLICY "Participants can send messages" ON public.delivery_messages
    FOR INSERT WITH CHECK (
        delivery_id IN (
            SELECT id FROM public.package_deliveries
            WHERE user_id = auth.uid()
            OR driver_id = auth.uid()
        )
    );

-- Earnings report policies
CREATE POLICY "Drivers can view own earnings report" ON public.driver_earnings_report
    FOR SELECT USING (driver_id = auth.uid());

-- Bank accounts policies
CREATE POLICY "Drivers can manage own bank accounts" ON public.bank_accounts
    FOR ALL USING (driver_id = auth.uid());

-- Stripe accounts policies
CREATE POLICY "Drivers can view own stripe account" ON public.driver_stripe_accounts
    FOR SELECT USING (driver_id = auth.uid());

-- Payouts policies
CREATE POLICY "Drivers can view own payouts" ON public.payouts
    FOR SELECT USING (driver_id = auth.uid());

-- ============================================
-- REALTIME SUBSCRIPTIONS
-- ============================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.package_deliveries;
ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_tickets;
ALTER PUBLICATION supabase_realtime ADD TABLE public.delivery_messages;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Get available tickets for drivers in area (using Haversine formula)
CREATE OR REPLACE FUNCTION get_available_tickets(
    p_driver_lat DOUBLE PRECISION,
    p_driver_lng DOUBLE PRECISION,
    p_radius_miles DOUBLE PRECISION DEFAULT 10
)
RETURNS SETOF public.driver_tickets AS $$
BEGIN
    RETURN QUERY
    SELECT t.*
    FROM public.driver_tickets t
    WHERE t.status = 'available'
    AND (
        3959 * acos(
            cos(radians(p_driver_lat)) * cos(radians(t.pickup_lat)) *
            cos(radians(t.pickup_lng) - radians(p_driver_lng)) +
            sin(radians(p_driver_lat)) * sin(radians(t.pickup_lat))
        )
    ) <= p_radius_miles
    ORDER BY t.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Update driver location and active delivery
CREATE OR REPLACE FUNCTION update_driver_location(
    p_driver_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION
)
RETURNS void AS $$
BEGIN
    -- Update driver's location
    UPDATE public.drivers
    SET
        current_lat = p_lat,
        current_lng = p_lng,
        last_location_update = NOW(),
        updated_at = NOW()
    WHERE id = p_driver_id;

    -- Update driver_locations table
    INSERT INTO public.driver_locations (driver_id, latitude, longitude, is_online, updated_at)
    VALUES (p_driver_id, p_lat, p_lng, true, NOW())
    ON CONFLICT (driver_id)
    DO UPDATE SET
        latitude = p_lat,
        longitude = p_lng,
        updated_at = NOW();

    -- Update active package delivery if exists
    UPDATE public.package_deliveries
    SET
        driver_lat = p_lat,
        driver_lng = p_lng,
        updated_at = NOW()
    WHERE driver_id = p_driver_id
    AND status IN ('accepted', 'driverEnRoute', 'pickedUp', 'inTransit');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Accept a package delivery ticket
CREATE OR REPLACE FUNCTION accept_delivery_ticket(
    p_ticket_id UUID,
    p_driver_id UUID
)
RETURNS public.driver_tickets AS $$
DECLARE
    v_ticket public.driver_tickets;
    v_delivery_id UUID;
BEGIN
    -- Get and lock the ticket
    SELECT * INTO v_ticket
    FROM public.driver_tickets
    WHERE id = p_ticket_id AND status = 'available'
    FOR UPDATE;

    IF v_ticket IS NULL THEN
        RAISE EXCEPTION 'Ticket not available';
    END IF;

    -- Update ticket
    UPDATE public.driver_tickets
    SET
        driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW()
    WHERE id = p_ticket_id
    RETURNING * INTO v_ticket;

    -- Update the package delivery
    UPDATE public.package_deliveries
    SET
        driver_id = p_driver_id,
        status = 'accepted',
        accepted_at = NOW(),
        updated_at = NOW()
    WHERE id = v_ticket.delivery_id;

    RETURN v_ticket;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Complete a package delivery
CREATE OR REPLACE FUNCTION complete_package_delivery(
    p_delivery_id UUID,
    p_driver_id UUID
)
RETURNS public.package_deliveries AS $$
DECLARE
    v_delivery public.package_deliveries;
BEGIN
    -- Update delivery status
    UPDATE public.package_deliveries
    SET
        status = 'delivered',
        delivered_at = NOW(),
        final_price = estimated_price + tip_amount,
        payment_status = 'captured',
        updated_at = NOW()
    WHERE id = p_delivery_id AND driver_id = p_driver_id
    RETURNING * INTO v_delivery;

    IF v_delivery IS NULL THEN
        RAISE EXCEPTION 'Delivery not found or not assigned to driver';
    END IF;

    -- Update driver stats
    UPDATE public.drivers
    SET
        total_deliveries = total_deliveries + 1,
        total_earnings = total_earnings + v_delivery.driver_earnings + v_delivery.tip_amount,
        updated_at = NOW()
    WHERE id = p_driver_id;

    -- Update driver ticket
    UPDATE public.driver_tickets
    SET
        status = 'completed',
        completed_at = NOW(),
        tip_amount = v_delivery.tip_amount
    WHERE delivery_id = p_delivery_id;

    -- Record earning
    INSERT INTO public.earnings (driver_id, ride_id, type, amount, description, created_at)
    VALUES (
        p_driver_id,
        p_delivery_id,
        'rideEarning',
        v_delivery.driver_earnings,
        'Entrega completada: ' || v_delivery.visa_trip_number,
        NOW()
    );

    -- Record tip if present
    IF v_delivery.tip_amount > 0 THEN
        INSERT INTO public.earnings (driver_id, ride_id, type, amount, description, created_at)
        VALUES (
            p_driver_id,
            p_delivery_id,
            'tip',
            v_delivery.tip_amount,
            'Propina: ' || v_delivery.visa_trip_number,
            NOW()
        );
    END IF;

    -- Update monthly earnings report
    INSERT INTO public.driver_earnings_report (driver_id, year, month, total_deliveries, gross_earnings, tips_received, platform_fees_paid, net_earnings)
    VALUES (
        p_driver_id,
        EXTRACT(YEAR FROM NOW())::INTEGER,
        EXTRACT(MONTH FROM NOW())::INTEGER,
        1,
        v_delivery.estimated_price,
        v_delivery.tip_amount,
        v_delivery.platform_fee,
        v_delivery.driver_earnings + v_delivery.tip_amount
    )
    ON CONFLICT (driver_id, year, month)
    DO UPDATE SET
        total_deliveries = driver_earnings_report.total_deliveries + 1,
        gross_earnings = driver_earnings_report.gross_earnings + v_delivery.estimated_price,
        tips_received = driver_earnings_report.tips_received + v_delivery.tip_amount,
        platform_fees_paid = driver_earnings_report.platform_fees_paid + v_delivery.platform_fee,
        net_earnings = driver_earnings_report.net_earnings + v_delivery.driver_earnings + v_delivery.tip_amount,
        updated_at = NOW();

    RETURN v_delivery;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get driver's IRS 1099-K summary
CREATE OR REPLACE FUNCTION get_driver_tax_summary(
    p_driver_id UUID,
    p_year INTEGER
)
RETURNS TABLE (
    total_deliveries INTEGER,
    gross_earnings DECIMAL,
    tips_received DECIMAL,
    platform_fees DECIMAL,
    net_earnings DECIMAL,
    needs_1099k BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(der.total_deliveries), 0)::INTEGER,
        COALESCE(SUM(der.gross_earnings), 0.00),
        COALESCE(SUM(der.tips_received), 0.00),
        COALESCE(SUM(der.platform_fees_paid), 0.00),
        COALESCE(SUM(der.net_earnings), 0.00),
        COALESCE(SUM(der.gross_earnings), 0) >= 600 -- IRS threshold for 1099-K
    FROM public.driver_earnings_report der
    WHERE der.driver_id = p_driver_id
    AND der.year = p_year;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add current_lat and current_lng columns to drivers table if not exists
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'drivers' AND column_name = 'current_lat') THEN
        ALTER TABLE public.drivers ADD COLUMN current_lat DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'drivers' AND column_name = 'current_lng') THEN
        ALTER TABLE public.drivers ADD COLUMN current_lng DOUBLE PRECISION;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'drivers' AND column_name = 'last_location_update') THEN
        ALTER TABLE public.drivers ADD COLUMN last_location_update TIMESTAMPTZ;
    END IF;
END $$;

-- Index for online drivers location
CREATE INDEX IF NOT EXISTS idx_drivers_online_location
    ON public.drivers(current_lat, current_lng)
    WHERE is_online = true;
