import os

path = r'C:\Users\marti\Documents\projects\toro-admin-web\lib\features\admin\repositories\kpi_repo.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Buscar método _isTestTransaction
start = content.find('bool _isTestTransaction')
end = content.find('// =========', start)
if end == -1:
    end = content.find('// BREAKDOWN', start)
if end == -1:
    end = start + 700
print("=== _isTestTransaction METHOD ===")
print(content[start:end])
print("=== END ===")

# Check the getKpiTotals loop
loop_start = content.find('for (final r in (raw as List))', content.find('double grossTotal'))
if loop_start > 0:
    loop_end = content.find('transactionCount++;', loop_start)
    if loop_end > 0:
        print("\n=== GETKPI TOTALS LOOP (from for to after transactionCount) ===")
        print(content[loop_start:loop_end+200])
    else:
        print(f"\nLoop found at {loop_start}")
        print(content[loop_start:loop_start+800])
else:
    print("getKpiTotals loop not found")
    
# Count test transactions in the raw data
print("\n=== Checking if metadata filter would work ===")
# Simulate what the filter would do with some test data
test_meta = {"test": "webhook-validation-2026-06-11", "type": "wallet_topup"}
real_meta = {"stripe_account": "acct_123", "backfilled_from": "connect"}
nested_meta = {"stripe_account": "acct_123", "original_metadata": {"test": "webhook-validation"}}

for name, meta in [("DIRECT test key", test_meta), ("REAL", real_meta), ("NESTED test", nested_meta)]:
    print(f"\n{name}: {meta}")
    if meta is dict:
        if 'test' in meta:
            print(f"  -> 'test' in meta: YES -> FILTERED OUT")
        else:
            print(f"  -> 'test' in meta: NO")
        vals = ' '.join(str(v) for v in meta.values()).lower()
        if 'test' in vals:
            print(f"  -> 'test' in values: YES -> FILTERED OUT")
        else:
            print(f"  -> 'test' in values: NO")
    meta_str = str(meta).lower()
    if 'test:' in meta_str:
        print(f"  -> 'test:' in string: YES -> FILTERED OUT")
    else:
        print(f"  -> 'test:' in string: NO")
