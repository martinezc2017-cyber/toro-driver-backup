# CLAUDE CODE - DATABASE MEMORY SYSTEM

> **Purpose**: Use Supabase database as persistent memory between chat sessions
> **Setup Date**: 2026-01-24

---

## HOW THIS WORKS

Instead of relying on static documentation, Claude can query the live Supabase database to understand:
- Current project state
- Recent user activity
- Active bookings/rides
- Financial data
- Configuration settings
- What features are actually being used

---

## QUICK START (Every New Chat Session)

### Step 1: Read Connection Info
```bash
# Read this file to get database credentials
cat .claude/SUPABASE_CONNECTION.md
```

### Step 2: Test Connection
```bash
# Quick health check
psql "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres" \
  -c "SELECT COUNT(*) FROM profiles"
```

### Step 3: Get Current State
```sql
-- Run this query to understand what's happening now
SELECT
  'Profiles' as table_name, COUNT(*) as count FROM profiles
UNION ALL
SELECT 'Deliveries', COUNT(*) FROM deliveries
UNION ALL
SELECT 'Carpools', COUNT(*) FROM share_ride_bookings
UNION ALL
SELECT 'Drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'Active Deliveries', COUNT(*) FROM deliveries WHERE status IN ('pending', 'accepted', 'in_progress')
UNION ALL
SELECT 'Active Carpools', COUNT(*) FROM share_ride_bookings WHERE status IN ('pending', 'matched', 'confirmed', 'active');
```

---

## COMMON QUERIES FOR CONTEXT

### What's the user working on?
```sql
-- Recent deliveries (last 7 days)
SELECT
  id,
  service_type,
  status,
  pickup_address,
  destination_address,
  created_at,
  total_price
FROM deliveries
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 10;
```

### Are there any active trips?
```sql
-- Active deliveries/rides
SELECT
  id,
  service_type,
  status,
  pickup_address,
  destination_address,
  driver_id IS NOT NULL as has_driver,
  created_at
FROM deliveries
WHERE status IN ('pending', 'accepted', 'in_progress')
ORDER BY created_at DESC;
```

### What's the carpool situation?
```sql
-- Recent carpools
SELECT
  id,
  origin,
  destination,
  status,
  seats_requested,
  pickup_time,
  total_price,
  driver_id IS NOT NULL as has_driver
FROM share_ride_bookings
WHERE created_at > NOW() - INTERVAL '7 days'
ORDER BY created_at DESC
LIMIT 10;
```

### How's the financial health?
```sql
-- Revenue summary (last 30 days)
SELECT
  DATE(created_at) as date,
  COUNT(*) as trips,
  SUM(total_price) as revenue,
  SUM(platform_fee) as platform_earnings
FROM transactions
WHERE created_at > NOW() - INTERVAL '30 days'
  AND status = 'completed'
GROUP BY DATE(created_at)
ORDER BY date DESC
LIMIT 30;
```

### Any issues to address?
```sql
-- Open support tickets
SELECT
  id,
  subject,
  category,
  status,
  priority,
  created_at
FROM support_tickets
WHERE status IN ('open', 'in_progress')
ORDER BY
  CASE priority
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'medium' THEN 3
    WHEN 'low' THEN 4
  END,
  created_at DESC;
```

### What's the pricing config?
```sql
-- Current pricing by state
SELECT
  state_code,
  state_name,
  carpool_base_price,
  carpool_per_mile,
  ride_base_price,
  ride_per_mile,
  platform_commission_percent
FROM state_pricing
WHERE is_active = true
ORDER BY state_code;
```

---

## USING psql

### Install PostgreSQL Client
If psql is not installed:
```bash
# Download from: https://www.postgresql.org/download/windows/
# Or install via package manager
```

### Connect
```bash
export DB_URL="postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres"
psql "$DB_URL"
```

### Quick Commands
```sql
\dt                           -- List tables
\d+ share_ride_bookings       -- Describe table
\x                            -- Toggle expanded display (better for wide rows)

SELECT * FROM profiles LIMIT 5;
```

### Save Query to File
```bash
psql "$DB_URL" -c "SELECT * FROM deliveries ORDER BY created_at DESC LIMIT 10" > recent_deliveries.txt
```

---

## USING SUPABASE CLI

### Execute SQL File
```bash
cd "/c/Users/marti/OneDrive/Escritorio/flutter toro-rider/toro"

# Create query file
cat > query.sql << 'EOF'
SELECT COUNT(*) FROM deliveries;
SELECT COUNT(*) FROM share_ride_bookings;
EOF

# Execute it
supabase db execute --db-url "$DB_URL" --file query.sql
```

### Execute Inline Query
```bash
supabase db execute \
  --db-url "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres" \
  --command "SELECT * FROM profiles LIMIT 5"
```

---

## INTERPRETING THE DATA

### Service Types
- `package` = Package delivery
- `ride` = Standard ride (passenger only)
- `carpool` = Shared ride with other passengers

### Status Flow (Deliveries)
```
pending → accepted → in_progress → delivered
                              ↓
                         cancelled
```

### Status Flow (Carpools)
```
pending → matched → confirmed → active → completed
                                   ↓
                              cancelled
```

### Payment Status
- `pending` = Payment authorized but not captured
- `completed` = Payment captured successfully
- `failed` = Payment failed
- `refunded` = Payment refunded to user

### Payout Status
- `pending` = Earnings not yet paid to driver
- `processing` = Payout in progress
- `paid` = Driver received payout
- `failed` = Payout failed (retry needed)

---

## MEMORY PATTERNS

### Pattern 1: State Restoration
When user asks "Where did we leave off?"
```sql
-- Check recent migrations applied
SELECT filename, created_at
FROM supabase_migrations.schema_migrations
ORDER BY created_at DESC
LIMIT 10;

-- Check recent trips created
SELECT id, service_type, status, created_at
FROM deliveries
ORDER BY created_at DESC
LIMIT 5;
```

### Pattern 2: Feature Usage
When user asks "Is feature X being used?"
```sql
-- Example: Check if carpool round trips are being used
SELECT COUNT(*) as round_trip_bookings
FROM share_ride_bookings
WHERE is_return_trip = true;

-- Example: Check if QR tips are being used
SELECT COUNT(*) as qr_tips_count
FROM qr_tips
WHERE created_at > NOW() - INTERVAL '30 days';
```

### Pattern 3: Error Diagnosis
When user reports a bug:
```sql
-- Check for failed transactions
SELECT id, type, status, created_at
FROM transactions
WHERE status = 'failed'
  AND created_at > NOW() - INTERVAL '7 days';

-- Check for cancelled rides with reasons
SELECT
  id,
  status,
  cancelled_at,
  notes->>'reason' as cancellation_reason
FROM deliveries
WHERE status = 'cancelled'
  AND cancelled_at > NOW() - INTERVAL '7 days';
```

### Pattern 4: Configuration Check
Before making changes, check current settings:
```sql
-- Check current app settings
SELECT key, value, description
FROM app_settings;

-- Check pricing rules
SELECT * FROM state_pricing WHERE state_code = 'AZ';
```

---

## BEST PRACTICES

### ✅ DO
- Query database at start of each session to get current state
- Use database to verify user's claims ("Is feature X broken?")
- Check migration history to see what changed recently
- Look at actual data patterns before suggesting changes
- Use `LIMIT` clauses to avoid overwhelming output

### ❌ DON'T
- Assume static documentation is current
- Make changes without querying first
- Trust only the code - verify with data
- Run unlimited queries (use LIMIT)
- Store sensitive data in plain text in these docs

---

## TROUBLESHOOTING

### "Connection refused"
- Check if Supabase project is paused (Dashboard)
- Verify password hasn't been reset
- Check network/firewall

### "Permission denied"
- Using wrong password
- Database user doesn't have permissions
- RLS policy blocking query

### "Timeout"
- Query too complex/slow
- Add indexes
- Use LIMIT clause
- Check slow query log in Supabase Dashboard

### "psql: command not found"
- PostgreSQL client not installed
- Add to PATH: `C:\Program Files\PostgreSQL\16\bin`

---

## SECURITY REMINDERS

- 🔒 **Database password** is sensitive - never commit to git
- 🔑 **Service role key** has full access - use with caution
- 📝 **Anon key** is safe for client apps
- ⚠️ **RLS policies** protect data - don't bypass them
- 🚫 **Never expose credentials** in client code or logs

---

## ADVANCED: Python Script for Queries

Create `scripts/query_db.py`:
```python
import psycopg2
import os

DB_URL = "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres"

conn = psycopg2.connect(DB_URL)
cur = conn.cursor()

# Example: Get current state
cur.execute("""
    SELECT
        (SELECT COUNT(*) FROM deliveries) as deliveries,
        (SELECT COUNT(*) FROM share_ride_bookings) as carpools,
        (SELECT COUNT(*) FROM profiles) as users
""")

result = cur.fetchone()
print(f"Deliveries: {result[0]}")
print(f"Carpools: {result[1]}")
print(f"Users: {result[2]}")

cur.close()
conn.close()
```

Run with:
```bash
python scripts/query_db.py
```

---

## SCHEMA REFERENCE

For full table definitions, see:
- `.claude/DATABASE_SCHEMA.md` - Complete schema documentation
- `supabase/migrations/` - Raw SQL migration files

---

**Remember**: The database is the source of truth. Documentation can be outdated, but data never lies.

**Last Updated**: 2026-01-24
**Next Review**: When major features are added/changed
