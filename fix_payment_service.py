import os

path = r'C:\Users\marti\tools\StudioProjects\toro-rider-web\lib\core\services\payment_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix the insert status: 'succeeded' -> 'success' and add country_code
old1 = "        'status': transaction.status.name,\n        'stripe_payment_intent_id': transaction.stripePaymentIntentId,\n        'stripe_transfer_id': transaction.stripeTransferId,\n        'created_at': transaction.createdAt.toIso8601String(),\n        'completed_at': transaction.completedAt?.toIso8601String(),\n      });"

new1 = "        'status': transaction.status == PaymentTransactionStatus.succeeded ? 'success' : transaction.status.name,\n        'country_code': 'MX',\n        'booking_type': transaction.serviceType,\n        'stripe_payment_intent_id': transaction.stripePaymentIntentId,\n        'stripe_transfer_id': transaction.stripeTransferId,\n        'created_at': transaction.createdAt.toIso8601String(),\n        'completed_at': transaction.completedAt?.toIso8601String(),\n      });"

if old1 in content:
    content = content.replace(old1, new1)
    print("1. Fixed insert: succeeded->success, added country_code and booking_type")
else:
    print("1. WARNING: Could not find insert status pattern")
    # Find the insert block
    idx = content.find("from('transactions').insert")
    if idx >= 0:
        print(f"   Found 'from(transactions).insert' at position {idx}")
        print(f"   Context: ...{content[idx:idx+500]}...")

# 2. Fix updateTransactionStatus to map succeeded->success
old2 = "        'status': status.name,\n        'completed_at': completedAt?.toIso8601String(),\n      };"

new2 = "        'status': status == PaymentTransactionStatus.succeeded ? 'success' : status.name,\n        'completed_at': completedAt?.toIso8601String(),\n      };"

if old2 in content:
    content = content.replace(old2, new2)
    print("2. Fixed updateTransactionStatus: succeeded->success")
else:
    print("2. WARNING: Could not find updateTransactionStatus pattern")
    idx = content.find("'completed_at':")
    if idx >= 0:
        print(f"   Found 'completed_at' at position {idx}")
        print(f"   Context: ...{content[idx-50:idx+100]}...")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('\nDONE: payment_service.dart updated')
