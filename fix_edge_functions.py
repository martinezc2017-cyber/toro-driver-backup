import os

# 1. Fix stripe-create-payment-intent
path1 = r'C:\Users\marti\tools\StudioProjects\toro-rider-web\supabase\functions\stripe-create-payment-intent\index.ts'

with open(path1, 'r', encoding='utf-8') as f:
    content = f.read()

# Add country_code and metadata from rider profile to transactionData
old1 = "      metadata: {\n        booking_id: bookingId,\n        booking_type: bookingType,\n      },\n    }\n\n    // Link to appropriate booking table"

new1 = """      country_code: resolvedCurrency === 'mxn' ? 'MX' : (resolvedCurrency === 'usd' ? 'US' : 'US'),
      currency: resolvedCurrency,
      metadata: {
        booking_id: bookingId,
        booking_type: bookingType,
        currency: resolvedCurrency,
        ...metadata,
      },
    }

    // Link to appropriate booking table"""

if old1 in content:
    content = content.replace(old1, new1)
    print("1. stripe-create-payment-intent: Added country_code, currency to transaction")
else:
    print("1. WARNING: Pattern not found in stripe-create-payment-intent")
    idx = content.find("metadata: {")
    if idx >= 0:
        print(f"   Found 'metadata:' at position {idx}")
        print(f"   Context: ...{content[idx-50:idx+100]}...")

# Also add country_code to minimal retry
old1b = "        stripe_payment_intent_id: paymentIntent.id,\n        payment_method: 'card',\n      }"

new1b = """        stripe_payment_intent_id: paymentIntent.id,
        payment_method: 'card',
        country_code: resolvedCurrency === 'mxn' ? 'MX' : (resolvedCurrency === 'usd' ? 'US' : 'US'),
      }"""

if old1b in content:
    content = content.replace(old1b, new1b)
    print("2. stripe-create-payment-intent: Added country_code to minimal retry")
else:
    print("2. WARNING: Minimal retry pattern not found")

with open(path1, 'w', encoding='utf-8') as f:
    f.write(content)

# 2. Fix stripe-capture-payment
path2 = r'C:\Users\marti\tools\StudioProjects\toro-rider-web\supabase\functions\stripe-capture-payment\index.ts'

if os.path.exists(path2):
    with open(path2, 'r', encoding='utf-8') as f:
        content2 = f.read()
    
    # Add metadata about captured event to transaction update
    old2 = "status: 'success',"
    new2 = """status: 'success',
              metadata: supabaseMetadata,  // Preserve original metadata"""
    
    if old2 in content2:
        content2 = content2.replace(old2, new2, 1)  # Only first occurrence
        print(f"3. stripe-capture-payment: Added metadata to status update")
    else:
        print("3. WARNING: 'success' status not found in stripe-capture-payment")
        count = content2.count("'success'")
        print(f"   Found {count} occurrences of 'success'")
    
    with open(path2, 'w', encoding='utf-8') as f:
        f.write(content2)
else:
    print(f"3. stripe-capture-payment not found at {path2}")

# 3. Fix stripe-webhook to skip test charges
path3 = r'C:\Users\marti\tools\StudioProjects\toro-rider-web\supabase\functions\stripe-webhook\index.ts'

if os.path.exists(path3):
    with open(path3, 'r', encoding='utf-8') as f:
        content3 = f.read()
    
    # Add test charge detection before payment_intent.succeeded handler
    old3 = "      case 'payment_intent.succeeded': {\n        // Pago de usuario exitoso - distribuir al driver\n        const paymentIntent = event.data.object as Stripe.PaymentIntent\n        const metadata = paymentIntent.metadata\n\n        if (metadata.driver_id && metadata.ride_id) {"

    new3 = """      case 'payment_intent.succeeded': {
        // Pago de usuario exitoso - distribuir al driver
        const paymentIntent = event.data.object as Stripe.PaymentIntent
        const metadata = paymentIntent.metadata

        // SKIP test/e2e charges - these are not real transactions
        if (metadata?.e2e_audit === 'true' || metadata?.e2e || metadata?.test || metadata?.source === 'webhook-validation') {
          console.log('SKIP test/e2e charge:', paymentIntent.id)
          break
        }

        if (metadata.driver_id && metadata.ride_id) {"""

    if old3 in content3:
        content3 = content3.replace(old3, new3)
        print("4. stripe-webhook: Added test charge detection for payment_intent.succeeded")
    else:
        print("4. WARNING: payment_intent.succeeded handler not found")
        idx = content3.find("payment_intent.succeeded")
        if idx >= 0:
            print(f"   Found at position {idx}")
            print(f"   Context: ...{content3[idx:idx+300]}...")
    
    with open(path3, 'w', encoding='utf-8') as f:
        f.write(content3)
else:
    print(f"4. stripe-webhook not found at {path3}")

print('\nDONE: All edge functions updated')
