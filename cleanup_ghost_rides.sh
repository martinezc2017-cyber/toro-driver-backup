#!/bin/bash

# Script para limpiar viajes fantasma
# Uso: ./cleanup_ghost_rides.sh <driver_id>

SUPABASE_URL="https://gkqcrkqaijwhiksyjekv.supabase.co"
SUPABASE_ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdrcWNya3FhaWp3aGlrc3lqZWt2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE2Mzc4MzI0NzAsImV4cCI6MTk1MzQwODQ3MH0.K9xB8L2tWxZ_M6l7q8Z8Z_Z_Z_Z_Z_Z_Z_Z_Z_Z_Z_Z8"

DRIVER_ID="${1}"

if [ -z "$DRIVER_ID" ]; then
  echo "❌ Error: driver_id is required"
  echo "Usage: ./cleanup_ghost_rides.sh <driver_id>"
  exit 1
fi

echo "🔧 Cleaning ghost rides for driver: $DRIVER_ID"

# Call the force-release-rides function
curl -X POST "${SUPABASE_URL}/functions/v1/force-release-rides" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
  -d "{\"driver_id\": \"${DRIVER_ID}\"}"

echo ""
echo "✅ Cleanup complete!"
