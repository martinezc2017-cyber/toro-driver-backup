import csv
from collections import Counter, defaultdict

path = r'C:\Users\marti\Downloads\rides_1781236113974.csv'
with open(path, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    rows = list(reader)

print(f"Total rows: {len(rows)}")
print(f"Columns: {list(rows[0].keys()) if rows else 'empty'}")
print()

if rows:
    # Show first 3 rows fully
    for i, r in enumerate(rows[:3]):
        print(f"--- Row {i} ---")
        for k, v in r.items():
            print(f"  {k}: {v}")
    
    # Column summaries
    for col in rows[0].keys():
        vals = Counter()
        for r in rows:
            vals[r[col]] += 1
        top = vals.most_common(10)
        print(f"\n--- {col} ---")
        if len(vals) > 10:
            print(f"  ({len(vals)} unique values, showing top 10)")
        for v, cnt in top:
            print(f"  '{v}': {cnt}")
