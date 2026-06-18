import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Current state: rounding is AFTER debugPrint
# Move rounding BEFORE debugPrint
old = '''    if (kDebugMode) {
      debugPrint('\u2550\u2550\u2550 KpiRepo.getKpiTotals \u2192 canonical \u2550\u2550\u2550');
      for (final e in result.entries) {
        debugPrint('  ${e.key.padRight(22)}= ${e.value}');
      }
      debugPrint('  stripe_snap_available: ${stripeSnap != null}');
    }
    // Round all monetary values to 2 decimal places
    for (final k in result.keys) {
      if (result[k] is double) {
        result[k] = ((result[k] as double) * 100).round() / 100;
      }
    }'''

new = '''    // Round all monetary values to 2 decimal places FIRST
    for (final k in result.keys) {
      if (result[k] is double) {
        result[k] = ((result[k] as double) * 100).round() / 100;
      }
    }
    if (kDebugMode) {
      debugPrint('\u2550\u2550\u2550 KpiRepo.getKpiTotals \u2192 canonical \u2550\u2550\u2550');
      for (final e in result.entries) {
        debugPrint('  ${e.key.padRight(22)}= ${e.value}');
      }
      debugPrint('  stripe_snap_available: ${stripeSnap != null}');
    }'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('OK: Moved rounding BEFORE debugPrint')
else:
    print('Pattern not found')
    # Try simplified version
    old2 = '''    if (kDebugMode) {
      debugPrint('KpiRepo.getKpiTotals')
'''
    if old2 in content:
        print('Simplified debugPrint pattern found')
    
    idx = content.find('Round all monetary')
    if idx >= 0:
        start = max(0, idx - 400)
        end = min(len(content), idx + 100)
        print(f'\nFound at {idx}. Showing context:')
        print(content[start:end])
