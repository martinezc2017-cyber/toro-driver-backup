# Read and modify kpi_repo.dart
import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix getDailyFinance select to include metadata
old1 = "'payment_method, country_code, type, status, created_at',\n    );\n    if (countryCode != null && countryCode.isNotEmpty) q = q.eq('country_code', countryCode);\n    if (startDate != null) q = q.gte('created_at', startDate.toUtc().toIso8601String());\n    if (endDate != null) q = q.lte('created_at', endDate.toUtc().toIso8601String());\n\n    const capturedStatuses = {'success', 'completed', 'captured', 'paid', 'approved', 'processed', 'authorized'};\n    final raw = await q.limit(20000);\n    final Map<String, Map<String, dynamic>> byDay = {};\n    for (final r in (raw as List)) {\n      final m = r as Map<String, dynamic>;\n      final st = (m['status']?.toString() ?? '').toLowerCase();"

new1 = "'payment_method, country_code, type, status, created_at, metadata',\n    );\n    if (countryCode != null && countryCode.isNotEmpty) q = q.eq('country_code', countryCode);\n    if (startDate != null) q = q.gte('created_at', startDate.toUtc().toIso8601String());\n    if (endDate != null) q = q.lte('created_at', endDate.toUtc().toIso8601String());\n\n    const capturedStatuses = {'success', 'completed', 'captured', 'paid', 'approved', 'processed', 'authorized'};\n    final raw = await q.limit(20000);\n    final Map<String, Map<String, dynamic>> byDay = {};\n    for (final r in (raw as List)) {\n      final m = r as Map<String, dynamic>;\n      // FIX: Skip test transactions (metadata has 'test', 'e2e', 'webhook-validation')\n      if (_isTestTransaction(m)) continue;\n      final st = (m['status']?.toString() ?? '').toLowerCase();"

if old1 in content:
    content = content.replace(old1, new1)
    print("1. Fixed getDailyFinance select + test filter")
else:
    print("1. WARNING: Could not find old1 pattern in getDailyFinance")
    # Debug: print some context
    idx = content.find('payment_method, country_code, type, status, created_at')
    if idx >= 0:
        print(f"   Found at position {idx}")
        print(f"   Context: ...{content[idx:idx+400]}...")

# 2. Fix getKpiTotals select to include metadata
old2 = "'payment_method, country_code, type, status, created_at',\n    );\n    if (countryCode != null && countryCode.isNotEmpty) {\n      q = q.eq('country_code', countryCode);\n    }\n    if (startDate != null) q = q.gte('created_at', startDate.toUtc().toIso8601String());\n    if (endDate != null) q = q.lte('created_at', endDate.toUtc().toIso8601String());\n\n    final raw = await q.limit(20000);\n\n    double grossTotal = 0;       // TODO cobrado (servicios + wallet)"

new2 = "'payment_method, country_code, type, status, created_at, metadata',\n    );\n    if (countryCode != null && countryCode.isNotEmpty) {\n      q = q.eq('country_code', countryCode);\n    }\n    if (startDate != null) q = q.gte('created_at', startDate.toUtc().toIso8601String());\n    if (endDate != null) q = q.lte('created_at', endDate.toUtc().toIso8601String());\n\n    final raw = await q.limit(20000);\n\n    double grossTotal = 0;       // TODO cobrado (servicios + wallet)"

if old2 in content:
    content = content.replace(old2, new2)
    print("2. Fixed getKpiTotals select + metadata")
else:
    print("2. WARNING: Could not find old2 pattern in getKpiTotals")
    idx = content.find('double grossTotal')
    if idx >= 0:
        print(f"   Found 'double grossTotal' at position {idx}")
        print(f"   Context: ...{content[idx-300:idx+100]}...")

# 3. Fix the loop in getKpiTotals to skip test transactions
old3 = "      final m = r as Map<String, dynamic>;\n      final st = (m['status']?.toString() ?? '').toLowerCase();\n      if (!capturedStatuses.contains(st) && st != 'refunded') continue;\n      final type = (m['type']?.toString() ?? '').toLowerCase();\n      final amt = (m['amount'] as num?)?.toDouble() ?? 0;"

new3 = "      final m = r as Map<String, dynamic>;\n      // FIX: Skip test transactions (metadata has 'test', 'e2e', 'webhook-validation')\n      if (_isTestTransaction(m)) continue;\n      final st = (m['status']?.toString() ?? '').toLowerCase();\n      if (!capturedStatuses.contains(st) && st != 'refunded') continue;\n      final type = (m['type']?.toString() ?? '').toLowerCase();\n      final amt = (m['amount'] as num?)?.toDouble() ?? 0;"

if old3 in content:
    content = content.replace(old3, new3)
    print("3. Fixed getKpiTotals loop with test filter")
else:
    print("3. WARNING: Could not find old3 pattern")
    # Find alternative pattern
    count_old3 = content.count("if (!capturedStatuses.contains(st) && st != 'refunded') continue;")
    print(f"   Found {count_old3} occurrences of the status check")
    if count_old3 >= 2:
        # Replace second occurrence (which is in getKpiTotals)
        parts = content.split("if (!capturedStatuses.contains(st) && st != 'refunded') continue;")
        if len(parts) >= 3:
            # Second occurrence is in getKpiTotals method
            fix_part = parts[1]  # Between first and second occurrence
            if 'final m = r as Map<String, dynamic>' in fix_part:
                content = parts[0] + "if (!capturedStatuses.contains(st) && st != 'refunded') continue;" + parts[1]
                # Hmm this is complex. Let me just do a simpler approach.
                print("   Complex replacement needed")

# 4. Add _isTestTransaction method before BREAKDOWN section
old4 = "  // ============================================================================\n  // BREAKDOWN (for pie charts)\n  // ============================================================================"

new4 = """  // ============================================================================
  // TEST DATA DETECTION
  // ============================================================================

  /// Check if a transaction is test/e2e data based on metadata
  /// Test transactions have 'test', 'e2e', or 'webhook-validation' in metadata
  bool _isTestTransaction(Map<String, dynamic> tx) {
    final meta = tx['metadata'];
    if (meta == null) return false;

    // metadata is a Map from JSONB column
    if (meta is Map) {
      if (meta.containsKey('test') ||
          meta.containsKey('e2e') ||
          meta.containsKey('e2e_audit')) {
        return true;
      }
      // Check if any value contains webhook-validation
      final metaStr = meta.values.join(' ').toLowerCase();
      if (metaStr.contains('webhook-validation') ||
          metaStr.contains('e2e') ||
          metaStr.contains('test')) {
        return true;
      }
    }

    // Also check as string (for edge cases)
    final metaString = meta.toString().toLowerCase();
    if (metaString.contains('webhook-validation') ||
        metaString.contains('\\"test\\"') ||
        metaString.contains('\\"e2e\\"')) {
      return true;
    }

    return false;
  }

  // ============================================================================
  // BREAKDOWN (for pie charts)
  // ============================================================================"""

if old4 in content:
    content = content.replace(old4, new4)
    print("4. Added _isTestTransaction method")
else:
    print("4. WARNING: Could not find BREAKDOWN section marker")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('\nDONE: kpi_repo.dart updated successfully')
