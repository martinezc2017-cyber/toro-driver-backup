#!/bin/bash

# TORO RIDER - Quick Start Script for Claude Code
# Run this at the start of each chat session to get current project state

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   TORO RIDER - Project Context Loader${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Database connection string
DB_URL="postgresql://postgres:VI6rC4T3BJkOWfqh@db.gkqcrkqaijwhiksyjekv.supabase.co:5432/postgres"

# Project directory
PROJECT_DIR="/c/Users/marti/OneDrive/Escritorio/flutter toro-rider/toro"

echo -e "${YELLOW}📊 DATABASE STATISTICS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if psql is available
if command -v psql &> /dev/null; then
    # Get database stats
    psql "$DB_URL" -t -A << 'EOF'
-- Summary statistics
SELECT '✓ Total Users: ' || COUNT(*)::text FROM profiles;
SELECT '✓ Total Drivers: ' || COUNT(*)::text FROM drivers;
SELECT '✓ Active Deliveries: ' || COUNT(*)::text FROM deliveries WHERE status IN ('pending', 'accepted', 'in_progress');
SELECT '✓ Active Carpools: ' || COUNT(*)::text FROM share_ride_bookings WHERE status IN ('pending', 'matched', 'confirmed', 'active');
SELECT '✓ Deliveries (Last 7d): ' || COUNT(*)::text FROM deliveries WHERE created_at > NOW() - INTERVAL '7 days';
SELECT '✓ Carpools (Last 7d): ' || COUNT(*)::text FROM share_ride_bookings WHERE created_at > NOW() - INTERVAL '7 days';
SELECT '✓ Revenue (Last 7d): $' || COALESCE(SUM(total_price), 0)::numeric(10,2)::text FROM transactions WHERE created_at > NOW() - INTERVAL '7 days' AND status = 'completed';
EOF
else
    echo "⚠️  psql not installed. Install PostgreSQL client to query database."
    echo "   Download from: https://www.postgresql.org/download/windows/"
fi

echo ""
echo -e "${YELLOW}📁 PROJECT INFO${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Project: Toro Rider"
echo "✓ Location: $PROJECT_DIR"
echo "✓ Database: Supabase (gkqcrkqaijwhiksyjekv)"
echo "✓ Platform: Flutter (Mobile) + Next.js (Admin)"

echo ""
echo -e "${YELLOW}🔧 RECENT ACTIVITY${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Recent migrations
if [ -d "$PROJECT_DIR/supabase/migrations" ]; then
    echo "✓ Recent Migrations:"
    ls -1t "$PROJECT_DIR/supabase/migrations" | grep -E "^202" | head -5 | sed 's/^/  - /'
fi

echo ""
echo -e "${YELLOW}📋 AVAILABLE COMMANDS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Database:"
echo "  psql \"\$DB_URL\"                    # Connect to database"
echo "  psql \"\$DB_URL\" -c \"QUERY\"         # Execute query"
echo ""
echo "Supabase CLI:"
echo "  supabase db execute --file query.sql"
echo "  supabase db dump --data-only"
echo ""
echo "Flutter:"
echo "  flutter run                        # Run app"
echo "  flutter analyze                    # Check for errors"
echo ""

echo -e "${YELLOW}🔗 QUICK LINKS${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Dashboard:  https://app.supabase.com/project/gkqcrkqaijwhiksyjekv"
echo "SQL Editor: https://app.supabase.com/project/gkqcrkqaijwhiksyjekv/sql/new"
echo "Stripe:     https://dashboard.stripe.com/test/payments"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Context loaded! Ready to assist.${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Export DB_URL for later use
export DB_URL
