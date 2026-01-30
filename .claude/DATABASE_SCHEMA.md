# TORO RIDER - DATABASE SCHEMA REFERENCE

> **Last Updated**: 2026-01-24
> **Total Migrations**: 177+ SQL files
> **Database**: Supabase PostgreSQL

---

## CORE TABLES

### 1. `profiles` - User Profiles
```sql
-- All app users (riders, drivers, admins)
id: uuid (PK, references auth.users)
email: text NOT NULL
full_name: text
phone: text
avatar_url: text
created_at: timestamp
updated_at: timestamp
```

### 2. `deliveries` - Package/Ride/Carpool Deliveries
```sql
-- Unified table for all service types
id: uuid (PK)
user_id: uuid (FK -> profiles)
driver_id: uuid (FK -> drivers)
service_type: text ('package', 'ride', 'carpool')
status: text ('pending', 'accepted', 'in_progress', 'delivered', 'cancelled')

-- Location fields
pickup_lat: float
pickup_lng: float
pickup_address: text
destination_lat: float
destination_lng: float
destination_address: text

-- Package specific
package_size: text
quantity: int

-- Pricing (ALL IN MILES)
distance_miles: float
estimated_minutes: int
estimated_price: float
total_price: float
tip_amount: float
state_code: text (AZ, CA, TX, etc.)

-- Payment
payment_method: text ('card', 'cash')
stripe_payment_intent_id: text

-- Financial split (calculated by Edge Functions)
driver_earnings: float
platform_commission: float
platform_commission_percent: float

-- Timestamps
created_at: timestamp
scheduled_time: timestamp
cancelled_at: timestamp
completed_at: timestamp

-- Other
notes: jsonb
waypoints: jsonb (multi-stop rides)
legs_pricing: jsonb (per-leg pricing)
```

### 3. `share_ride_bookings` - Carpool Bookings
```sql
-- Dedicated carpool/shared rides table
id: uuid (PK)
rider_id: uuid (FK -> profiles)
driver_id: uuid (FK -> drivers)

-- Trip details
origin: text (short name)
origin_address: text (full address)
origin_lat: float
origin_lng: float
destination: text (short name)
destination_address: text (full address)
destination_lat: float
destination_lng: float

-- Scheduling
pickup_time: timestamp (UTC)
arrival_time: timestamp (UTC)
estimated_duration_minutes: int

-- Capacity
seats_requested: int
filled_seats: int
max_companion_distance_km: float
max_wait_time_minutes: int

-- Status & Type
status: text ('pending', 'matched', 'confirmed', 'active', 'completed', 'cancelled')
is_carpool_commute: boolean
is_return_trip: boolean
linked_return_booking_id: uuid

-- Pricing (ALL IN MILES)
distance_miles: float
estimated_price: float
total_price: float
state_code: text

-- Financial split
driver_earnings: float
platform_fee: float
platform_fee_percent: float
driver_base: float
driver_per_mile: float
driver_per_minute: float
rider_base: float
rider_per_mile: float
rider_per_minute: float

-- Favorite driver system
favorite_driver_requested: boolean
favorite_driver_id: uuid
assignment_type: text ('pool', 'pending_favorite', 'favorite_assigned')
assignment_details: jsonb

-- Payment
stripe_payment_intent_id: text
stripe_charge_id: text

-- Recurring
recurring_days: int[] (0=Sun, 6=Sat)

-- Timestamps
created_at: timestamp
updated_at: timestamp
cancelled_at: timestamp
completed_at: timestamp
```

### 4. `drivers` - Driver Profiles
```sql
id: uuid (PK, references auth.users)
full_name: text
email: text
phone: text
status: text ('pending', 'active', 'inactive', 'suspended')
rating: float (default 5.0)

-- Vehicle info
vehicle_make: text
vehicle_model: text
vehicle_year: int
vehicle_plate: text
vehicle_color: text

-- Verification
is_verified: boolean
verified_at: timestamp
verified_by: uuid

-- Stripe Connect
stripe_account_id: text
stripe_onboarding_complete: boolean
stripe_charges_enabled: boolean
stripe_payouts_enabled: boolean

created_at: timestamp
updated_at: timestamp
```

### 5. `transactions` - Financial Transactions
```sql
-- Canonical financial record for all money movement
id: uuid (PK)
created_at: timestamp

-- Transaction type
type: text ('ride', 'carpool', 'package', 'cancellation_fee', 'tip', 'payout', 'refund')

-- Relations
delivery_id: uuid (FK -> deliveries)
booking_id: uuid (FK -> share_ride_bookings)
rider_id: uuid (FK -> profiles)
driver_id: uuid (FK -> drivers)

-- Amounts
gross_amount: float (total charged to rider)
net_amount: float (amount to driver after fees)
platform_fee: float
platform_fee_percent: float
tip_amount: float
tax_amount: float

-- TNC (Transportation Network Company) Tax
tnc_tax_amount: float
tnc_tax_jurisdiction: text
tnc_tax_rate: float

-- Stripe
stripe_payment_intent_id: text
stripe_charge_id: text
stripe_transfer_id: text

-- Addresses (canonical)
origin_address: text
destination_address: text

-- Status
status: text ('pending', 'completed', 'failed', 'refunded')
completed_at: timestamp
```

### 6. `driver_earnings` - Driver Earnings Summary
```sql
id: uuid (PK)
driver_id: uuid (FK -> drivers)
delivery_id: uuid (FK -> deliveries)
booking_id: uuid (FK -> share_ride_bookings)

-- Earnings breakdown
gross_earnings: float (before fees)
platform_fee: float
net_earnings: float (after fees)
tip_amount: float
total_payout: float (net + tips)

-- Payout
payout_status: text ('pending', 'processing', 'paid', 'failed')
payout_date: timestamp
stripe_transfer_id: text

created_at: timestamp
```

### 7. `refunds` - Refund Records
```sql
id: uuid (PK)
booking_id: uuid (FK -> share_ride_bookings)
delivery_id: uuid (FK -> deliveries)
rider_id: uuid (FK -> profiles)

amount: float
reason: text
status: text ('pending', 'approved', 'rejected', 'completed')

stripe_refund_id: text
processed_at: timestamp
created_at: timestamp
```

### 8. `carpool_modifications` - Carpool Modification Audit
```sql
id: uuid (PK)
booking_id: uuid (FK -> share_ride_bookings)
rider_id: uuid (FK -> profiles)

modification_type: text ('time_change', 'cancellation', 'seat_change')
old_value: jsonb
new_value: jsonb
fee_amount: float

created_at: timestamp
```

### 9. `saved_places` - User Saved Locations
```sql
id: uuid (PK)
user_id: uuid (FK -> profiles)
name: text ('Home', 'Work', etc.)
address: text
lat: float
lng: float
icon: text
created_at: timestamp
```

### 10. `payment_methods` - User Payment Methods
```sql
id: uuid (PK)
user_id: uuid (FK -> profiles)
stripe_payment_method_id: text
card_brand: text ('visa', 'mastercard', etc.)
card_last4: text
is_default: boolean
created_at: timestamp
```

### 11. `notifications` - User Notifications
```sql
id: uuid (PK)
user_id: uuid (FK -> profiles)
title: text
message: text
type: text ('ride', 'carpool', 'payment', 'system')
read: boolean
created_at: timestamp
```

### 12. `driver_locations` - Real-time Driver Location
```sql
id: uuid (PK)
driver_id: uuid (FK -> drivers)
delivery_id: uuid (FK -> deliveries)
latitude: float
longitude: float
heading: float
speed: float
accuracy: float
updated_at: timestamp
```

### 13. `active_carpool_locations` - Real-time Carpool Tracking
```sql
id: uuid (PK)
booking_id: uuid (FK -> share_ride_bookings)
driver_id: uuid (FK -> drivers)
latitude: float
longitude: float
heading: float
speed: float
updated_at: timestamp
```

### 14. `carpool_events` - Carpool Lifecycle Events
```sql
id: uuid (PK)
carpool_id: uuid (FK -> share_ride_bookings)
event_type: text ('created', 'matched', 'started', 'completed', 'cancelled')
lat: float
lng: float
occurred_at: timestamp
payload: jsonb
```

### 15. `app_settings` - Global App Configuration
```sql
id: uuid (PK)
key: text UNIQUE
value: jsonb
description: text
updated_at: timestamp

-- Example keys:
-- 'carpool_max_wait_minutes'
-- 'carpool_default_radius_km'
-- 'pricing_surge_multiplier'
```

### 16. `state_pricing` - Per-State Pricing Rules
```sql
id: uuid (PK)
state_code: text UNIQUE ('AZ', 'CA', 'TX', etc.)
state_name: text

-- Package pricing
package_base_price: float
package_per_mile: float
package_per_minute: float
package_min_price: float

-- Ride pricing
ride_base_price: float
ride_per_mile: float
ride_per_minute: float
ride_min_price: float

-- Carpool pricing
carpool_base_price: float
carpool_per_mile: float
carpool_per_minute: float
carpool_min_price: float

-- Platform fees
platform_commission_percent: float (default 10%)

-- Active
is_active: boolean
updated_at: timestamp
```

### 17. `tax_jurisdictions` - TNC Tax Configuration
```sql
id: uuid (PK)
jurisdiction_name: text
state_code: text
city: text
county: text

-- Tax rates
tnc_tax_rate: float (e.g., 0.02 = 2%)
applies_to_rides: boolean
applies_to_carpools: boolean
applies_to_packages: boolean

effective_date: date
expires_date: date
is_active: boolean

created_at: timestamp
```

### 18. `driver_documents` - Driver Verification Documents
```sql
id: uuid (PK)
driver_id: uuid (FK -> drivers)
document_type: text ('license', 'insurance', 'registration', 'background_check')
document_url: text (Supabase Storage URL)
status: text ('pending', 'approved', 'rejected', 'expired')
expiration_date: date
verified_at: timestamp
verified_by: uuid (admin)
created_at: timestamp
```

### 19. `support_tickets` - Customer Support
```sql
id: uuid (PK)
user_id: uuid (FK -> profiles)
driver_id: uuid (FK -> drivers)
delivery_id: uuid (FK -> deliveries)
booking_id: uuid (FK -> share_ride_bookings)

subject: text
description: text
category: text ('payment', 'driver', 'technical', 'other')
status: text ('open', 'in_progress', 'resolved', 'closed')
priority: text ('low', 'medium', 'high', 'urgent')

assigned_to: uuid (admin)
resolved_at: timestamp
created_at: timestamp
```

### 20. `qr_tips` - QR Code Tip System
```sql
id: uuid (PK)
driver_id: uuid (FK -> drivers)
rider_id: uuid (FK -> profiles)
delivery_id: uuid (FK -> deliveries)
booking_id: uuid (FK -> share_ride_bookings)

amount: float
stripe_payment_intent_id: text
status: text ('pending', 'completed', 'failed')

created_at: timestamp
```

---

## MATERIALIZED VIEWS

### `platform_finance_daily` - Daily Financial Summary
```sql
-- Refreshed daily via cron job
date: date (PK)

-- Ride metrics
total_rides: int
completed_rides: int
cancelled_rides: int
gross_ride_revenue: float
net_ride_revenue: float (after driver payouts)

-- Carpool metrics
total_carpools: int
completed_carpools: int
gross_carpool_revenue: float

-- Platform earnings
platform_commission: float
cancellation_fees: float
total_platform_earnings: float

-- Driver payouts
total_driver_payouts: float
pending_payouts: float

last_updated: timestamp
```

---

## REALTIME SUBSCRIPTIONS

Tables enabled for real-time updates:
- ✅ `deliveries` - Ride status changes
- ✅ `share_ride_bookings` - Carpool status changes
- ✅ `driver_locations` - Driver GPS updates
- ✅ `active_carpool_locations` - Carpool driver GPS
- ✅ `carpool_events` - Carpool lifecycle events
- ✅ `notifications` - New notifications

---

## ROW LEVEL SECURITY (RLS)

All tables have RLS enabled. Key policies:

### Riders (authenticated users)
- ✅ Can read/update own profile
- ✅ Can create deliveries/bookings
- ✅ Can view own trips only
- ✅ Can view drivers assigned to their trips
- ❌ Cannot view other riders' data

### Drivers
- ✅ Can read/update own driver profile
- ✅ Can view trips assigned to them
- ✅ Can update trip status
- ✅ Can view rider info for assigned trips
- ❌ Cannot view unassigned trips (privacy)

### Admins (enterprise_admin_shell)
- ✅ Full read access to all tables
- ✅ Can update trips, drivers, refunds
- ✅ Can view all financial data
- ✅ Can manage app settings
- ✅ Can verify drivers

---

## STORAGE BUCKETS

### `driver-documents`
- Driver licenses
- Insurance cards
- Vehicle registration
- Background check results

### `profile-avatars`
- User profile photos
- Driver profile photos

### `receipts`
- Trip receipts (PDF)
- Expense receipts

---

## EDGE FUNCTIONS

Deployed Supabase Edge Functions:

1. **stripe-webhook** - Process Stripe webhooks
2. **stripe-connect-onboarding** - Driver Stripe Connect setup
3. **stripe-connect-dashboard** - Driver payout dashboard
4. **stripe-instant-payout** - Instant payout for drivers
5. **stripe-create-payment-intent** - Create payment for rides
6. **stripe-capture-payment** - Capture authorized payment
7. **stripe-refund** - Process refunds
8. **stripe-weekly-payout** - Batch weekly payouts
9. **send-notification** - Send push notifications
10. **notify-driver-earnings** - Notify driver of earnings
11. **find-nearby-carpools** - Match riders to carpools
12. **process-tip** - Handle QR tip payments
13. **process-driver-receipt** - OCR receipt processing

---

## CRON JOBS

Scheduled tasks via `pg_cron`:

```sql
-- Weekly driver payouts (Sundays at 2 AM UTC)
SELECT cron.schedule('weekly-driver-payout', '0 2 * * 0', 'SELECT stripe_weekly_payout()');

-- Refresh materialized view (Daily at 1 AM UTC)
SELECT cron.schedule('refresh-finance-daily', '0 1 * * *', 'REFRESH MATERIALIZED VIEW platform_finance_daily');
```

---

## INDEXES

Critical indexes for performance:

```sql
-- Deliveries
CREATE INDEX idx_deliveries_user_id ON deliveries(user_id);
CREATE INDEX idx_deliveries_driver_id ON deliveries(driver_id);
CREATE INDEX idx_deliveries_status ON deliveries(status);
CREATE INDEX idx_deliveries_created_at ON deliveries(created_at DESC);

-- Carpools
CREATE INDEX idx_carpools_rider_id ON share_ride_bookings(rider_id);
CREATE INDEX idx_carpools_driver_id ON share_ride_bookings(driver_id);
CREATE INDEX idx_carpools_status ON share_ride_bookings(status);
CREATE INDEX idx_carpools_pickup_time ON share_ride_bookings(pickup_time);

-- Transactions
CREATE INDEX idx_transactions_rider_id ON transactions(rider_id);
CREATE INDEX idx_transactions_driver_id ON transactions(driver_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);
```

---

## USEFUL QUERIES

### Get recent bookings
```sql
SELECT * FROM share_ride_bookings
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 20;
```

### Count active rides
```sql
SELECT
  COUNT(*) FILTER (WHERE service_type = 'ride') as rides,
  COUNT(*) FILTER (WHERE service_type = 'carpool') as carpools,
  COUNT(*) FILTER (WHERE service_type = 'package') as packages
FROM deliveries
WHERE status IN ('pending', 'accepted', 'in_progress');
```

### Platform revenue today
```sql
SELECT
  SUM(platform_fee) as total_commission,
  COUNT(*) as completed_trips
FROM transactions
WHERE DATE(created_at) = CURRENT_DATE
  AND status = 'completed';
```

### Driver earnings pending payout
```sql
SELECT
  d.full_name,
  SUM(de.total_payout) as pending_amount
FROM driver_earnings de
JOIN drivers d ON de.driver_id = d.id
WHERE de.payout_status = 'pending'
GROUP BY d.id, d.full_name
ORDER BY pending_amount DESC;
```

---

**For detailed migration history, see**: `supabase/migrations/`
**Total migrations**: 177 files
**Latest migrations**: Focus on TNC tax, financial normalization, RLS fixes
