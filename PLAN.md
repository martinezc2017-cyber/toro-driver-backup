# MASTER CHECKLIST — QR System Implementation Status

## COMPLETED:
- [x] Rider Bonus Meter UI rewrite (search_screen.dart) — slider, allocation choice, QR info, carpool info
- [x] No-default allocation — rider MUST explicitly choose (allocationChosen flag)
- [x] Anti-fraud SQL migration (20260212_qr_antifraud.sql) — RLS, RPC award_qr_point, trigger, audit log
- [x] Weekly donation SQL migration (20260212_qr_weekly_donations.sql) — table, view, 3 RPCs
- [x] Tier system SQL migration (20260212_qr_tier_system.sql) — pricing_config columns, qr_scans, summary view
- [x] Removed old spendPointsAsTip system (infinite recycling bug fixed)
- [x] Removed old selectedTipPercent/calculateTipForRide from qr_points_service.dart
- [x] Removed _spendQRPointsForTip from ride_service.dart
- [x] Added recordRideDonation to qr_points_service.dart
- [x] Added _recordQRDonation to ride_service.dart (both completion paths)
- [x] Added WeeklyTopDriver class and weeklyTopDriverProvider
- [x] Added _loadWeeklyTopDriver to qr_points_service.dart
- [x] Added weekly #1 driver display in Bonus Meter (_buildTop1DriverInfo)
- [x] Per-ride QR bonus toggle in destination_screen.dart (_useQRBonus, _buildQRBonusToggle)
- [x] Crossed-out price display when QR bonus active
- [x] i18n strings for donation system (ES + EN, gen-l10n run)
- [x] Driver QR points screen with tier info (qr_points_screen.dart)
- [x] Driver QR service with tier config loading (driver_qr_points_service.dart)
- [x] All 3 split calculators updated with tier support
- [x] Driver i18n QR tier strings (en.json, es.json, es-MX.json)
- [x] Driver donations received tab (3rd tab in qr_points_screen.dart)
- [x] QRDonationReceived model + data loading + realtime subscription in driver_qr_points_service.dart
- [x] Driver donations i18n strings (qr_tab_donations, qr_donations_title, etc.)
- [x] Admin donations dashboard tab (4th tab "Donaciones" in admin_installs_map_screen.dart)
- [x] Admin donations leaderboard with podium, table, aggregation by driver
- [x] DB trigger: auto-award driver QR point on referral's first ride (20260212_qr_auto_award.sql)
- [x] Consolidated profiles columns migration (20260212_qr_profiles_columns.sql) — qr_rider_share, referred_by, driver_qr_points table, qr_points table, qr_tip_history table

## NOT DONE YET:
- [ ] Apply all SQL migrations to Supabase (need `supabase db push` or manual apply)
- [ ] Admin QR leaderboard update with tier info columns
- [ ] End-to-end testing of full QR flow

## SQL MIGRATIONS TO APPLY (in order):
1. 20260212_qr_profiles_columns.sql — profiles columns + driver_qr_points + qr_points + qr_tip_history tables
2. 20260212_qr_tier_system.sql — pricing_config tier columns + qr_scans + qr_tier_changes
3. 20260212_qr_antifraud.sql — RLS, award_qr_point RPC, audit log, protect trigger
4. 20260212_qr_weekly_donations.sql — qr_ride_donations table, RPCs
5. 20260212_qr_auto_award.sql — ride completion trigger for driver QR auto-award

## KEY ARCHITECTURE:
- **Rider QR allocation**: riderShare (0-10) + driverShare (0-10) = 10
- **Rider discount**: level * (riderShare / 10)%
- **Donation to #1 driver**: level * (driverShare / 10)%
- **Points are passive**: last all week, NOT spent per ride
- **Per-ride toggle**: _useQRBonus in destination_screen — rider explicitly enables
- **Anti-fraud**: Server-side RPC + trigger + audit log + session variable pattern
- **DB trigger**: on_ride_completed_award_qr — auto-increments referring driver's level

---

# Tourism System Plan (from previous sessions)

## Pasos anteriores del turismo - ver commits anteriores para detalles
