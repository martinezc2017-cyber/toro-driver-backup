# SUPABASE DATABASE CONNECTION

## Project Info
- **Project Name**: Toro Rider
- **Project Ref**: `gkqcrkqaijwhiksyjekv`
- **Region**: US East (likely)
- **Database**: PostgreSQL 15+

## Connection Credentials

### API Endpoint
```
https://gkqcrkqaijwhiksyjekv.supabase.co
```

### Database Connection String
```
postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres
```

### API Keys

**Anon/Public Key** (safe for client):
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdrcWNya3FhaWp3aGlrc3lqZWt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcyMjA0NTYsImV4cCI6MjA4Mjc5NjQ1Nn0.QmYXkhPndrUgInC8pdr7wdROVeh69BtbeICZbFV7Rno
```

**Service Role Key** (admin access - GET FROM DASHBOARD):
```
Need to retrieve from: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/settings/api
```

**Database Password**:
```
VI6rC4T3BJkOWfqh
```

## Quick Access URLs

- **Dashboard**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv
- **Database**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/editor
- **SQL Editor**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/sql/new
- **Table Editor**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/editor
- **API Docs**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/api
- **Settings**: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/settings/api

## Using Supabase CLI

### Install (Already done ✓)
```bash
# Supabase CLI already installed at: C:\Users\marti\bin\supabase.exe
```

### Link to Project
```bash
cd "C:\Users\marti\OneDrive\Escritorio\flutter toro-rider\toro"
supabase link --project-ref gkqcrkqaijwhiksyjekv
# Enter DB password when prompted: VI6rC4T3BJkOWfqh
```

### Execute SQL Queries
```bash
# Method 1: Using supabase db execute
supabase db execute --db-url "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres" --file query.sql

# Method 2: Using psql directly (requires PostgreSQL client)
psql "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres" -c "SELECT * FROM profiles LIMIT 5"
```

### Common Queries
```bash
# Get table list
supabase db execute --command "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"

# Get schema of a table
supabase db execute --command "\d share_ride_bookings"

# Count rows
supabase db execute --command "SELECT COUNT(*) FROM share_ride_bookings"
```

## Using psql (PostgreSQL Client)

### Install psql
Download from: https://www.postgresql.org/download/windows/

### Connect
```bash
psql "postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres"
```

### Quick Commands
```sql
\dt                    -- List all tables
\d+ table_name         -- Describe table
\q                     -- Quit

SELECT * FROM share_ride_bookings LIMIT 5;
SELECT COUNT(*) FROM deliveries;
```

## Environment Variables

Create `.env` file in project root:
```env
SUPABASE_URL=https://gkqcrkqaijwhiksyjekv.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdrcWNya3FhaWp3aGlrc3lqZWt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjcyMjA0NTYsImV4cCI6MjA4Mjc5NjQ1Nn0.QmYXkhPndrUgInC8pdr7wdROVeh69BtbeICZbFV7Rno
SUPABASE_SERVICE_ROLE_KEY=[GET_FROM_DASHBOARD]
DATABASE_URL=postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres
```

## Claude Code Memory

For future Claude sessions to access the database:

1. **Read this file** to get credentials
2. **Execute queries** using psql or Supabase CLI
3. **Check schema** by reading migration files in `supabase/migrations/`

### Example: Get current state
```bash
psql "$DATABASE_URL" -c "
SELECT
  (SELECT COUNT(*) FROM deliveries) as deliveries_count,
  (SELECT COUNT(*) FROM share_ride_bookings) as carpools_count,
  (SELECT COUNT(*) FROM profiles) as users_count
"
```

## Security Notes

- ⚠️ **Never commit .env files** - already in .gitignore
- ✅ **Anon key is safe** for client apps
- 🔒 **Service role key** should never be exposed in client code
- 🔐 **Database password** stored securely in this file

## Troubleshooting

### Cannot connect
1. Check if project is paused in Dashboard
2. Verify password hasn't been reset
3. Check firewall/network restrictions

### Supabase CLI errors
1. Ensure you're in project directory
2. Run `supabase link` first
3. Check Docker is running (for local dev)

### Query timeout
1. Use indexed queries
2. Add LIMIT clauses
3. Check slow query log in Dashboard

---

**Last Updated**: 2026-01-24
**Created By**: Claude Code Setup
