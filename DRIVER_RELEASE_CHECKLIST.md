# TORO Driver — checklist de publicación

Versión preparada: `1.2.84+4126`

## Validación automática completada

- [x] Catálogos `en`, `es` y `es-MX` con las mismas claves.
- [x] Formatos de moneda, distancia y país sin asumir México en USA.
- [x] Stripe Connect y retiros seleccionan proveedor y cuenta por `US` o `MX`.
- [x] Evidencia de instalación usa un identificador estable por dispositivo.
- [x] Sign in with Apple usa el botón oficial y la eliminación de cuenta llama al servidor.
- [x] `PrivacyInfo.xcprivacy` e `Info.plist` declaran el uso real de datos y permisos.
- [x] Pruebas de regresión de Driver, Rider/backend y Command Center.
- [x] APK release y AAB release firmados.
- [x] Command Center web compila en release.

## Backend obligatorio antes de publicar

- [ ] Aplicar las migraciones `20260819_driver_stripe_accounts_us.sql`, `20260820_driver_stripe_country_contract.sql`, `20260820_stripe_customers_by_country.sql` y `20260820_app_installations_and_supply_demand.sql`.
- [ ] Desplegar las Edge Functions Stripe modificadas y `delete-account`.
- [ ] Configurar `STRIPE_US_SECRET_KEY` y `STRIPE_MX_SECRET_KEY` en Supabase.
- [ ] Configurar `APPLE_DRIVER_CLIENT_ID=com.tororide.driver`.
- [ ] Configurar `APPLE_DRIVER_CLIENT_SECRET`, o bien `APPLE_TEAM_ID`, `APPLE_KEY_ID` y `APPLE_PRIVATE_KEY`.
- [ ] Confirmar que las cuentas Connect USA están creadas en `driver_stripe_accounts_us` y las de México en `driver_stripe_accounts_mx`.
- [ ] Ejecutar `tools/pricing_contract_check.sh` con `PGPASSWORD` o `SUPABASE_DB_PASSWORD` para auditar el esquema vivo.

## Prueba manual en dispositivos reales

- [ ] iPhone configurado en USA: registro, ubicación, documentos, precios USD, millas, Stripe USA, retiro y eliminación de cuenta.
- [ ] iPhone configurado en México: registro, ubicación, documentos, precios MXN, kilómetros, Stripe México, retiro y eliminación de cuenta.
- [ ] Android USA y México: repetir el flujo financiero y comprobar notificaciones en segundo plano.
- [ ] Cambiar entre English, Español y Español (México); reiniciar la app y confirmar persistencia.
- [ ] Verificar que no aparezcan pantallas, bancos, estados, monedas o documentos del país contrario.
- [ ] Instalar, abrir, autenticar y reinstalar; confirmar en Command Center que dispositivo, cuenta, país, ciudad, plataforma, versión y última actividad no se duplican incorrectamente.
- [ ] Comparar demanda Rider contra conductores Driver disponibles por región en Command Center.

## App Store Connect

- [ ] Subir una build generada en macOS/Codemagic con el mismo `pubspec.yaml` y bundle ID `com.tororide.driver`.
- [ ] Usar capturas reales de Driver en iPhone/iPad, sin barras o pantallas Android.
- [ ] Declarar únicamente los datos que realmente recopila la app y marcar que no se usan para tracking si esa sigue siendo la configuración real.
- [ ] Proporcionar una cuenta de revisión funcional y notas con pasos para probar USA/México, Stripe sandbox y eliminación de cuenta.
- [ ] Revisar que descripción, idiomas, política de privacidad, soporte y funciones visibles coincidan exactamente con la build.

## Google Play

- [ ] Subir `build/app/outputs/bundle/release/app-release.aab`.
- [ ] Completar Data Safety, acceso a la app, eliminación de cuenta, permisos de ubicación en segundo plano y credenciales de revisión.
- [ ] Probar primero en Internal testing antes de promover a producción.

## Publicación

- [ ] No publicar la app móvil antes de desplegar y verificar el backend correspondiente.
- [ ] No cambiar versión, migraciones, secretos o build después de completar las pruebas sin repetir este checklist.
