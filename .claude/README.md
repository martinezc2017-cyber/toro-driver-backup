# TORO DRIVER - Claude Code Configuration

> **Project**: Toro Driver - Driver app for Toro ride sharing platform
> **Database**: Shared Supabase PostgreSQL with Toro Rider
> **Platform**: Flutter (iOS & Android)

---

## 📁 PROJECT INFO

### What is Toro Driver?
Companion app for drivers to:
- Accept ride/delivery requests
- Track earnings
- Navigate to pickup/dropoff
- Manage documents & verification
- Process instant payouts

### Shared Database
This app shares the same Supabase database as Toro Rider:
- **Project Ref**: `gkqcrkqaijwhiksyjekv`
- **Connection**: See `SUPABASE_CONNECTION.md`
- **Schema**: See `DATABASE_SCHEMA.md`

---

## 🚀 QUICK START

Same as Toro Rider - all context files are shared:
- `SUPABASE_CONNECTION.md` - Database credentials
- `DATABASE_SCHEMA.md` - Schema reference
- `MEMORY_SYSTEM.md` - How to use DB as memory
- `QUICK_START.sh` - Initialization script

---

## 📊 DRIVER-SPECIFIC TABLES

### Main Tables for Drivers
- `drivers` - Driver profiles & verification
- `deliveries` - Rides/deliveries assigned to driver
- `driver_earnings` - Earnings & payout tracking
- `driver_documents` - License, insurance, etc.
- `driver_locations` - Real-time GPS tracking
- `active_carpool_locations` - Carpool GPS tracking

### Queries for Driver Context
```sql
-- Get driver info
SELECT * FROM drivers WHERE id = 'driver-uuid';

-- Get assigned deliveries
SELECT * FROM deliveries
WHERE driver_id = 'driver-uuid'
  AND status IN ('accepted', 'in_progress')
ORDER BY created_at DESC;

-- Get earnings pending payout
SELECT SUM(total_payout) as pending
FROM driver_earnings
WHERE driver_id = 'driver-uuid'
  AND payout_status = 'pending';

-- Get recent trips
SELECT
  id,
  service_type,
  pickup_address,
  destination_address,
  total_price,
  net_earnings,
  created_at
FROM driver_earnings de
JOIN deliveries d ON de.delivery_id = d.id
WHERE de.driver_id = 'driver-uuid'
ORDER BY created_at DESC
LIMIT 10;
```

---

## 🔧 DRIVER APP FEATURES

- ✅ Accept/reject delivery requests
- ✅ Real-time navigation
- ✅ GPS location sharing
- ✅ Earnings dashboard
- ✅ Instant payout (Stripe Connect)
- ✅ Document upload & verification
- ✅ Trip history
- ✅ Rating system
- ✅ Support tickets

---

## 💰 DRIVER FINANCIAL FLOW

```
1. Driver completes ride
2. Transaction created with split:
   - Gross: $20.00
   - Platform fee (10%): $2.00
   - Net to driver: $18.00
3. Driver earnings record created
4. Weekly payout via Stripe Connect
   OR instant payout (with small fee)
```

---

## 📝 DEVELOPMENT NOTES

### Key Services
- `lib/core/services/driver_service.dart` - Driver-specific operations
- `lib/core/services/location_service.dart` - GPS tracking
- `lib/core/services/navigation_service.dart` - Turn-by-turn nav

### Stripe Connect
Drivers use Stripe Connect for payouts:
- Onboarding: `stripe-connect-onboarding` Edge Function
- Payouts: `stripe-connect-dashboard` Edge Function
- Instant payout: `stripe-instant-payout` Edge Function

---

**Shared Resources**: This app shares database & backend with Toro Rider
**Last Updated**: 2026-01-24
