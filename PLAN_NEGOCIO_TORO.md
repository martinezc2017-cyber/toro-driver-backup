# PLAN DE NEGOCIO TORO - NUMEROS REALES

---

## MODELO ACTUALIZADO (Feb 2026) — DOS CATEGORIAS + TORO NIVELAR

> **MODELO VIGENTE.** Dos categorias de servicio con Toro Nivelar activo en AMBAS.
> Wait & Save reemplaza el concepto de "Non-Peak Hours" — admin controla disponibilidad.

### DOS CATEGORIAS DE SERVICIO:
```
  NORMAL                          WAIT & SAVE
  ─────────────────────           ─────────────────────
  Minimum fare: $9.00             Minimum fare: $6.00
  Siempre disponible              Admin controla cuando (dias aleatorios)
  Rider lo ve siempre             Rider lo ve cuando admin lo activa
  Toro Nivelar: ON                Toro Nivelar: ON
  Split: 51/23.4/20/5.6           Split: 51/23.4/20/5.6 (mismo)

  Para que sirve Wait & Save:
  - Cubre demanda de viajes baratos (competir con Uber $6-7 min)
  - Admin lo activa dias aleatorios para controlar costos
  - Reemplaza "Non-Peak Hours" — es mas controlable
  - Rider puede esperar mas tiempo por un chofer a cambio de precio menor
```

### VALORES EN ADMIN WEB (fuente de verdad):
```
Driver:     51.0%
Platform:   23.4% (AUTO = 100 - 51 - 20 - 5.6)
Insurance:  20.0%
Tax AZ:      5.6%
TOTAL:     100.0%

Normal minimum_fare:        $9.00
Wait & Save minimum_fare:   $6.00
Toro Nivelar:               ON (ambas categorias)

DB: wait_and_save_enabled BOOLEAN, wait_and_save_minimum_fare DECIMAL
```

### DATOS REALES DE UBER (extraidos de 23 PDFs, Oct 2025 - Feb 2026):
```
11 semanas activas:
  Customer fare promedio/semana:  ~$999
  Driver fare promedio/semana:    ~$548 (55% del customer fare)
  Tips promedio/semana:           ~$60
  Trips promedio/semana:          ~42

Uber real split:
  Driver:         ~55%
  Insurance/Ops:  ~17%
  Uber Fee:       ~20%
  Gov fees:        ~3%
```

### SISTEMA TORO NIVELAR — Platform % Variable:
```
  Fare del trip     | Platform %  | Driver %  | Insurance | Tax
  $0 – $10          | 5%          | 69.4%     | 20%       | 5.6%
  $10 – $20         | 15%         | 59.4%     | 20%       | 5.6%
  $20 – $35         | 23.4%       | 51.0%     | 20%       | 5.6%
  $35+              | 25%         | 49.4%     | 20%       | 5.6%

DB columns (pricing_config):
  variable_platform_enabled    BOOLEAN
  platform_tier_1_max_fare     ($10)   platform_tier_1_percent (5%)
  platform_tier_2_max_fare     ($20)   platform_tier_2_percent (15%)
  platform_tier_3_max_fare     ($35)   platform_tier_3_percent (23.4%)
                                       platform_tier_4_percent (25%)

Configurable desde Admin Web > Comisiones > banner "Toro Nivelar"
```

### EJEMPLO — Trip Normal de 1 milla ($9.00 minimum fare):
```
                          Uber        Toro Normal     Diferencia
─────────────────────────────────────────────────────────────────
Rider paga:               $7.00       $9.00           +$2 (Toro min mas alto)
Driver (QR 0):            $3.85       $6.25           +62%
Driver (QR 3):            $3.85       $6.52           +69%
Driver (QR 5):            $3.85       $6.70           +74%
Platform:                 ~$1.40      $0.45 (5%)
Insurance:                incluido    $1.80
Tax:                      incluido    $0.50

Con $9 min + Nivelar Tier 1 (5%):
  Driver base = $9 × 69.4% = $6.25  <<< MUY atractivo vs Uber $3.85
```

### EJEMPLO — Trip Wait & Save de 1 milla ($6.00 minimum):
```
                          Uber        Toro W&S        Diferencia
─────────────────────────────────────────────────────────────────
Rider paga:               $7.00       $6.00           -$1 (Toro mas barato)
Driver (QR 0):            $3.85       $4.16           +8%
Driver (QR 3):            $3.85       $4.34           +13%
Driver (QR 5):            $3.85       $4.46           +16%
Platform:                 ~$1.40      $0.30 (5%)
Insurance:                incluido    $1.20
Tax:                      incluido    $0.34
```

### DISTRIBUCION REALISTA DE QR (por que el peor caso NUNCA pasa):
```
Un rider NO puede llegar a QR 10+ en un solo dia. Los niveles se
acumulan con viajes a lo largo de semanas/meses. Distribucion real:

  QR Level    | % de riders  | Riders/sem (de 42) | Costo QR avg
  ────────────|──────────────|────────────────────|──────────────
  QR 0 (nuevo)|  43%         | 18 riders          | $0 (sin QR)
  QR 1-3      |  29%         | 12 riders          | ~2% del fare
  QR 4-7      |  19%         |  8 riders          | ~5% del fare
  QR 8-12     |   7%         |  3 riders          | ~10% del fare
  QR 13-15    |   2%         |  1 rider            | ~14% del fare

  Promedio ponderado QR: (18×0 + 12×2 + 8×5.5 + 3×10 + 1×14) / 42
                       = 112 / 42 = 2.67% promedio

  vs peor caso: si TODOS fueran QR 15 = 15% (imposible)
  REALIDAD: 2.67% — casi 6 veces MENOS que el peor caso
```

### SIMULACION SEMANAL CORREGIDA (42 trips, numeros honestos):
```
IMPORTANTE: Los $999/sem de Uber YA INCLUYEN surge/peak pricing.
NO se puede agregar multiplier encima — seria doble conteo.
La unica diferencia real entre Uber y Toro es el minimum fare.

DE DONDE SALEN LOS NUMEROS:
  PDFs de Uber: Martin gana $548/sem como driver (esto es lo unico real)
  Uber le da ~55% al driver → customer fare = $548 / 0.55 = ~$999/sem
  42 trips/sem → promedio $23.79 por trip

TORO GROSS (mismos 42 trips, mismas distancias):
  Uber gross: $999/sem (ya incluye peaks/surges)
  Toro bump:  +$18/sem (~12 trips cortos suben de $7.50 a $9 por min fare)
  ──────────────────────────────────────────────────────
  TORO GROSS: ~$1,017/sem  (solo +1.8% mas que Uber)

DISTRIBUCION POR FARE TIER (42 trips, $1,017 gross):
  10 trips at $9     (min fare, Tier 1)  = $90
   7 trips at $12    (Tier 2)            = $84
  15 trips at $22    (Tier 3)            = $330
   8 trips at $45    (Tier 4)            = $360
   2 trips at $76.50 (Tier 4)            = $153
  ──────────────────────────────────────────────────────
  CHECK: $90+$84+$330+$360+$153 = $1,017 ✓

PLATFORM (NIVELAR):
  10 × $9   × 5%    = $4.50   (Tier 1)
   7 × $12  × 15%   = $12.60  (Tier 2)
  15 × $22  × 23.4% = $77.22  (Tier 3)
   8 × $45  × 25%   = $90.00  (Tier 4)
   2 × $76.50 × 25% = $38.25  (Tier 4)
  ──────────────────────────────────────────────────────
  PLATFORM BRUTO: $222.57/sem ($890/mes)

QR COSTO REALISTA:
  Driver QR bonus (drivers al max, avg QR 12):
    Bonus = 12% de driver_base por trip
    10 × ($9 × 69.4% × 12%)    = 10 × $0.75 = $7.50
     7 × ($12 × 59.4% × 12%)   =  7 × $0.86 = $5.99
    15 × ($22 × 51% × 12%)     = 15 × $1.35 = $20.20
     8 × ($45 × 49.4% × 12%)   =  8 × $2.67 = $21.33
     2 × ($76.50 × 49.4% × 12%)=  2 × $4.53 = $9.07
    SUBTOTAL driver QR: $64.09/sem

  Rider QR discount (lo guardan para largos, avg 2.67%):
    Solo ~30% de riders lo usan y solo en trips >$20
    15 medium × 30% × $22 × 2.67% = $2.64
     8 long   × 40% × $45 × 2.67% = $3.85
     2 XL     × 50% × $76 × 2.67% = $2.03
    SUBTOTAL rider QR: $8.52/sem

  TOTAL QR: $64 + $9 = $73/sem ($292/mes)

RESUMEN SEMANAL (1 chofer, numeros honestos):
  Gross:            $1,017/sem
  Platform bruto:   $223/sem
  QR total:         -$73/sem
  PLATFORM NETO:    $150/sem ($600/mes)
  Driver base:      $537/sem (gross - platform - insurance - tax)
  Driver + QR:      $537 + $64 QR = $601/sem
  Driver + QR + tip:$601 + $60 = $661/sem
  Insurance:        $1,017 × 20% = $203/sem ($813/mes → cubre $400 TNC)
  Tax:              $1,017 × 5.6% = $57/sem
```

### COMPARACION: TORO vs UBER (Martin como driver + dueno):
```
                              UBER          TORO (realista)
  ──────────────────────────────────────────────────────────
  Gross/sem (customer fare):  $999          $1,017
  Martin como driver/sem:     $548          $601 (base+QR)
  Tips/sem:                   $60           $60
  Martin total driver:        $608/sem      $661/sem
  Martin como dueno (plat):   $0            $150/sem
  MARTIN TOTAL/SEM:           $608          $811

  POR MES (×4.33):
  Ingreso bruto:              $2,633        $3,512
  - Gas:                      -$520         -$520
  - Desgaste:                 -$100         -$100
  - Infra (Supabase etc):     $0            -$70
  - TNC Insurance:            $0*           -$400
  ──────────────────────────────────────────────────────────
  NETO MES:                   $2,013        $2,422
  DIFERENCIA:                               +$409/mes (+20%)

  * Uber paga su propio seguro — el driver no lo ve.
  Con Toro: insurance pool genera $813/mes, paga $400 TNC,
  surplus $413/mes va a reserva/colchon.

  VENTAJA REAL DE TORO:
  - +$409/mes mas que Uber como 1 solo chofer
  - Cada chofer adicional agrega ~$150/sem ($650/mes) a platform
  - Con 3 choferes: platform gana $450/sem ($1,949/mes) extra
  - Con 5 choferes: platform gana $750/sem ($3,248/mes) extra
  - ESO es donde esta el negocio: escalar choferes
```

### QR — COMO FUNCIONA EL COSTO (NUMEROS HONESTOS):
```
DRIVER QR (lo van a tener AL MAXIMO):
  Los drivers lo grindean a 10-15 porque es dinero directo.
  Asumir: driver avg QR 12. Bonus = 12% de driver_base.

  Per trip con driver QR 12:
    $9 min:     driver_base $6.25 → bonus $0.75 → Plat: $0.45 - $0.75 = -$0.30
    $22 medio:  driver_base $11.22 → bonus $1.35 → Plat: $5.15 - $1.35 = $3.80
    $45 largo:  driver_base $22.23 → bonus $2.67 → Plat: $11.25 - $2.67 = $8.58
  Costo driver QR semanal: ~$64/sem ($277/mes)

RIDER QR (lo guardan para viajes largos):
  En $9 min: QR 3 = $0.27 descuento → una baba, no lo usan
  En $45 trip: QR 5 = $2.25 descuento → ahi si
  Solo ~30-40% lo usan en trips >$20.
  Costo rider QR semanal: ~$9/sem ($39/mes)

TOTAL QR: $73/sem ($316/mes)

POR QUE SIGUE SIENDO RENTABLE:
  Platform bruto $223/sem - QR $73/sem = $150/sem neto
  En trips cortos la plataforma pierde $0.30 per trip (subsidia)
  En trips medios/largos la plataforma gana $3.80-$8.58 per trip
  Los largos PAGAN el subsidio de los cortos — eso es Toro Nivelar.
```

### WAIT & SAVE — MODULADOR (reemplaza Non-Peak Hours):
```
Concepto: Admin controla cuando Wait & Save esta disponible.
  - NO es automatico por horario (como non-peak hours)
  - Admin activa/desactiva manualmente o por dias programados
  - Cuando esta ON: rider ve dos opciones (Normal $9 / W&S $6)
  - Cuando esta OFF: rider solo ve Normal $9
  - Dias aleatorios para controlar costos de plataforma

Admin Dashboard muestra:
  - Categoria activa actual (Normal only / Normal + W&S)
  - Promedio de trips por categoria (cuantos eligen W&S vs Normal)
  - Revenue promedio por categoria
  - Impacto en platform earnings cuando W&S esta activo

DB (pricing_config):
  wait_and_save_enabled          BOOLEAN DEFAULT false
  wait_and_save_minimum_fare     DECIMAL(10,2) DEFAULT 6.00
```

### SEGURO TNC:
```
Insurance at 20% genera (numeros corregidos):
  $1,017/sem × 20% = $203/sem = $813/mes

TNC Insurance Arizona: ~$400/mes por chofer
  → 1 chofer: $813 - $400 = $413 surplus (colchon)
  → 2 choferes: necesitan generar ~$800/mes, 1 chofer genera $813 → justo
  → 3+ choferes: cada chofer genera su propio $813 para cubrir su $400
```

### ESCALAMIENTO POR CHOFERES (numeros corregidos):
```
Choferes | Trips/sem | Gross/sem | Plat bruto | QR costo | Plat NET/sem | Plat NET/mes
1        | 42        | $1,017    | $223       | $73      | $150         | $650
3        | 126       | $3,051    | $669       | $219     | $450         | $1,949
5        | 210       | $5,085    | $1,115     | $365     | $750         | $3,248
10       | 420       | $10,170   | $2,230     | $730     | $1,500       | $6,495

Insurance por chofer: $203/sem = $813/mes (cubre $400 TNC + $413 surplus)

Ratio plat neto / plat bruto = ~67% (QR se come ~33%)
A 10 choferes: $6,495/mes platform neto — el negocio real es escalar.
Martin como driver adicional: +$661/sem ($2,862/mes) encima de esto.
```

### GUARDRAILS — NO MOVER SIN ENTENDER:
```
PELIGRO si mueves estos sin recalcular:
  !! Insurance % < 20% → NO cubre $400/mes TNC por chofer
  !! Variable platform OFF + driver < 51% → driver gana menos que Uber
  !! Peak multiplier > 2.0 → rider se va a Uber
  !! Normal minimum_fare < $9 → pierde ventaja vs Uber en trips cortos
  !! W&S minimum_fare < $6 → no competitivo, driver gana miseria

SEGURO MOVER:
  - Variable platform tiers (ajustar desde admin)
  - QR point value (1% por nivel es el default)
  - Peak hours (ajustar horarios y multipliers)
  - Booking fee, service fee
  - Wait & Save dias/horarios de activacion
```

### PENDIENTES TECNICOS:
```
[x] SQL migration: variable_platform_enabled + tiers en pricing_config
[x] Admin UI: Banner "Toro Nivelar" con toggle + sliders + simulacion
[x] SplitCalculator (driver app): usa getEffectivePlatformPercent()
[x] SplitCalculator (rider app): misma logica sincronizada
[x] financial_connection_service.dart: lee variable platform de pricing_config
[x] QR rider: platform absorbe descuento en trips minimos (implementado en codigo)
[x] Driver notification: mostrar desglose con bono despues de ride
[x] Financial audit: 10 columnas nuevas en deliveries + completeRide() actualizado
[ ] SQL migration: wait_and_save_enabled + minimum_fare en pricing_config
[ ] Rider app: mostrar dos opciones cuando W&S esta activo
[ ] Admin: modulador Wait & Save con estadisticas de categoria
[ ] Admin: actualizar minimum_fare Normal a $9 en pricing_config
[ ] QR Nacional: leaderboard + super bono + boton donar
[ ] Dashboard admin: luz verde "seguro meter siguiente chofer"
[ ] Documentar modelo en Admin Web (tooltip/info card)
```

---
---

## ═══════════════════════════════════════════════════
## PLAN ORIGINAL (números del Claude anterior, referencia)
## Usa split 57/29.4/8/5.6 y minimum_fare $10.50
## Los valores REALES del admin son 51/23.4/20/5.6 con $6 min
## ═══════════════════════════════════════════════════

## DATOS BASE (de la experiencia real de Martin con Uber)

```
Martin con Uber HOY:
  15 viajes/dia
  6 dias/semana
  ~$1,000/semana ($167/dia como driver)

Desglose:
  Gross promedio por viaje: ~$18.50 (lo que paga el rider)
  Uber toma ~40%:           -$7.40
  Martin recibe:             $11.10 por viaje

Con Toro (Martin es driver + dueno):
  Gross:                     $18.50
  Martin como driver (57%):  $10.55
  Toro = Martin (29.4%):     $5.44  <- TAMBIEN ES SUYO
  Insurance (8%):            $1.48
  Tax (5.6%):                $1.04
  Stripe (~):                -$0.84
  Martin total:              $15.15 por viaje

  DIFERENCIA: $15.15 vs $11.10 = +36% MAS con Toro
```

---

## 1. ESTRUCTURA DE PRECIOS (Arizona)

### Split:
```
Driver:     57.0%
Toro:       29.4%
Insurance:   8.0%
Tax:         5.6%
TOTAL:     100.0%
```

### Tarifas:
```
base_fare:        $2.50
per_mile_rate:    $0.85
per_minute_rate:  $0.16
minimum_fare:     $10.50
booking_fee:      $1.50
cancellation_fee: $5.00
service_fee:      $2.50
```

### Multiplicadores:
```
Normal:    x1.0  (9AM-4PM entre semana)
Peak AM:   x1.5  (7-9AM L-V)
Peak PM:   x1.5  (4-7PM L-V)
Night:     x1.3  (10PM-5AM)
Weekend:   x1.2  (Sab-Dom)
Surge:     hasta x2.0
```

---

## 2. GASTOS FIJOS MENSUALES

```
INFRAESTRUCTURA (se pagan siempre):
+-- Seguro comercial rideshare:  $250/mes
+-- Supabase Pro:                $25/mes
+-- Dominio/hosting:             $15/mes
+-- Apple Developer:             $8/mes
+-- Google Play:                 $2/mes
+-- Telefono/datos:              $60/mes
+-- AI tools:                    $20/mes
= SUBTOTAL INFRA:               $380/mes

VARIABLE (depende de cuanto manejas):
+-- Gasolina 15 trips/dia:      ~$20/dia = $520/mes
+-- Desgaste vehiculo:          ~$100/mes reserva
= SUBTOTAL VARIABLE:            $620/mes

TOTAL GASTOS OPERATIVOS:        $1,000/mes
```

---

## 3. MARTIN CON TORO A MAXIMA CAPACIDAD (15 viajes/dia)

Si Toro tuviera los mismos riders que Uber HOY:

```
15 viajes × $18.50 gross = $277.50/dia

Despues de Stripe ($0.84 avg per trip):
  $277.50 - $12.60 = $264.90 neto para split

  Driver Martin (57%):    $151.00/dia
  Toro Martin (29.4%):     $77.88/dia
  Insurance pool (8%):     $21.19/dia
  Tax pool (5.6%):         $14.83/dia

  MARTIN TOTAL/DIA:       $151.00 + $77.88 = $228.88
  - Pero insurance y tax salen del gross, ya estan separados

POR SEMANA (6 dias):      $228.88 × 6 = $1,373.28
POR MES (26 dias):        $228.88 × 26 = $5,950.88

MENOS GASTOS:             -$1,000/mes
NETO MES:                 $4,950.88/mes

VS UBER:                  $1,000 × 4.33 = $4,330/mes
                          - gasolina $520 - desgaste $100
                          = $3,710/mes neto

TORO: $4,950/mes vs UBER: $3,710/mes = +$1,240 MAS con Toro
```

**PERO**: Toro no tiene riders el dia 1. Ese es el reto.

---

## 4. ESTRATEGIA: MANEJAR UBER + TORO AL MISMO TIEMPO

```
LA CLAVE: No dejas Uber el dia 1.

FASE 1 (Mes 1-3): Uber + Toro simultaneo
  - Prendes AMBAS apps
  - Cuando llega ride de Toro, lo tomas (prioridad)
  - Cuando no hay Toro, tomas Uber
  - CADA rider de Uber que te toca, le das tarjeta:
    "Baja Toro. Mismo chofer. Mejor precio."
  - Tu ingreso de Uber sigue siendo ~$1,000/semana
  - Toro va creciendo poco a poco encima de eso

FASE 2 (Mes 4-6): Toro crece, Uber baja
  - Mas rides de Toro = menos tiempo en Uber
  - Cuando Toro llega a 8-10 rides/dia,
    Uber te da solo 5-7 (los huecos)
  - Ingreso sube porque Toro paga mas por viaje

FASE 3 (Mes 7+): Toro dominante
  - Toro llega a 12-15 rides/dia
  - Apagas Uber (o lo usas solo para huecos muertos)
  - Ingreso sube significativamente

ESTO CAMBIA TODO PORQUE:
- NUNCA pierdes tu ingreso base de $1,000/semana
- Cada ride de Toro que reemplaza un ride de Uber = +$4 extra
- No hay "meses en rojo" como en el plan anterior
- El crecimiento de Toro es ENCIMA de tu ingreso actual
```

---

## 5. CRECIMIENTO MES A MES - ANO 1

### Como consigues riders para Toro:

```
ARMA SECRETA: Ya manejas 15 rides/dia con Uber.
Eso es 90 riders/semana que puedes convertir.

Conversion realista:
  De 90 riders/semana que ven tu tarjeta:
  - 20% descargan la app (18 personas)
  - 30% de esos piden un ride (5-6 personas)
  - 50% de esos se vuelven regulares (2-3 personas)

  = 2-3 riders NUEVOS de Toro cada semana
  = 10-12 riders nuevos por mes

ADEMAS:
  - Posts en Facebook local groups
  - Boca a boca de riders satisfechos
  - Tarjetas en negocios locales
```

### MES 1: Lanzamiento (Uber + Toro)

```
Uber: 13 rides/dia (tu base)
Toro: 2 rides/dia (amigos + primeros converts)
TOTAL: 15 rides/dia

INGRESOS:
  Uber: 13 × $11.10 = $144.30/dia
  Toro: 2 × $15.15 = $30.30/dia
  TOTAL/DIA: $174.60

  TOTAL/MES (26 dias): $4,539.60
  GASTOS: -$1,000
  NETO MES 1: $3,539.60

  vs solo Uber: $3,710 - asi que basicamente igual
  PERO: ya empezaste a construir tu base Toro
```

### MES 2:

```
Uber: 11 rides/dia
Toro: 4 rides/dia
TOTAL: 15 rides/dia

  Uber: 11 × $11.10 = $122.10/dia
  Toro: 4 × $15.15 = $60.60/dia
  TOTAL/DIA: $182.70
  TOTAL/MES: $4,750.20
  GASTOS: -$1,000
  NETO: $3,750.20 (+$40 vs solo Uber)
```

### MES 3:

```
Uber: 9 rides/dia
Toro: 6 rides/dia
TOTAL: 15 rides/dia

  Uber: 9 × $11.10 = $99.90
  Toro: 6 × $15.15 = $90.90
  TOTAL/DIA: $190.80
  TOTAL/MES: $4,960.80
  GASTOS: -$1,000
  NETO: $3,960.80 (+$250 vs solo Uber)
```

### MES 4:

```
Uber: 7 rides/dia
Toro: 8 rides/dia (Toro ya domina!)
TOTAL: 15 rides/dia

  Uber: 7 × $11.10 = $77.70
  Toro: 8 × $15.15 = $121.20
  TOTAL/DIA: $198.90
  TOTAL/MES: $5,171.40
  GASTOS: -$1,000
  NETO: $4,171.40 (+$461 vs solo Uber)
```

### MES 5:

```
Uber: 5 rides/dia
Toro: 10 rides/dia
TOTAL: 15 rides/dia

  TOTAL/DIA: $207.00
  TOTAL/MES: $5,382.00
  GASTOS: -$1,000
  NETO: $4,382.00

  ADEMAS: con 10 Toro rides/dia,
  empiezas a tener LISTA DE ESPERA
  en horas peak. Necesitas otro driver.
```

### MES 6:

```
Uber: 3 rides/dia (solo huecos)
Toro: 12 rides/dia
TOTAL: 15 rides/dia

  TOTAL/DIA: $215.10
  TOTAL/MES: $5,592.60
  GASTOS: -$1,000
  NETO: $4,592.60

  RECHAZAS: 3-5 rides Toro/dia por estar ocupado
  TRIGGER: hora de buscar chofer #2
```

### MES 7: Apagas Uber, solo Toro + Chofer #2

```
Martin: 15 rides/dia Toro
Chofer #2: 3-5 rides/dia (overflow + nuevos)
TOTAL: ~20 rides/dia

Mas detalle del chofer #2:
  MODELO 1099: el trae su carro + su seguro
  Costo para Toro: $35 (background check)
  Toro gana de sus rides: 29.4% - Stripe

  Chofer #2: 4 rides × $18.50 = $74/dia gross
  Toro neto del #2: $74 × 29.4% = $21.76 - Stripe $3.45 = $18.31/dia

  MARTIN:
  Driver 15 rides: $151.00/dia
  Toro propio: $77.88/dia
  Toro del #2: $18.31/dia
  TOTAL: $247.19/dia
  TOTAL/MES: $6,426.94
  GASTOS: -$1,000
  NETO: $5,426.94
```

### MES 8-9: Chofer #2 crece

```
Chofer #2 sube a 8-10 rides/dia (sus propios regulares)

Martin: 15 rides/dia
Chofer #2: 9 rides/dia
TOTAL: 24 rides/dia

  Martin driver: $151.00
  Toro propio: $77.88
  Toro del #2: $41.20
  TOTAL/DIA: $270.08
  TOTAL/MES: $7,022.08
  GASTOS: -$1,000
  NETO: $6,022.08
```

### MES 10-12: Chofer #3, empiezas a rechazar otra vez

```
Martin: 15/dia
Chofer #2: 12/dia (ya esta full)
Chofer #3: 5/dia (empieza)
TOTAL: 32 rides/dia

  Martin driver: $151.00
  Toro propio: $77.88
  Toro de #2: $54.93
  Toro de #3: $22.89
  TOTAL/DIA: $306.70
  TOTAL/MES: $7,974.20
  GASTOS: -$1,000
  NETO: $6,974.20
```

---

## 6. TABLA ANO 1 COMPLETO

```
Mes | Uber | Toro | Total | Dia   | Mes Neto | Acumulado
----|------|------|-------|-------|----------|----------
 1  | 13   |  2   |  15   | $175  | $3,540   | $3,540
 2  | 11   |  4   |  15   | $183  | $3,750   | $7,290
 3  |  9   |  6   |  15   | $191  | $3,961   | $11,251
 4  |  7   |  8   |  15   | $199  | $4,171   | $15,422
 5  |  5   | 10   |  15   | $207  | $4,382   | $19,804
 6  |  3   | 12   |  15   | $215  | $4,593   | $24,397
 7  |  0   | 15+4 |  19   | $247  | $5,427   | $29,824
 8  |  0   | 15+7 |  22   | $260  | $5,760   | $35,584
 9  |  0   | 15+9 |  24   | $270  | $6,022   | $41,606
10  |  0   |15+12 |  27   | $290  | $6,540   | $48,146
11  |  0   |15+12+3| 30   | $300  | $6,800   | $54,946
12  |  0   |15+12+7| 34   | $315  | $7,190   | $62,136
----|------|------|-------|-------|----------|----------

NETO ANO 1: ~$62,136 (antes de income tax)
Income tax (~22%): ~-$13,670
NETO NETO ANO 1: ~$48,466

COMPARACION:
  Solo Uber todo el ano: $3,710 × 12 = $44,520 neto
  Toro ano 1:            $48,466 neto + negocio propio creciendo

  DIFERENCIA: +$3,946 MAS + un negocio que escala
```

---

## 7. ANO 2 - ESCALANDO (modelo 1099)

### Por que modelo 1099:
```
Cada chofer es contractor independiente:
- Trae su carro + su seguro
- Toro no paga seguro por el
- Costo para Toro: $35 one-time (background check)
- Cada chofer es rentable desde su PRIMER viaje

TORO GANA POR CHOFER (establecido, 12 rides/dia):
  12 × $18.50 = $222/dia gross
  Toro (29.4%): $65.27 - Stripe $10.28 = $54.99/dia
  = $1,429.74/mes por chofer

  ESO es lo que Toro gana NETO por cada chofer activo.
```

### Donde consigues choferes:
```
Tu pitch: "Ganas 57% en Toro vs 55-60% en Uber.
Pero en Toro el minimum fare es $10.50 vs Uber $7.
O sea: ganas mas por viaje corto. Mismos viajes."

Donde buscar:
  - Facebook: "Uber Drivers Phoenix", "Rideshare AZ"
  - Ex-Uber frustrados (hay miles)
  - Tus propios riders: "Conoces alguien que maneje Uber?"
  - Referido de choferes: $50 por chofer que traigan
```

### Timeline ano 2:

```
Mes 13 (inicio ano 2):
  Martin: 15 rides/dia
  2 choferes establecidos: 12 rides/dia cada uno
  1 chofer nuevo: 5 rides/dia
  TOTAL: 44 rides/dia

Mes 15:
  Agregas chofer #5 y #6
  TOTAL: ~65 rides/dia

Mes 18 (temporada baja - OJO):
  Rides bajan 30%
  TOTAL: ~45 rides/dia
  Pero NO pierdes dinero porque no pagas seguro de nadie
  Los choferes simplemente manejan menos
  Algunos se van a Uber temporalmente - esta bien

Mes 21 (vuelve temporada alta):
  Choferes regresan + agregas nuevos
  8 choferes + Martin
  TOTAL: ~85 rides/dia

Mes 24 (fin ano 2):
  10 choferes + Martin
  TOTAL: ~110 rides/dia
```

### Numeros ano 2:

```
CON 10 CHOFERES ACTIVOS (mes 24):

110 rides/dia × $18.50 = $2,035/dia gross

Toro de los 10 choferes (no Martin):
  95 rides × $18.50 = $1,757.50 gross
  Toro (29.4%): $516.71 - Stripe $81.38 = $435.33/dia

Martin driver (15 rides): $151.00/dia
Martin Toro propio: $77.88/dia
Toro de otros: $435.33/dia

MARTIN TOTAL/DIA: $664.21
MARTIN TOTAL/MES: $17,269.46

GASTOS:
+-- Infra:           $380
+-- Gasolina Martin: $520
+-- Desgaste:        $100
+-- Contabilidad:    $200
+-- Soporte:         $200
= TOTAL GASTOS:     $1,400/mes

NETO MES 24: $17,269 - $1,400 = $15,869/mes
            = $190,428/ano (ritmo)
```

---

## 8. ANO 3 - MARTIN DEJA DE MANEJAR

```
TRIGGER: Cuando Toro de otros choferes genera > $6,000/mes
(suficiente para vivir sin manejar)

Con 10 choferes eso ya pasa ($435/dia = $11,310/mes).
Podria dejar de manejar en mes 18-20.

PERO: Martin manejando genera $228/dia extra.
Mejor esperar a tener 15-20 choferes para que
el ingreso de Toro reemplace completamente.

20 choferes:
  19 × 12 rides + Martin 0 = 228 rides/dia
  228 × $18.50 = $4,218/dia gross
  Toro (29.4%): $1,240 - Stripe $195 = $1,045/dia
  MARTIN/MES: $27,170

  Si quiere, contrata:
  - 1 persona soporte ($3,000/mes)
  - Contador ($300/mes)

  NETO: $27,170 - $3,300 - $400 infra = $23,470/mes
  = $281,640/ano

Martin se enfoca 100% en:
  - Reclutar mas choferes
  - Mejorar la app
  - Abrir segunda ciudad
  - Marketing
```

---

## 9. ESCALAMIENTO ANO 3-5

```
ANO 3: 20-40 CHOFERES
  40 choferes × 12 rides × $18.50 = $8,880/dia gross
  Toro neto: ~$2,100/dia = $54,600/mes
  Gastos: empleados + infra = ~$8,000/mes
  NETO: ~$46,600/mes = $559,200/ano

ANO 4: 40-80 CHOFERES + SEGUNDA CIUDAD
  80 choferes
  Toro neto: ~$4,200/dia = $109,200/mes
  Gastos: 3 empleados + oficina + legal = ~$18,000/mes
  NETO: ~$91,200/mes = $1,094,400/ano

ANO 5: 100-200 CHOFERES, 3 CIUDADES
  150 choferes
  Toro neto: ~$7,800/dia = $202,800/mes
  Gastos: ~$50,000/mes (equipo, oficinas, legal, marketing)
  NETO: ~$152,800/mes = $1,833,600/ano
```

---

## 10. TABLA RESUMEN 5 ANOS

```
Ano | Choferes | Rides/dia | Toro/mes  | Gastos  | Neto/mes  | Neto/ano
----|----------|-----------|-----------|---------|-----------|----------
  1 | 1->3     | 15->34    | crece     | $1,000  | $3,500->7K| ~$62,000
  2 | 3->10    | 34->110   | $11,300   | $1,400  | ~$15,800  | ~$190,000
  3 | 10->40   | 110->480  | $54,600   | $8,000  | ~$46,600  | ~$559,000
  4 | 40->80   | 480->960  | $109,200  | $18,000 | ~$91,200  | ~$1.1M
  5 | 80->150  | 960->1800 | $202,800  | $50,000 | ~$152,800 | ~$1.8M

NOTA: Ano 1 incluye ingresos como driver + Uber.
Ano 2+ Martin deja de manejar progresivamente.
```

---

## 11. ESTACIONALIDAD (Phoenix)

```
TEMPORADA ALTA (Oct-Abr): Snowbirds, turistas, buen clima
  = numeros normales o +20-30%

TEMPORADA BAJA (May-Sep): 115°F, gente no sale
  = -30-40% rides

PERO CON MODELO 1099:
  No pagas seguro de nadie, no tienes gastos fijos por chofer.
  Si baja la demanda, los choferes manejan menos.
  Tu gasto fijo sigue siendo solo $1,000-1,400/mes.
  NUNCA pierdes dinero por temporada baja.

LOS CHOFERES:
  Temporada baja = algunos se van a Uber temporal
  Temporada alta = regresan + traen amigos
  Esto es NORMAL y esta bien.
```

---

## 12. COMO CONSEGUIR RIDERS

```
FASE 1 (Mes 1-6): CONVERSION DE TUS RIDERS DE UBER
  - Tarjeta en tu carro: "Prueba Toro - misma calidad, local"
  - 90 riders/semana ven tu tarjeta
  - 2-3 se convierten a regulares de Toro por semana
  - Meta: 50 riders activos para mes 6

FASE 2 (Mes 7-12): BOCA A BOCA + REDES
  - Cada rider Toro le dice a 1-2 personas
  - Posts en Facebook, Nextdoor, local groups
  - Tarjetas en bares, restaurantes, hoteles
  - "Refiere amigo: ambos ganan $5"
  - Meta: 200 riders activos para mes 12

FASE 3 (Ano 2): CRECIMIENTO ORGANICO
  - Con 10 choferes, cubres mas area
  - Mas disponibilidad = mejor servicio = mas riders
  - Google reviews empiezan a aparecer
  - App Store optimization
  - Meta: 800+ riders activos

FASE 4 (Ano 3+): MARKETING PAGADO
  - Facebook/Instagram Ads ($500-2,000/mes)
  - Google Ads (cuando buscan "ride Phoenix")
  - Partnerships con empresas locales
  - Meta: 3,000+ riders activos
```

---

## 13. COMO CONSEGUIR CHOFERES

```
Tu pitch: "57% para ti vs 55% en Uber. PERO nuestro
minimum fare es $10.50 vs Uber $7. En viajes cortos
ganas $2-3 MAS por viaje."

DONDE:
  - Facebook: "Uber Drivers Phoenix" (miles de miembros)
  - Referidos: $50 por chofer que traigan
  - Gasolineras y zonas de espera de rideshare
  - Craigslist, Indeed para gig drivers

INCENTIVO:
  - Primer semana: 0% comision Toro (100% para el driver)
  - Le cuesta a Toro ~$200 pero gana un driver

MODELO 1099:
  - Driver trae su carro + su seguro
  - No firman contrato exclusivo (pueden tener Uber tambien)
  - Manejan cuando quieran, cuanto quieran
  - Requisitos: carro 2015+, seguro, background check, licencia
```

---

## 14. RIESGOS Y MITIGACION

```
RIESGO 1: Riders no se cambian de Uber
  Impacto: Crecimiento lento
  Mitigacion: Manejas Uber + Toro simultaneo.
  Nunca pierdes tu ingreso base.
  Toro crece encima, no en vez de.

RIESGO 2: Temporada baja
  Impacto: -30-40% rides May-Sep
  Mitigacion: Modelo 1099 = sin gastos fijos por chofer.
  Ahorrar 30% de temporada alta.

RIESGO 3: Accidente
  Impacto: Claim contra el driver (su seguro)
  Con modelo 1099: es SU seguro, no el tuyo.
  Insurance pool (8%) es reserva extra.

RIESGO 4: Chofer malo
  Impacto: Reviews negativos
  Mitigacion: Rating minimo 4.5. Sacar rapido.

RIESGO 5: Uber baja precios en tu zona
  Impacto: Bajo (eres muy chico para que les importe)
  Mitigacion: Tu diferenciador es servicio personal,
  no precio.

RIESGO 6: Regulaciones TNC Arizona
  Impacto: Necesitas licencia/permisos
  Mitigacion: Investigar ANTES de lanzar.
  Arizona es muy business-friendly.
```

---

## 15. IMPUESTOS (obligatorio)

### USA (Arizona):
```
POR VIAJE:
+-- Sales tax: 5.6% del gross (ya separado en el split)
+-- TNC tax: $0.20/viaje
+-- Stripe fees: automatico

TRIMESTRAL:
+-- Estimated income tax (federal + AZ state)
+-- Self-employment tax: 15.3%

ANUAL:
+-- 1099-K para cada driver que gane >$600
+-- Tax return federal + estatal
+-- Insurance renewal
```

### MEXICO (futuro):
```
POR VIAJE:
+-- IVA 16% sobre servicio plataforma
+-- Retencion ISR driver: 2.5% (con RFC) / 20% (sin RFC)
+-- Retencion IVA driver: 8%

MENSUAL:
+-- Declaracion SAT + pagos
+-- CFDI (facturas electronicas)
```

---

## 16. FONDO BONO TORO

```
MAS RELEVANTE CUANDO HAY 5+ CHOFERES.
Con Martin solo, no tiene sentido (te pagas a ti mismo).

DE DONDE SALE:
  Peak:   Toro aporta $0.75/viaje
  Night:  Toro aporta $0.50/viaje
  Surge:  Toro aporta $1.50/viaje
  Normal: nada

PARA QUE:
  Bono $0.25-$0.50 al driver en viajes cortos normales
  "Toro invirtio en ti para que valga la pena"

REGLAS:
  < $50 saldo: se pausa
  > $500: excedente a reserva general
```

---

## 17. METRICAS PARA TRACKEAR

```
DIARIAS:
  - Rides completados (Toro vs Uber)
  - Rides rechazados/perdidos en Toro
  - Nuevos riders que descargaron

SEMANALES:
  - Riders activos de Toro
  - % de rides Toro vs Uber (meta: crecer cada semana)
  - Conversion rate (cuantos de tus Uber riders bajan Toro)

MENSUALES:
  - Neto total
  - Ahorro
  - Rider retention (cuantos repiten)
  - Costo por adquisicion de rider

TRIGGERS:
  - Rechazas >20% rides Toro -> agrega chofer
  - Retention <60% -> mejora servicio
  - Driver avg <8 rides/dia -> mas marketing riders
```

---

## 18. TABLAS DB NECESARIAS

```sql
-- Tracking ingresos plataforma
platform_revenue
platform_tax_obligations
sales_tax_collected
tnc_tax_collected

-- Tracking drivers (1099)
driver_1099_tracking
driver_annual_earnings

-- Fondo Bono Toro
toro_fund_balance
toro_fund_transactions

-- Ya existen (Mexico):
tax_retentions
tax_monthly_summary
```

---

## 19. PRIORIDADES TECNICAS PARA LANZAMIENTO

```
PRIORIDAD 1 (OBLIGATORIO PARA LANZAR):
[ ] Tax tracking de Toro (sales tax, TNC)
[ ] Actualizar minimum_fare a $10.50
[ ] Stripe integration completa

PRIORIDAD 2 (ANTES DE CHOFER #2):
[ ] Driver 1099 tracking (>$600)
[ ] Onboarding flow nuevos drivers
[ ] Background check integration

PRIORIDAD 3 (MEJORAS):
[ ] Fondo Bono Toro
[ ] Fix QR system bugs
[ ] Ticket transparente
```

---

## 20. RESUMEN EJECUTIVO

```
SITUACION ACTUAL:
  Martin gana ~$1,000/semana con Uber (15 rides/dia)

CON TORO:
  Mismo trabajo, +36% mas por viaje ($15.15 vs $11.10)
  Ano 1: $62K (driver + dueno, transicion gradual de Uber)
  Ano 2: $190K (10 choferes, modelo 1099)
  Ano 3: $559K (40 choferes)
  Ano 5: $1.8M (150 choferes, 3 ciudades)

VENTAJA:
  Nunca pierdes ingreso - Uber sigue mientras Toro crece
  Cada rider de Uber es un rider potencial de Toro
  Modelo 1099 = cero gastos fijos por chofer
  Crecimiento organico, sin deuda, sin inversionistas

DIFERENCIADOR:
  Driver gana 57% (vs Uber 55-60%)
  Minimum fare $10.50 (vs Uber $7) = driver gana mas en cortos
  Servicio personal, local
  Transparencia total en ticket
```
