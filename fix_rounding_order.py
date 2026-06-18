import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old = '''    // Round all monetary values to 2 decimal places
    for (final k in result.keys) {
      if (result[k] is double) {
        result[k] = ((result[k] as double) * 100).round() / 100;
      }
    }
    if (kDebugMode) {
      debugPrint('═══ KpiRepo.getKpiTotals → canonical ═══');
      for (final e in result.entries) {
        debugPrint('  ${e.key.padRight(22)}= ${e.value}');
      }
      debugPrint('  stripe_snap_available: ${stripeSnap != null}');
    }
    // ignore: unawaited_futures
    UiLogger.snapshot'''

new = '''    if (kDebugMode) {
      debugPrint('═══ KpiRepo.getKpiTotals → canonical ═══');
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
    }
    // ignore: unawaited_futures
    UiLogger.snapshot'''

if old in content:
    content = content.replace(old, new)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    print('OK: Moved rounding AFTER debugPrint')
else:
    print('Pattern not found')
    # Find the rounding code
    idx = content.find('Round all monetary')
    if idx >= 0:
        # Show surrounding context
        start = max(0, idx - 300)
        end = min(len(content), idx + 400)
        print(f'Found at {idx}. Context:')
        print(content[start:end])
    else:
        print('Rounding code not found!')
