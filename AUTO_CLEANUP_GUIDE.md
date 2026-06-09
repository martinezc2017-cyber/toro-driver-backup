# 🤖 Auto-Cleanup Ghost Rides - Documentation

## Overview
Sistema automático para limpiar viajes fantasma (ghost rides) que quedan en estado `accepted` o `in_progress` sin actualización por más de 24 horas.

---

## 🏗️ Architecture

### Tres capas de protección:

#### 1️⃣ **Database Cron Job (Supabase)**
- **Función**: `auto_cleanup_ghost_rides()`
- **Frecuencia**: Cada 6 horas (0:00, 6:00, 12:00, 18:00 UTC)
- **Archivo**: `supabase/migrations/20260505_auto_cleanup_ghost_rides.sql`
- **Requisito**: Extensión `pg_cron` habilitada en Supabase

#### 2️⃣ **Edge Function (Supabase)**
- **Función**: `auto-cleanup-rides`
- **Archivo**: `supabase/functions/auto-cleanup-rides/index.ts`
- **Método**: POST
- **URL**: `https://gkqcrkqaijwhiksyjekv.supabase.co/functions/v1/auto-cleanup-rides`

#### 3️⃣ **Claude Code Cron (Redundancia)**
- **Job ID**: `0eff5ef8`
- **Frecuencia**: Cada 6 horas
- **Acción**: Ejecuta edge function via HTTP

---

## 🧹 What Gets Cleaned

### Criterios de limpieza:
```sql
WHERE status IN ('accepted', 'in_progress')
  AND driver_id IS NOT NULL
  AND (NOW() - updated_at) > INTERVAL '24 hours'
```

### Tablas afectadas:
- **deliveries** (rides + packages)
- **share_ride_bookings** (carpools)

### Acción:
```sql
SET status = 'pending',
    driver_id = NULL,
    accepted_at = NULL,
    started_at = NULL
```

---

## 📋 Deployment Steps

### 1. Deploy Database Migration
```bash
# Via Supabase Dashboard:
# SQL Editor → Run migration file

# Via CLI:
supabase db push
```

### 2. Deploy Edge Function
```bash
supabase functions deploy auto-cleanup-rides
```

### 3. Enable pg_cron (if not already enabled)
```sql
-- Supabase Dashboard → SQL Editor
CREATE EXTENSION IF NOT EXISTS pg_cron;
```

### 4. Verify Cron Job
```sql
SELECT * FROM cron.job;
```

---

## 🔍 Monitoring

### Check cleanup logs:
```sql
SELECT * FROM audit_log 
WHERE action = 'auto_cleanup_ghost_rides'
ORDER BY created_at DESC
LIMIT 10;
```

### Check function execution:
- Supabase Dashboard → Edge Functions → auto-cleanup-rides → Logs

### Check database cron:
```sql
SELECT * FROM cron.job_run_details
ORDER BY start_time DESC
LIMIT 10;
```

---

## 🔧 Manual Execution

### Via Edge Function:
```bash
curl -X POST https://gkqcrkqaijwhiksyjekv.supabase.co/functions/v1/auto-cleanup-rides \
  -H "Content-Type: application/json" \
  -H "apikey: YOUR_ANON_KEY"
```

### Via SQL:
```sql
SELECT auto_cleanup_ghost_rides();
```

---

## ⚙️ Configuration

### Change cleanup interval:
Edit `supabase/migrations/20260505_auto_cleanup_ghost_rides.sql`:
```sql
-- Change this:
'0 */6 * * *'  -- Every 6 hours

-- To:
'0 */2 * * *'  -- Every 2 hours
'0 * * * *'    -- Every hour
'*/30 * * * *' -- Every 30 minutes
```

### Change grace period (24 hours → X):
Edit `supabase/functions/auto-cleanup-rides/index.ts`:
```typescript
// Change this:
lte('updated_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())

// To:
lte('updated_at', new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString())  // 6 hours
lte('updated_at', new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString()) // 48 hours
```

---

## 🚨 Alerts & Notifications

### If cleanup fails:
1. Check function logs in Supabase Dashboard
2. Verify `pg_cron` extension is enabled
3. Check database permissions
4. Review error messages in `audit_log`

### Fallback: Manual cleanup
```sql
-- Force cleanup immediately
SELECT auto_cleanup_ghost_rides();

-- Or via edge function
curl -X POST https://.../functions/v1/auto-cleanup-rides
```

---

## 📊 Cleanup History

### View all cleanups:
```sql
SELECT * FROM audit_log 
WHERE action LIKE '%cleanup%'
ORDER BY created_at DESC;
```

### Count cleanups per day:
```sql
SELECT DATE(created_at), COUNT(*)
FROM audit_log 
WHERE action = 'auto_cleanup_ghost_rides'
GROUP BY DATE(created_at);
```

---

## 🔐 Security Notes

- ✅ Uses SERVICE_ROLE_KEY for migrations
- ✅ Edge function requires valid API key
- ✅ Database triggers run as system user
- ✅ RLS policies still applied
- ✅ All actions logged in audit_log

---

## 📞 Troubleshooting

| Issue | Solution |
|-------|----------|
| Cleanup not running | Check if `pg_cron` is enabled: `SELECT * FROM pg_extension;` |
| Too many false positives | Increase grace period from 24h to 48h |
| Not cleaning fast enough | Reduce interval from 6h to 2h |
| Database quota exceeded | Reduce frequency or grace period |

---

**Last Updated**: 2026-05-05
**Status**: ✅ Active & Monitoring
