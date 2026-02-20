// Legal documents for TORO DRIVER v2.0
// Multi-language: English (en) + Spanish (es)
// Effective Date: February 2026
// Entity: TORO DRIVER LLC, Delaware, USA

import 'legal_constants.dart';

class LegalDocuments {
  LegalDocuments._();

  // ============================================================================
  // LANGUAGE-AWARE DOCUMENT ACCESSORS
  // ============================================================================

  static String getTermsAndConditions(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _termsEs;
      default:
        return _termsEn;
    }
  }

  static String getPrivacyPolicy(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _privacyEs;
      default:
        return _privacyEn;
    }
  }

  static String getIndependentContractorAgreement(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _icaEs;
      default:
        return _icaEn;
    }
  }

  static String getSafetyPolicy(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _safetyEs;
      default:
        return _safetyEn;
    }
  }

  static String getBackgroundCheckConsent(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _backgroundCheckEs;
      default:
        return _backgroundCheckEn;
    }
  }

  static String getLiabilityWaiver(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _waiverEs;
      default:
        return _waiverEn;
    }
  }

  static String getMexicoAddendum(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _mexicoAddendumEs;
      default:
        return _mexicoAddendumEn;
    }
  }

  /// Get combined document in specified language
  static String getCombinedDocument(String languageCode) {
    return '''
${getTermsAndConditions(languageCode)}

${getPrivacyPolicy(languageCode)}

${getIndependentContractorAgreement(languageCode)}

${getSafetyPolicy(languageCode)}

${getBackgroundCheckConsent(languageCode)}

${getLiabilityWaiver(languageCode)}
''';
  }

  /// Get combined document including Mexico addendum
  static String getCombinedDocumentWithMexico(String languageCode) {
    return '''
${getCombinedDocument(languageCode)}

${getMexicoAddendum(languageCode)}
''';
  }

  static String getOrganizerPlatformAgreement(String languageCode) {
    switch (languageCode.toLowerCase()) {
      case 'es':
      case 'es-mx':
        return _organizerAgreementEs;
      default:
        return _organizerAgreementEn;
    }
  }

  /// Default combined legal document (English)
  static String get combinedLegalDocument => getCombinedDocument('en');

  /// Get combined document based on device locale
  static String getCombinedDocumentForLocale(String? localeCode) {
    final code = localeCode?.toLowerCase().split('_').first ?? 'en';
    return getCombinedDocument(code);
  }

  // ============================================================================
  // Backward compatibility aliases
  // ============================================================================

  static String get termsAndConditions => _termsEn;
  static String get privacyPolicy => _privacyEn;
  static String get driverAgreement => _icaEn;
  static String get liabilityWaiver => _waiverEn;
  static String get safetyPolicy => _safetyEn;
  static String get backgroundCheckConsent => _backgroundCheckEn;

  // ============================================================================
  // ENGLISH DOCUMENTS v2.0
  // ============================================================================

  static String get _termsEn => '''
================================================================================
${LegalConstants.companyName} - TERMS AND CONDITIONS OF SERVICE
Version ${LegalConstants.termsVersion} | Effective Date: February 2026
Entity: ${LegalConstants.companyLegalName} | Jurisdiction: ${LegalConstants.companyJurisdiction}
================================================================================

PLEASE READ THESE TERMS CAREFULLY BEFORE USING TORO DRIVER.

By accessing or using the Toro Driver application ("App"), you agree to be bound
by these Terms and Conditions ("Terms"). If you do not agree, do not use the App.

--------------------------------------------------------------------------------
1. ACCEPTANCE OF TERMS
--------------------------------------------------------------------------------

By creating an account or using Toro Driver, you acknowledge that you have read,
understood, and agree to these Terms, the Privacy Policy, Independent Contractor
Agreement, Safety Policy, Liability Waiver, and all applicable laws.

--------------------------------------------------------------------------------
2. DESCRIPTION OF SERVICE
--------------------------------------------------------------------------------

Toro Driver is a technology platform that facilitates connections between
independent third-party service providers ("Drivers") and users seeking
transportation or delivery services.

IMPORTANT CLARIFICATIONS:

- Toro Driver is NOT a transportation provider, carrier, taxi company,
  chauffeur service, or logistics operator.
- Toro Driver does NOT own, lease, dispatch, or control vehicles.
- Toro Driver does NOT employ Drivers.
- Drivers act solely as independent third-party providers.
- Toro Driver does NOT control how Drivers perform services, select routes,
  operate vehicles, or interact with riders, except for minimum platform rules.
- Nothing in this Agreement creates employment, agency, apparent agency,
  partnership, joint venture, or representation of any kind.

All services are provided exclusively by Drivers.

--------------------------------------------------------------------------------
2.1 NO AGENCY / NO APPARENT AGENCY
--------------------------------------------------------------------------------

Drivers are NOT agents, employees, or representatives of Toro Driver.

Drivers are NOT authorized to:
- Represent themselves as Toro Driver employees or agents
- Use phrases such as "I work for Toro" or "Toro Driver employee"
- Bind Toro Driver to obligations
- Make guarantees or promises on Toro Driver's behalf

Users acknowledge that Toro Driver only provides software and safety tools.

--------------------------------------------------------------------------------
2.2 NO GUARANTEE OF SAFETY
--------------------------------------------------------------------------------

Toro Driver may offer safety features such as identity verification, trip sharing,
SOS buttons, or optional audio/video recording.

THESE FEATURES REDUCE RISK BUT DO NOT GUARANTEE SAFETY.

Toro Driver does not guarantee that incidents, crimes, accidents, harassment,
assaults, or misconduct will not occur.

--------------------------------------------------------------------------------
3. ELIGIBILITY REQUIREMENTS
--------------------------------------------------------------------------------

To use Toro Driver, you must:
- Be at least 21 years old
- Hold a valid driver's license (min. 1 year)
- Pass background and driving record checks
- Maintain valid insurance
- Have legal work authorization
- Provide accurate information

--------------------------------------------------------------------------------
4. DRIVER RESPONSIBILITIES
--------------------------------------------------------------------------------

Drivers agree to:
- Operate safely and lawfully
- Maintain vehicle safety
- Treat riders with respect
- Decline trips if unsafe
- Never operate while impaired
- Report incidents immediately

--------------------------------------------------------------------------------
5. INDEPENDENT CONTRACTOR STATUS
--------------------------------------------------------------------------------

Drivers acknowledge:
- Independent contractor status
- Freedom to accept or decline trips
- No exclusivity
- Responsibility for taxes
- No employee benefits
- No agency or apparent agency relationship

--------------------------------------------------------------------------------
6. PAYMENT TERMS
--------------------------------------------------------------------------------

- Fares are calculated by distance, time, and service type
- Toro Driver retains a platform fee
- Payments are issued weekly
- Tips belong 100% to Drivers
- Disputes must be raised within 30 days

--------------------------------------------------------------------------------
7. VEHICLE AND INSURANCE REQUIREMENTS
--------------------------------------------------------------------------------

Drivers must maintain:
- Compliant vehicle
- Valid registration
- Required insurance
- Commercial coverage if required by law

--------------------------------------------------------------------------------
8. SAFETY & ZERO TOLERANCE
--------------------------------------------------------------------------------

ZERO TOLERANCE for:
- Sexual misconduct of any kind
- Harassment or intimidation
- Violence or threats
- Discrimination
- Substance impairment

Violations result in immediate deactivation and potential reporting to authorities.

--------------------------------------------------------------------------------
9. INCIDENT REPORTING & EVIDENCE PRESERVATION
--------------------------------------------------------------------------------

Drivers must immediately report:
- Accidents or collisions
- Threats or assaults
- Suspicious behavior
- Safety concerns

Toro Driver may preserve:
- GPS data and trip telemetry
- Audio/video recordings (if enabled)
- Chat logs and communications
- Safety event data

Evidence is preserved for legal proceedings and regulatory compliance.

--------------------------------------------------------------------------------
10. LIMITATION OF LIABILITY
--------------------------------------------------------------------------------

To the maximum extent permitted by law:
- Toro Driver is not liable for acts of Drivers or riders
- No liability for criminal acts of third parties
- Total liability capped at fees paid in last 3 months or USD \$100,
  whichever is lesser

--------------------------------------------------------------------------------
11. INDEMNIFICATION
--------------------------------------------------------------------------------

Drivers agree to indemnify and hold harmless Toro Driver from any claims arising
from their conduct, violations, or negligence.

--------------------------------------------------------------------------------
12. DISPUTE RESOLUTION & ARBITRATION
--------------------------------------------------------------------------------

- Binding individual arbitration required
- No class or collective actions
- Opt-out allowed within 30 days of registration

--------------------------------------------------------------------------------
13. GOVERNING LAW
--------------------------------------------------------------------------------

Governing law: State of California, USA

--------------------------------------------------------------------------------
14. CONTACT
--------------------------------------------------------------------------------

Legal: ${LegalConstants.companyEmail}
Driver Support: ${LegalConstants.supportEmail}

================================================================================
END OF TERMS AND CONDITIONS v${LegalConstants.termsVersion}
================================================================================
''';

  static String get _privacyEn => '''
================================================================================
${LegalConstants.companyName} - PRIVACY POLICY
Version ${LegalConstants.privacyVersion} | Effective Date: February 2026
================================================================================

Toro Driver collects data strictly to operate the platform, ensure safety,
comply with law, and defend legal claims.

--------------------------------------------------------------------------------
1. INFORMATION WE COLLECT
--------------------------------------------------------------------------------

A. INFORMATION YOU PROVIDE:
- Account information (name, email, phone, address)
- Identity documents (driver's license, photo ID)
- Vehicle information (make, model, year, registration, insurance)
- Payment information (bank account for deposits)
- Background check consent and information
- Profile photo

B. INFORMATION COLLECTED AUTOMATICALLY:
- Location data (GPS tracking during active rides)
- Trip data (routes, duration, distance)
- Device information (model, OS, unique identifiers)
- App usage data and interaction patterns
- Optional audio/video recordings (if enabled by user)
- Safety events and SOS triggers

C. INFORMATION FROM THIRD PARTIES:
- Background check results
- Driving record information
- Insurance verification
- Identity verification results

--------------------------------------------------------------------------------
2. HOW WE USE YOUR INFORMATION
--------------------------------------------------------------------------------

We use your information to:
- Verify your identity and eligibility
- Connect you with riders seeking services
- Process payments and tax documentation
- Ensure safety and security of our platform
- Improve our services
- Communicate important updates
- Comply with legal and regulatory requirements
- Investigate incidents and resolve disputes
- Preserve evidence when required by law

--------------------------------------------------------------------------------
3. LOCATION DATA
--------------------------------------------------------------------------------

We collect precise location data to:
- Match you with nearby ride requests
- Provide navigation and routing
- Calculate accurate fares
- Ensure rider safety
- Investigate incidents and disputes
- Comply with regulatory requirements

Location is tracked when you are online/available.
You can go offline to stop location tracking.

--------------------------------------------------------------------------------
4. RECORDING AND EVIDENCE
--------------------------------------------------------------------------------

If audio/video recording features are enabled:
- Recordings may be stored for safety purposes
- Evidence is preserved when an incident is reported
- Legal hold is applied when required by law or litigation
- Recordings are encrypted at rest and in transit
- Two-party consent state requirements are followed

--------------------------------------------------------------------------------
5. DATA SHARING
--------------------------------------------------------------------------------

We may share your information with:
- Riders (name, photo, vehicle info, real-time location during trips)
- Background check providers
- Payment processors
- Law enforcement (upon valid legal request)
- Legal counsel (for claims defense)

WE DO NOT SELL YOUR PERSONAL INFORMATION.

--------------------------------------------------------------------------------
6. DATA RETENTION
--------------------------------------------------------------------------------

- Active accounts: As long as you remain active
- Trip records: 7 years for tax and legal compliance
- Safety evidence: Preserved if incident reported
- After deactivation: 90 days, then anonymized/deleted
- Background check data: As required by law

--------------------------------------------------------------------------------
7. YOUR RIGHTS
--------------------------------------------------------------------------------

You have the right to:
- ACCESS: Request a copy of your personal data
- CORRECT: Update inaccurate information
- DELETE: Request deletion of your account and data
- OPT-OUT: Control marketing communications
- PORTABILITY: Receive your data in portable format

Contact: ${LegalConstants.privacyEmail}

--------------------------------------------------------------------------------
8. CALIFORNIA PRIVACY RIGHTS (CCPA)
--------------------------------------------------------------------------------

California residents have additional rights:
- Right to know what personal information is collected
- Right to delete personal information
- Right to opt-out of sale of personal information
- Right to non-discrimination for exercising privacy rights

--------------------------------------------------------------------------------
9. CONTACT
--------------------------------------------------------------------------------

Privacy: ${LegalConstants.privacyEmail}
Support: ${LegalConstants.supportEmail}

================================================================================
END OF PRIVACY POLICY v${LegalConstants.privacyVersion}
================================================================================
''';

  static String get _icaEn => '''
================================================================================
${LegalConstants.companyName} - INDEPENDENT CONTRACTOR AGREEMENT
Version ${LegalConstants.icaVersion} | Effective Date: February 2026
================================================================================

This Independent Contractor Agreement ("Agreement") is between you ("Driver,"
"Contractor") and ${LegalConstants.companyLegalName} ("Company").

--------------------------------------------------------------------------------
1. INDEPENDENT CONTRACTOR RELATIONSHIP
--------------------------------------------------------------------------------

A. STATUS:
You are an independent contractor, NOT an employee. Nothing in this Agreement
creates an employment, agency, joint venture, partnership, or representation
relationship of any kind.

B. CONTROL:
You retain complete control over:
- When you choose to be available on the platform
- Whether to accept or decline any service request
- The manner in which you provide services
- Your work schedule and hours
- Use of other platforms or services

C. NO EXCLUSIVITY:
You are free to provide services through other platforms at any time.

D. NO AUTHORITY TO REPRESENT:
You have no authority to:
- Represent yourself as a Toro Driver employee or agent
- Bind Toro Driver to any obligation or contract
- Make promises or guarantees on behalf of Toro Driver

--------------------------------------------------------------------------------
2. SERVICE REQUIREMENTS
--------------------------------------------------------------------------------

When providing services, you agree to:
- Provide safe, professional transportation
- Follow all applicable traffic laws
- Maintain your vehicle in safe condition
- Not operate while impaired
- Treat all riders with respect
- Complete accepted trips unless safety concerns arise

--------------------------------------------------------------------------------
3. VEHICLE AND EQUIPMENT
--------------------------------------------------------------------------------

You are responsible for:
- A qualifying vehicle that meets our standards
- Valid registration and inspection
- Adequate auto insurance coverage
- Any necessary permits or licenses
- A compatible smartphone device
- All fuel, maintenance, and repair costs

--------------------------------------------------------------------------------
4. PAYMENT AND FEES
--------------------------------------------------------------------------------

A. FARE CALCULATION:
Fares are calculated by the platform based on distance, time, and service type.
The platform retains a service fee.

B. PAYMENT SCHEDULE:
Payments are processed weekly via direct deposit.

C. TAXES:
You are responsible for all applicable taxes. You will receive a 1099 form
if you earn above the IRS threshold.

--------------------------------------------------------------------------------
5. COOPERATION AND EVIDENCE PRESERVATION
--------------------------------------------------------------------------------

You agree to:
- Cooperate fully in any investigation related to incidents during trips
- Preserve evidence (photos, recordings, witness info) if requested
- Not destroy, alter, or conceal any evidence related to reported incidents
- Provide truthful statements in investigations

--------------------------------------------------------------------------------
6. TERMINATION
--------------------------------------------------------------------------------

Either party may terminate this Agreement at any time.
Toro Driver may deactivate your account immediately for safety violations,
fraudulent activity, or material breach.

--------------------------------------------------------------------------------
7. ACKNOWLEDGMENT
--------------------------------------------------------------------------------

By accepting this Agreement, you acknowledge that:
- You have read and understood all terms
- You are voluntarily entering into this Agreement
- You understand your independent contractor status
- You have no agency or apparent agency authority
- You are responsible for your own taxes and expenses

================================================================================
END OF INDEPENDENT CONTRACTOR AGREEMENT v${LegalConstants.icaVersion}
================================================================================
''';

  static String get _safetyEn => '''
================================================================================
${LegalConstants.companyName} - SAFETY POLICY AGREEMENT
Version ${LegalConstants.safetyVersion} | Effective Date: February 2026
================================================================================

--------------------------------------------------------------------------------
1. ZERO TOLERANCE POLICY
--------------------------------------------------------------------------------

Toro Driver maintains ZERO TOLERANCE for:

A. SEXUAL MISCONDUCT:
- Sexual contact, advances, comments, or behavior of ANY kind are STRICTLY
  PROHIBITED between Drivers and riders
- This includes unwanted touching, sexual comments, propositions, exposure,
  or any conduct of a sexual nature
- Immediate and permanent deactivation applies
- Reported to law enforcement when appropriate

B. SUBSTANCE IMPAIRMENT:
- No driving under the influence of alcohol or drugs
- No use of impairing substances while on active duty
- No open containers of alcohol in the vehicle

C. VIOLENCE AND HARASSMENT:
- No physical violence or threats
- No verbal abuse or intimidation
- No discrimination of any kind

D. DANGEROUS DRIVING:
- No excessive speeding
- No reckless driving
- No use of mobile devices while driving (except GPS)

VIOLATION RESULTS IN IMMEDIATE AND PERMANENT DEACTIVATION.

--------------------------------------------------------------------------------
2. CRIMINAL ACTS
--------------------------------------------------------------------------------

Any criminal act committed during or in connection with the use of the platform
will result in:
- Immediate permanent deactivation
- Full cooperation with law enforcement
- Preservation of all available evidence
- Pursuit of all available legal remedies

This includes but is not limited to: assault, theft, fraud, kidnapping,
DUI/DWI, drug offenses, and any act of violence.

--------------------------------------------------------------------------------
3. VEHICLE SAFETY REQUIREMENTS
--------------------------------------------------------------------------------

Before each shift, ensure:
- All lights functioning
- Tires properly inflated
- Brakes functioning
- Seatbelts working
- Interior clean and safe
- No hazardous materials

--------------------------------------------------------------------------------
4. INCIDENT REPORTING
--------------------------------------------------------------------------------

You must IMMEDIATELY report:
- Any accident or collision
- Threats or assaults
- Suspected criminal activity
- Vehicle breakdowns during active trips
- Any safety concerns

Report via: App emergency button, email ${LegalConstants.safetyEmail}, or call support.

Failure to report incidents may result in deactivation.

--------------------------------------------------------------------------------
5. EVIDENCE PRESERVATION
--------------------------------------------------------------------------------

Upon any incident:
- Do not delete or alter any recordings
- Preserve photos, messages, and witness information
- Cooperate fully with investigations
- Provide truthful accounts

Tampering with or destroying evidence is grounds for immediate deactivation
and may result in legal action.

--------------------------------------------------------------------------------
6. EMERGENCY PROCEDURES
--------------------------------------------------------------------------------

A. IN CASE OF ACCIDENT:
1. Stop immediately and ensure safety
2. Call 911 if injuries or significant damage
3. Exchange information with other parties
4. Document with photos
5. Report to Toro Driver immediately

B. IN CASE OF THREAT:
1. Do not escalate the situation
2. End the trip if safe to do so
3. Drive to a safe, public location
4. Call 911 if immediate danger
5. Report to Toro Driver

--------------------------------------------------------------------------------
7. ACKNOWLEDGMENT
--------------------------------------------------------------------------------

By accepting this Policy, I acknowledge that:
- I have read and understand all safety requirements
- I agree to comply with all safety policies
- I understand the consequences of violations
- I will report all incidents promptly
- I prioritize the safety of myself, passengers, and the public

================================================================================
END OF SAFETY POLICY v${LegalConstants.safetyVersion}
================================================================================
''';

  static String get _backgroundCheckEn => '''
================================================================================
${LegalConstants.companyName} - BACKGROUND CHECK CONSENT AND AUTHORIZATION
Version ${LegalConstants.backgroundCheckVersion} | Effective Date: February 2026
================================================================================

IMPORTANT: PLEASE READ THIS ENTIRE DOCUMENT CAREFULLY.

This document authorizes ${LegalConstants.companyLegalName} and its designated
background check provider to obtain consumer reports about you.

--------------------------------------------------------------------------------
1. AUTHORIZATION
--------------------------------------------------------------------------------

I authorize ${LegalConstants.companyLegalName} to obtain:
- Criminal history records (federal, state, local)
- Sex offender registry searches
- Motor vehicle records and driving history
- Identity verification
- Social Security Number verification
- Address history verification

--------------------------------------------------------------------------------
2. FCRA DISCLOSURE
--------------------------------------------------------------------------------

In accordance with the Fair Credit Reporting Act (FCRA), you are notified that
a consumer report may be obtained for employment purposes containing information
about your character, reputation, criminal history, and driving record.

--------------------------------------------------------------------------------
3. YOUR RIGHTS
--------------------------------------------------------------------------------

You have the right to:
- Request disclosure of the investigation scope
- Receive a free copy of any consumer report obtained
- Dispute the accuracy of information
- Contact the consumer reporting agency

--------------------------------------------------------------------------------
4. ONGOING AUTHORIZATION
--------------------------------------------------------------------------------

This authorization covers:
- Initial background check at application
- Periodic re-screening during engagement
- Checks following reported incidents
- Continuous monitoring of criminal and driving records

--------------------------------------------------------------------------------
5. STATE-SPECIFIC RIGHTS
--------------------------------------------------------------------------------

California residents: May request the nature and substance of all information.
New York residents: May request a copy of any report upon request.
Additional state-specific notices available upon request.

--------------------------------------------------------------------------------
6. CERTIFICATION
--------------------------------------------------------------------------------

By accepting, I certify that:
- I have read and understand this authorization
- All information I have provided is true and accurate
- I understand falsification may result in termination
- I acknowledge my rights under the FCRA

================================================================================
END OF BACKGROUND CHECK CONSENT v${LegalConstants.backgroundCheckVersion}
================================================================================
''';

  static String get _waiverEn => '''
================================================================================
${LegalConstants.companyName} - LIABILITY WAIVER AND RELEASE
Version ${LegalConstants.waiverVersion} | Effective Date: February 2026
================================================================================

PLEASE READ CAREFULLY - THIS AFFECTS YOUR LEGAL RIGHTS

--------------------------------------------------------------------------------
1. ASSUMPTION OF RISK
--------------------------------------------------------------------------------

You acknowledge that:
- Driving involves inherent risks including accidents and injuries
- You may encounter difficult or dangerous situations
- Weather, traffic, and road conditions create risks
- Interactions with riders may present risks
- You voluntarily assume all such risks

--------------------------------------------------------------------------------
2. RELEASE OF LIABILITY
--------------------------------------------------------------------------------

To the fullest extent permitted by law, you release Toro Driver from claims
arising from:
- Your use of the platform or provision of services
- Accidents, injuries, or property damage
- Interactions with riders or third parties
- Criminal acts committed by third parties
- Lost income or business opportunities

--------------------------------------------------------------------------------
3. CRIMINAL ACTS CLAUSE
--------------------------------------------------------------------------------

Toro Driver is NOT responsible for criminal acts committed by users or third
parties. This includes but is not limited to:
- Assault or battery
- Theft or robbery
- Sexual offenses
- Kidnapping or false imprisonment
- Any other criminal conduct

Driver assumes all risks related to interactions with riders and third parties.

--------------------------------------------------------------------------------
4. INDEMNIFICATION
--------------------------------------------------------------------------------

You agree to indemnify Toro Driver from any claims, damages, losses, and
expenses arising from:
- Your breach of any terms or agreements
- Your negligent or wrongful acts
- Your violation of any law or regulation
- Any claim by a third party related to your services
- Your failure to maintain adequate insurance

--------------------------------------------------------------------------------
5. LIMITATION OF DAMAGES
--------------------------------------------------------------------------------

IN NO EVENT SHALL TORO DRIVER BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL,
CONSEQUENTIAL, OR PUNITIVE DAMAGES.

--------------------------------------------------------------------------------
6. ACKNOWLEDGMENT
--------------------------------------------------------------------------------

I HAVE READ THIS WAIVER, FULLY UNDERSTAND ITS TERMS, AND ACCEPT IT
FREELY AND VOLUNTARILY. I UNDERSTAND THAT I AM GIVING UP SUBSTANTIAL RIGHTS,
INCLUDING THE RIGHT TO SUE.

================================================================================
END OF LIABILITY WAIVER v${LegalConstants.waiverVersion}
================================================================================
''';

  // ============================================================================
  // MEXICO ADDENDUM
  // ============================================================================

  static String get _mexicoAddendumEn => '''
================================================================================
${LegalConstants.companyName} - MEXICO OPERATIONS ADDENDUM
Version ${LegalConstants.mexicoAddendumVersion} | Effective Date: February 2026
================================================================================

This addendum applies to Drivers operating in Mexico and supplements the
main Terms and Conditions.

--------------------------------------------------------------------------------
1. APPLICABLE LAW
--------------------------------------------------------------------------------

Operations in Mexico are subject to:
- Ley Federal del Trabajo (LFT) - Federal Labor Law
- Ley del Servicio de Administracion Tributaria (SAT)
- Ley Federal de Proteccion al Consumidor (PROFECO)
- Applicable state and municipal regulations

--------------------------------------------------------------------------------
2. INDEPENDENT CONTRACTOR STATUS (MEXICO)
--------------------------------------------------------------------------------

In accordance with Mexican law:
- You are an independent service provider, NOT an employee
- This relationship does not create subordination (subordinacion)
- You control your schedule, routes, and methods
- You are responsible for your own fiscal obligations (SAT)
- You must issue CFDI invoices as required

--------------------------------------------------------------------------------
3. FISCAL OBLIGATIONS
--------------------------------------------------------------------------------

Mexican Drivers must:
- Register with SAT with appropriate tax regime
- Issue CFDI invoices for services rendered
- Comply with ISR and IVA obligations
- Maintain RFC documentation
- File tax declarations as required

--------------------------------------------------------------------------------
4. SAFETY AND SECURITY (MEXICO)
--------------------------------------------------------------------------------

Additional safety requirements for Mexico:
- Comply with local transit regulations
- Maintain required vehicle documentation (tarjeta de circulacion)
- Report incidents to appropriate local authorities
- Cooperate with state/federal investigations
- Maintain IMSS or private insurance coverage

--------------------------------------------------------------------------------
5. RECORDING AND CONSENT (MEXICO)
--------------------------------------------------------------------------------

Audio/video recording during trips in Mexico:
- Subject to applicable federal and state privacy laws
- Riders are notified of recording capability
- Recordings used only for safety and legal purposes

--------------------------------------------------------------------------------
6. INCIDENT REPORTING (MEXICO)
--------------------------------------------------------------------------------

In Mexico, you must also:
- Report accidents to local transit authorities
- Cooperate with Ministerio Publico if required
- Preserve evidence as required by Mexican law
- Report incidents involving firearms or violence to authorities

================================================================================
END OF MEXICO ADDENDUM v${LegalConstants.mexicoAddendumVersion}
================================================================================
''';

  // ============================================================================
  // SPANISH DOCUMENTS v2.0
  // ============================================================================

  static String get _termsEs => '''
================================================================================
${LegalConstants.companyName} - TERMINOS Y CONDICIONES DEL SERVICIO
Version ${LegalConstants.termsVersion} | Fecha Efectiva: Febrero 2026
Entidad: ${LegalConstants.companyLegalName} | Jurisdiccion: ${LegalConstants.companyJurisdiction}
================================================================================

POR FAVOR LEA ESTOS TERMINOS CUIDADOSAMENTE ANTES DE USAR TORO DRIVER.

Al acceder o usar la aplicacion Toro Driver ("App"), usted acepta estar sujeto
a estos Terminos y Condiciones ("Terminos"). Si no esta de acuerdo, no use la App.

--------------------------------------------------------------------------------
1. ACEPTACION DE TERMINOS
--------------------------------------------------------------------------------

Al crear una cuenta o usar Toro Driver, usted reconoce que ha leido, entendido
y acepta estos Terminos, la Politica de Privacidad, el Acuerdo de Contratista
Independiente, la Politica de Seguridad, la Exoneracion de Responsabilidad,
y todas las leyes aplicables.

--------------------------------------------------------------------------------
2. DESCRIPCION DEL SERVICIO
--------------------------------------------------------------------------------

Toro Driver es una plataforma tecnologica que facilita conexiones entre
proveedores de servicios independientes ("Conductores") y usuarios que buscan
servicios de transporte o entrega.

ACLARACIONES IMPORTANTES:

- Toro Driver NO es un proveedor de transporte, transportista, empresa de taxis,
  servicio de chofer u operador logistico.
- Toro Driver NO posee, alquila, despacha ni controla vehiculos.
- Toro Driver NO emplea a los Conductores.
- Los Conductores actuan unicamente como proveedores independientes.
- Toro Driver NO controla como los Conductores realizan servicios, seleccionan
  rutas, operan vehiculos o interactuan con pasajeros, excepto reglas minimas
  de la plataforma.
- Nada en este Acuerdo crea empleo, agencia, agencia aparente, sociedad,
  empresa conjunta o representacion de ningun tipo.

Todos los servicios son proporcionados exclusivamente por los Conductores.

--------------------------------------------------------------------------------
2.1 NO AGENCIA / NO AGENCIA APARENTE
--------------------------------------------------------------------------------

Los Conductores NO son agentes, empleados ni representantes de Toro Driver.

Los Conductores NO estan autorizados a:
- Representarse como empleados o agentes de Toro Driver
- Usar frases como "Trabajo para Toro" o "Empleado de Toro Driver"
- Vincular a Toro Driver con obligaciones
- Hacer garantias o promesas en nombre de Toro Driver

Los usuarios reconocen que Toro Driver solo proporciona software y herramientas
de seguridad.

--------------------------------------------------------------------------------
2.2 NO GARANTIA DE SEGURIDAD
--------------------------------------------------------------------------------

Toro Driver puede ofrecer funciones de seguridad como verificacion de identidad,
compartir viaje, botones SOS, o grabacion opcional de audio/video.

ESTAS FUNCIONES REDUCEN EL RIESGO PERO NO GARANTIZAN LA SEGURIDAD.

Toro Driver no garantiza que incidentes, crimenes, accidentes, acoso, agresiones
o conducta indebida no ocurriran.

--------------------------------------------------------------------------------
3. REQUISITOS DE ELEGIBILIDAD
--------------------------------------------------------------------------------

Para usar Toro Driver, debe:
- Tener al menos 21 anos de edad
- Poseer licencia de conducir valida (min. 1 ano)
- Pasar verificaciones de antecedentes y registro de manejo
- Mantener seguro valido
- Tener autorizacion legal para trabajar
- Proporcionar informacion precisa

--------------------------------------------------------------------------------
4. RESPONSABILIDADES DEL CONDUCTOR
--------------------------------------------------------------------------------

Los Conductores aceptan:
- Operar de manera segura y legal
- Mantener la seguridad del vehiculo
- Tratar a los pasajeros con respeto
- Rechazar viajes si no es seguro
- Nunca operar bajo efectos de sustancias
- Reportar incidentes inmediatamente

--------------------------------------------------------------------------------
5. ESTATUS DE CONTRATISTA INDEPENDIENTE
--------------------------------------------------------------------------------

Los Conductores reconocen:
- Su estatus de contratista independiente
- Libertad para aceptar o rechazar viajes
- Sin exclusividad
- Responsabilidad por sus impuestos
- Sin beneficios de empleado
- Sin relacion de agencia o agencia aparente

--------------------------------------------------------------------------------
6. TERMINOS DE PAGO
--------------------------------------------------------------------------------

- Las tarifas se calculan por distancia, tiempo y tipo de servicio
- Toro Driver retiene una comision de plataforma
- Los pagos se emiten semanalmente
- Las propinas pertenecen 100% a los Conductores
- Las disputas deben presentarse dentro de 30 dias

--------------------------------------------------------------------------------
7. REQUISITOS DE VEHICULO Y SEGURO
--------------------------------------------------------------------------------

Los Conductores deben mantener:
- Vehiculo que cumpla requisitos
- Registro valido
- Seguro requerido
- Cobertura comercial si la ley lo requiere

--------------------------------------------------------------------------------
8. SEGURIDAD Y TOLERANCIA CERO
--------------------------------------------------------------------------------

TOLERANCIA CERO para:
- Conducta sexual inapropiada de cualquier tipo
- Acoso o intimidacion
- Violencia o amenazas
- Discriminacion
- Conducir bajo efectos de sustancias

Las violaciones resultan en desactivacion inmediata y posible reporte a autoridades.

--------------------------------------------------------------------------------
9. REPORTE DE INCIDENTES Y PRESERVACION DE EVIDENCIA
--------------------------------------------------------------------------------

Los Conductores deben reportar inmediatamente:
- Accidentes o colisiones
- Amenazas o agresiones
- Comportamiento sospechoso
- Preocupaciones de seguridad

Toro Driver puede preservar:
- Datos GPS y telemetria del viaje
- Grabaciones de audio/video (si estan habilitadas)
- Registros de chat y comunicaciones
- Datos de eventos de seguridad

La evidencia se preserva para procedimientos legales y cumplimiento regulatorio.

--------------------------------------------------------------------------------
10. LIMITACION DE RESPONSABILIDAD
--------------------------------------------------------------------------------

En la maxima medida permitida por la ley:
- Toro Driver no es responsable por actos de Conductores o pasajeros
- No hay responsabilidad por actos criminales de terceros
- La responsabilidad total esta limitada a las comisiones pagadas en los
  ultimos 3 meses o USD \$100, lo que sea menor

--------------------------------------------------------------------------------
11. INDEMNIZACION
--------------------------------------------------------------------------------

Los Conductores aceptan indemnizar y mantener indemne a Toro Driver de
cualquier reclamo derivado de su conducta, violaciones o negligencia.

--------------------------------------------------------------------------------
12. RESOLUCION DE DISPUTAS Y ARBITRAJE
--------------------------------------------------------------------------------

- Se requiere arbitraje individual vinculante
- No se permiten acciones colectivas
- Puede optar por no participar dentro de 30 dias del registro

--------------------------------------------------------------------------------
13. LEY APLICABLE
--------------------------------------------------------------------------------

Ley aplicable: Estado de California, EE.UU.

--------------------------------------------------------------------------------
14. CONTACTO
--------------------------------------------------------------------------------

Legal: ${LegalConstants.companyEmail}
Soporte al Conductor: ${LegalConstants.supportEmail}

================================================================================
FIN DE TERMINOS Y CONDICIONES v${LegalConstants.termsVersion}
================================================================================
''';

  static String get _privacyEs => '''
================================================================================
${LegalConstants.companyName} - POLITICA DE PRIVACIDAD
Version ${LegalConstants.privacyVersion} | Fecha Efectiva: Febrero 2026
================================================================================

Toro Driver recopila datos estrictamente para operar la plataforma, garantizar
la seguridad, cumplir con la ley y defender reclamaciones legales.

--------------------------------------------------------------------------------
1. INFORMACION QUE RECOPILAMOS
--------------------------------------------------------------------------------

A. INFORMACION QUE USTED PROPORCIONA:
- Informacion de cuenta (nombre, correo, telefono, direccion)
- Documentos de identidad (licencia de conducir, identificacion con foto)
- Informacion del vehiculo (marca, modelo, ano, registro, seguro)
- Informacion de pago (cuenta bancaria para depositos)
- Consentimiento e informacion para verificacion de antecedentes
- Foto de perfil

B. INFORMACION RECOPILADA AUTOMATICAMENTE:
- Datos de ubicacion (rastreo GPS durante viajes activos)
- Datos del viaje (rutas, duracion, distancia)
- Informacion del dispositivo (modelo, SO, identificadores unicos)
- Datos de uso de la aplicacion
- Grabaciones opcionales de audio/video (si estan habilitadas)
- Eventos de seguridad y activaciones SOS

C. INFORMACION DE TERCEROS:
- Resultados de verificacion de antecedentes
- Informacion de registro de manejo
- Verificacion de seguro
- Resultados de verificacion de identidad

--------------------------------------------------------------------------------
2. COMO USAMOS SU INFORMACION
--------------------------------------------------------------------------------

Usamos su informacion para:
- Verificar su identidad y elegibilidad
- Conectarlo con pasajeros
- Procesar pagos y documentacion fiscal
- Garantizar la seguridad de la plataforma
- Mejorar nuestros servicios
- Comunicar actualizaciones importantes
- Cumplir con requisitos legales y regulatorios
- Investigar incidentes y resolver disputas
- Preservar evidencia cuando la ley lo requiera

--------------------------------------------------------------------------------
3. DATOS DE UBICACION
--------------------------------------------------------------------------------

Recopilamos datos de ubicacion precisos para:
- Conectarlo con solicitudes de viaje cercanas
- Proporcionar navegacion y rutas
- Calcular tarifas precisas
- Garantizar la seguridad del pasajero
- Investigar incidentes y disputas

La ubicacion se rastrea cuando esta en linea/disponible.
Puede desconectarse para detener el rastreo.

--------------------------------------------------------------------------------
4. GRABACION Y EVIDENCIA
--------------------------------------------------------------------------------

Si las funciones de grabacion de audio/video estan habilitadas:
- Las grabaciones se almacenan con fines de seguridad
- La evidencia se preserva cuando se reporta un incidente
- Se aplica retencion legal cuando lo requiere la ley
- Las grabaciones se cifran en reposo y en transito
- Se respetan los requisitos de consentimiento de dos partes por estado

--------------------------------------------------------------------------------
5. COMPARTIR DATOS
--------------------------------------------------------------------------------

Podemos compartir su informacion con:
- Pasajeros (nombre, foto, info del vehiculo, ubicacion en tiempo real)
- Proveedores de verificacion de antecedentes
- Procesadores de pagos
- Autoridades legales (ante solicitud legal valida)
- Asesores legales (para defensa de reclamaciones)

NO VENDEMOS SU INFORMACION PERSONAL.

--------------------------------------------------------------------------------
6. RETENCION DE DATOS
--------------------------------------------------------------------------------

- Cuentas activas: Mientras permanezca activo
- Registros de viajes: 7 anos para cumplimiento fiscal y legal
- Evidencia de seguridad: Preservada si se reporta incidente
- Despues de desactivacion: 90 dias, luego anonimizada/eliminada
- Datos de verificacion de antecedentes: Segun lo requiera la ley

--------------------------------------------------------------------------------
7. SUS DERECHOS
--------------------------------------------------------------------------------

Usted tiene derecho a:
- ACCESO: Solicitar una copia de sus datos personales
- CORRECCION: Actualizar informacion inexacta
- ELIMINACION: Solicitar eliminacion de su cuenta y datos
- EXCLUSION: Controlar comunicaciones de marketing
- PORTABILIDAD: Recibir sus datos en formato portable

Contacto: ${LegalConstants.privacyEmail}

--------------------------------------------------------------------------------
8. DERECHOS DE PRIVACIDAD DE CALIFORNIA (CCPA)
--------------------------------------------------------------------------------

Los residentes de California tienen derechos adicionales:
- Derecho a saber que informacion personal se recopila
- Derecho a eliminar informacion personal
- Derecho a optar por no vender informacion personal
- Derecho a no discriminacion por ejercer derechos de privacidad

--------------------------------------------------------------------------------
9. CONTACTO
--------------------------------------------------------------------------------

Privacidad: ${LegalConstants.privacyEmail}
Soporte: ${LegalConstants.supportEmail}

================================================================================
FIN DE POLITICA DE PRIVACIDAD v${LegalConstants.privacyVersion}
================================================================================
''';

  static String get _icaEs => '''
================================================================================
${LegalConstants.companyName} - ACUERDO DE CONTRATISTA INDEPENDIENTE
Version ${LegalConstants.icaVersion} | Fecha Efectiva: Febrero 2026
================================================================================

Este Acuerdo de Contratista Independiente ("Acuerdo") es entre usted
("Conductor", "Contratista") y ${LegalConstants.companyLegalName} ("Empresa").

--------------------------------------------------------------------------------
1. RELACION DE CONTRATISTA INDEPENDIENTE
--------------------------------------------------------------------------------

A. ESTATUS:
Usted es un contratista independiente, NO un empleado. Nada en este Acuerdo
crea una relacion de empleo, agencia, empresa conjunta, sociedad o
representacion de ningun tipo.

B. CONTROL:
Usted mantiene control completo sobre:
- Cuando elige estar disponible en la plataforma
- Si acepta o rechaza cualquier solicitud de servicio
- La manera en que proporciona servicios
- Su horario de trabajo
- Uso de otras plataformas o servicios

C. SIN EXCLUSIVIDAD:
Es libre de proporcionar servicios a traves de otras plataformas en cualquier
momento.

D. SIN AUTORIDAD PARA REPRESENTAR:
No tiene autoridad para:
- Representarse como empleado o agente de Toro Driver
- Vincular a Toro Driver con ninguna obligacion o contrato
- Hacer promesas o garantias en nombre de Toro Driver

--------------------------------------------------------------------------------
2. REQUISITOS DE SERVICIO
--------------------------------------------------------------------------------

Al proporcionar servicios, usted acepta:
- Proporcionar transporte seguro y profesional
- Seguir todas las leyes de transito aplicables
- Mantener su vehiculo en condiciones seguras
- No operar bajo efectos de sustancias
- Tratar a todos los pasajeros con respeto
- Completar viajes aceptados salvo preocupaciones de seguridad

--------------------------------------------------------------------------------
3. VEHICULO Y EQUIPO
--------------------------------------------------------------------------------

Usted es responsable de:
- Un vehiculo que cumpla nuestros estandares
- Registro e inspeccion validos
- Cobertura adecuada de seguro automotriz
- Permisos o licencias necesarios
- Un dispositivo movil compatible
- Todos los costos de combustible, mantenimiento y reparacion

--------------------------------------------------------------------------------
4. PAGO Y COMISIONES
--------------------------------------------------------------------------------

A. CALCULO DE TARIFAS:
Las tarifas son calculadas por la plataforma basadas en distancia, tiempo y
tipo de servicio. La plataforma retiene una comision de servicio.

B. CALENDARIO DE PAGOS:
Los pagos se procesan semanalmente mediante deposito directo.

C. IMPUESTOS:
Usted es responsable de todos los impuestos aplicables. Recibira un formulario
1099 si sus ingresos superan el umbral del IRS.

--------------------------------------------------------------------------------
5. COOPERACION Y PRESERVACION DE EVIDENCIA
--------------------------------------------------------------------------------

Usted acepta:
- Cooperar plenamente en cualquier investigacion relacionada con incidentes
- Preservar evidencia (fotos, grabaciones, informacion de testigos) si se solicita
- No destruir, alterar ni ocultar evidencia relacionada con incidentes reportados
- Proporcionar declaraciones veraces en investigaciones

--------------------------------------------------------------------------------
6. TERMINACION
--------------------------------------------------------------------------------

Cualquiera de las partes puede terminar este Acuerdo en cualquier momento.
Toro Driver puede desactivar su cuenta inmediatamente por violaciones de
seguridad, actividad fraudulenta o incumplimiento material.

--------------------------------------------------------------------------------
7. RECONOCIMIENTO
--------------------------------------------------------------------------------

Al aceptar este Acuerdo, usted reconoce que:
- Ha leido y entendido todos los terminos
- Entra voluntariamente en este Acuerdo
- Entiende su estatus de contratista independiente
- No tiene autoridad de agencia o agencia aparente
- Es responsable de sus propios impuestos y gastos

================================================================================
FIN DEL ACUERDO DE CONTRATISTA INDEPENDIENTE v${LegalConstants.icaVersion}
================================================================================
''';

  static String get _safetyEs => '''
================================================================================
${LegalConstants.companyName} - ACUERDO DE POLITICA DE SEGURIDAD
Version ${LegalConstants.safetyVersion} | Fecha Efectiva: Febrero 2026
================================================================================

--------------------------------------------------------------------------------
1. POLITICA DE TOLERANCIA CERO
--------------------------------------------------------------------------------

Toro Driver mantiene TOLERANCIA CERO para:

A. CONDUCTA SEXUAL INAPROPIADA:
- Contacto sexual, insinuaciones, comentarios o comportamiento de CUALQUIER
  tipo estan ESTRICTAMENTE PROHIBIDOS entre Conductores y pasajeros
- Esto incluye tocamientos no deseados, comentarios sexuales, proposiciones,
  exhibicionismo o cualquier conducta de naturaleza sexual
- Se aplica desactivacion inmediata y permanente
- Se reporta a las autoridades cuando corresponda

B. CONDUCIR BAJO EFECTOS DE SUSTANCIAS:
- No conducir bajo la influencia de alcohol o drogas
- No usar sustancias que deterioren la capacidad durante servicio activo
- No tener recipientes abiertos de alcohol en el vehiculo

C. VIOLENCIA Y ACOSO:
- No violencia fisica ni amenazas
- No abuso verbal ni intimidacion
- No discriminacion de ningun tipo

D. CONDUCCION PELIGROSA:
- No exceso de velocidad
- No conduccion temeraria
- No uso de dispositivos moviles mientras conduce (excepto GPS)

LA VIOLACION RESULTA EN DESACTIVACION INMEDIATA Y PERMANENTE.

--------------------------------------------------------------------------------
2. ACTOS CRIMINALES
--------------------------------------------------------------------------------

Cualquier acto criminal cometido durante o en conexion con el uso de la
plataforma resultara en:
- Desactivacion permanente inmediata
- Cooperacion total con las autoridades
- Preservacion de toda la evidencia disponible
- Busqueda de todos los recursos legales disponibles

Esto incluye pero no se limita a: agresion, robo, fraude, secuestro,
DUI/DWI, delitos de drogas y cualquier acto de violencia.

--------------------------------------------------------------------------------
3. REQUISITOS DE SEGURIDAD DEL VEHICULO
--------------------------------------------------------------------------------

Antes de cada turno, asegurese de:
- Todas las luces funcionando
- Llantas correctamente infladas
- Frenos funcionando
- Cinturones de seguridad operativos
- Interior limpio y seguro
- Sin materiales peligrosos

--------------------------------------------------------------------------------
4. REPORTE DE INCIDENTES
--------------------------------------------------------------------------------

Debe reportar INMEDIATAMENTE:
- Cualquier accidente o colision
- Amenazas o agresiones
- Actividad criminal sospechosa
- Descomposturas del vehiculo durante viajes activos
- Cualquier preocupacion de seguridad

Reporte via: Boton de emergencia en la app, correo ${LegalConstants.safetyEmail},
o llamada a soporte.

No reportar incidentes puede resultar en desactivacion.

--------------------------------------------------------------------------------
5. PRESERVACION DE EVIDENCIA
--------------------------------------------------------------------------------

Ante cualquier incidente:
- No elimine ni altere grabaciones
- Preserve fotos, mensajes e informacion de testigos
- Coopere plenamente con investigaciones
- Proporcione relatos veraces

Manipular o destruir evidencia es motivo de desactivacion inmediata y
puede resultar en accion legal.

--------------------------------------------------------------------------------
6. PROCEDIMIENTOS DE EMERGENCIA
--------------------------------------------------------------------------------

A. EN CASO DE ACCIDENTE:
1. Detengase inmediatamente y asegure la seguridad
2. Llame al 911 si hay lesiones o danos significativos
3. Intercambie informacion con las otras partes
4. Documente con fotos
5. Reporte a Toro Driver inmediatamente

B. EN CASO DE AMENAZA:
1. No escale la situacion
2. Termine el viaje si es seguro hacerlo
3. Conduzca a un lugar seguro y publico
4. Llame al 911 si hay peligro inmediato
5. Reporte a Toro Driver

--------------------------------------------------------------------------------
7. RECONOCIMIENTO
--------------------------------------------------------------------------------

Al aceptar esta Politica, reconozco que:
- He leido y entiendo todos los requisitos de seguridad
- Acepto cumplir con todas las politicas de seguridad
- Entiendo las consecuencias de las violaciones
- Reportare todos los incidentes con prontitud
- Priorizo la seguridad propia, de los pasajeros y del publico

================================================================================
FIN DE LA POLITICA DE SEGURIDAD v${LegalConstants.safetyVersion}
================================================================================
''';

  static String get _backgroundCheckEs => '''
================================================================================
${LegalConstants.companyName} - CONSENTIMIENTO Y AUTORIZACION DE VERIFICACION DE ANTECEDENTES
Version ${LegalConstants.backgroundCheckVersion} | Fecha Efectiva: Febrero 2026
================================================================================

IMPORTANTE: POR FAVOR LEA ESTE DOCUMENTO COMPLETO CUIDADOSAMENTE.

Este documento autoriza a ${LegalConstants.companyLegalName} y su proveedor
designado de verificacion de antecedentes a obtener reportes de consumidor
sobre usted.

--------------------------------------------------------------------------------
1. AUTORIZACION
--------------------------------------------------------------------------------

Autorizo a ${LegalConstants.companyLegalName} a obtener:
- Registros de historial criminal (federal, estatal, local)
- Busquedas en registros de delincuentes sexuales
- Registros vehiculares e historial de manejo
- Verificacion de identidad
- Verificacion de Numero de Seguro Social
- Verificacion de historial de direcciones

--------------------------------------------------------------------------------
2. DIVULGACION FCRA
--------------------------------------------------------------------------------

De acuerdo con la Ley de Reportes de Credito Justos (FCRA), se le notifica que
un reporte de consumidor puede ser obtenido para fines de empleo que contenga
informacion sobre su caracter, reputacion, historial criminal y registro de manejo.

--------------------------------------------------------------------------------
3. SUS DERECHOS
--------------------------------------------------------------------------------

Usted tiene derecho a:
- Solicitar divulgacion del alcance de la investigacion
- Recibir una copia gratuita de cualquier reporte obtenido
- Disputar la precision de la informacion
- Contactar a la agencia de reportes de consumidor

--------------------------------------------------------------------------------
4. AUTORIZACION CONTINUA
--------------------------------------------------------------------------------

Esta autorizacion cubre:
- Verificacion inicial de antecedentes al aplicar
- Re-verificaciones periodicas durante el compromiso
- Verificaciones posteriores a incidentes reportados
- Monitoreo continuo de registros criminales y de manejo

--------------------------------------------------------------------------------
5. DERECHOS ESPECIFICOS POR ESTADO
--------------------------------------------------------------------------------

Residentes de California: Pueden solicitar la naturaleza y sustancia de toda
la informacion. Residentes de Nueva York: Pueden solicitar copia de cualquier
reporte. Avisos adicionales especificos por estado disponibles bajo solicitud.

--------------------------------------------------------------------------------
6. CERTIFICACION
--------------------------------------------------------------------------------

Al aceptar, certifico que:
- He leido y entiendo esta autorizacion
- Toda la informacion que he proporcionado es verdadera y precisa
- Entiendo que la falsificacion puede resultar en terminacion
- Reconozco mis derechos bajo la FCRA

================================================================================
FIN DEL CONSENTIMIENTO DE VERIFICACION DE ANTECEDENTES v${LegalConstants.backgroundCheckVersion}
================================================================================
''';

  static String get _waiverEs => '''
================================================================================
${LegalConstants.companyName} - EXONERACION Y LIBERACION DE RESPONSABILIDAD
Version ${LegalConstants.waiverVersion} | Fecha Efectiva: Febrero 2026
================================================================================

POR FAVOR LEA CUIDADOSAMENTE - ESTO AFECTA SUS DERECHOS LEGALES

--------------------------------------------------------------------------------
1. ASUNCION DE RIESGO
--------------------------------------------------------------------------------

Usted reconoce que:
- Conducir implica riesgos inherentes incluyendo accidentes y lesiones
- Puede encontrar situaciones dificiles o peligrosas
- El clima, el trafico y las condiciones del camino crean riesgos
- Las interacciones con pasajeros pueden presentar riesgos
- Asume voluntariamente todos estos riesgos

--------------------------------------------------------------------------------
2. LIBERACION DE RESPONSABILIDAD
--------------------------------------------------------------------------------

En la maxima medida permitida por la ley, usted libera a Toro Driver de
reclamaciones derivadas de:
- Su uso de la plataforma o prestacion de servicios
- Accidentes, lesiones o danos a la propiedad
- Interacciones con pasajeros o terceros
- Actos criminales cometidos por terceros
- Perdida de ingresos u oportunidades de negocio

--------------------------------------------------------------------------------
3. CLAUSULA DE ACTOS CRIMINALES
--------------------------------------------------------------------------------

Toro Driver NO es responsable por actos criminales cometidos por usuarios o
terceros. Esto incluye pero no se limita a:
- Agresion o lesiones
- Robo o asalto
- Delitos sexuales
- Secuestro o privacion ilegal de la libertad
- Cualquier otra conducta criminal

El Conductor asume todos los riesgos relacionados con interacciones con
pasajeros y terceros.

--------------------------------------------------------------------------------
4. INDEMNIZACION
--------------------------------------------------------------------------------

Usted acepta indemnizar a Toro Driver de cualquier reclamacion, dano, perdida
y gasto derivado de:
- Su incumplimiento de cualquier termino o acuerdo
- Sus actos negligentes o ilicitos
- Su violacion de cualquier ley o regulacion
- Cualquier reclamacion de terceros relacionada con sus servicios
- Su falta de mantener seguro adecuado

--------------------------------------------------------------------------------
5. LIMITACION DE DANOS
--------------------------------------------------------------------------------

EN NINGUN CASO TORO DRIVER SERA RESPONSABLE POR DANOS INDIRECTOS, INCIDENTALES,
ESPECIALES, CONSECUENTES O PUNITIVOS.

--------------------------------------------------------------------------------
6. RECONOCIMIENTO
--------------------------------------------------------------------------------

HE LEIDO ESTA EXONERACION, ENTIENDO COMPLETAMENTE SUS TERMINOS Y LA ACEPTO
LIBRE Y VOLUNTARIAMENTE. ENTIENDO QUE ESTOY RENUNCIANDO A DERECHOS
SUSTANCIALES, INCLUYENDO EL DERECHO A DEMANDAR.

================================================================================
FIN DE LA EXONERACION DE RESPONSABILIDAD v${LegalConstants.waiverVersion}
================================================================================
''';

  static String get _mexicoAddendumEs => '''
================================================================================
${LegalConstants.companyName} - ADENDA DE OPERACIONES EN MEXICO
Version ${LegalConstants.mexicoAddendumVersion} | Fecha Efectiva: Febrero 2026
================================================================================

Esta adenda aplica a Conductores que operan en Mexico y complementa los
Terminos y Condiciones principales.

--------------------------------------------------------------------------------
1. LEY APLICABLE
--------------------------------------------------------------------------------

Las operaciones en Mexico estan sujetas a:
- Ley Federal del Trabajo (LFT)
- Ley del Servicio de Administracion Tributaria (SAT)
- Ley Federal de Proteccion al Consumidor (PROFECO)
- Regulaciones estatales y municipales aplicables

--------------------------------------------------------------------------------
2. ESTATUS DE CONTRATISTA INDEPENDIENTE (MEXICO)
--------------------------------------------------------------------------------

De acuerdo con la ley mexicana:
- Usted es un prestador de servicios independiente, NO un empleado
- Esta relacion no crea subordinacion
- Usted controla su horario, rutas y metodos
- Es responsable de sus obligaciones fiscales (SAT)
- Debe emitir facturas CFDI segun se requiera

--------------------------------------------------------------------------------
3. OBLIGACIONES FISCALES
--------------------------------------------------------------------------------

Los Conductores en Mexico deben:
- Registrarse ante el SAT con el regimen fiscal apropiado
- Emitir facturas CFDI por servicios prestados
- Cumplir con obligaciones de ISR e IVA
- Mantener documentacion de RFC
- Presentar declaraciones fiscales segun se requiera

--------------------------------------------------------------------------------
4. SEGURIDAD (MEXICO)
--------------------------------------------------------------------------------

Requisitos adicionales de seguridad para Mexico:
- Cumplir con regulaciones locales de transito
- Mantener documentacion vehicular requerida (tarjeta de circulacion)
- Reportar incidentes a las autoridades locales correspondientes
- Cooperar con investigaciones estatales/federales
- Mantener cobertura de IMSS o seguro privado

--------------------------------------------------------------------------------
5. GRABACION Y CONSENTIMIENTO (MEXICO)
--------------------------------------------------------------------------------

Grabacion de audio/video durante viajes en Mexico:
- Sujeta a las leyes federales y estatales de privacidad aplicables
- Los pasajeros son notificados de la capacidad de grabacion
- Las grabaciones se usan solo para fines de seguridad y legales

--------------------------------------------------------------------------------
6. REPORTE DE INCIDENTES (MEXICO)
--------------------------------------------------------------------------------

En Mexico, tambien debe:
- Reportar accidentes a las autoridades de transito locales
- Cooperar con el Ministerio Publico si se requiere
- Preservar evidencia segun lo requiera la ley mexicana
- Reportar incidentes con armas de fuego o violencia a las autoridades

================================================================================
FIN DE LA ADENDA DE MEXICO v${LegalConstants.mexicoAddendumVersion}
================================================================================
''';

  // ============================================================================
  // ORGANIZER PLATFORM AGREEMENT - ENGLISH
  // ============================================================================

  static String get _organizerAgreementEn => '''
================================================================================
ORGANIZER PLATFORM AGREEMENT v${LegalConstants.organizerAgreementVersion}
${LegalConstants.companyLegalName}
Effective Date: ${DateTime.now().toString().split(' ')[0]}
================================================================================

1. DEFINITIONS AND PARTIES

This Organizer Platform Agreement ("Agreement") is entered into between:

- ${LegalConstants.companyLegalName}, a company organized under the laws of the
  ${LegalConstants.companyJurisdiction} ("TORO", "Company", "Platform", "we", "us")

- You, the individual or entity registering as an event organizer on the TORO
  platform ("Organizer", "you", "your")

"Platform" refers to the TORO mobile application and related services.
"Event" refers to any transportation event, trip, tour, or route you create.
"Vehicle Provider" refers to drivers or vehicle owners who bid on your events.
"Commission" refers to the percentage fee charged by TORO on transactions.

--------------------------------------------------------------------------------

2. SCOPE OF THE PLATFORM

2.1 TORO operates as a technology marketplace that connects event organizers
    with vehicle providers. TORO does NOT:
    - Own, operate, or control any vehicles
    - Employ or manage vehicle providers
    - Guarantee the availability of vehicles
    - Provide transportation services directly

2.2 TORO provides:
    - A digital platform to create and publish transportation events
    - A bidding system for vehicle providers to offer their services
    - Payment processing and invoicing tools
    - Communication channels between organizers and providers
    - Real-time GPS tracking during active events

2.3 You acknowledge that TORO acts solely as an intermediary. The transportation
    contract is between you (Organizer) and the Vehicle Provider.

--------------------------------------------------------------------------------

3. ORGANIZER OBLIGATIONS

3.1 ACCURATE INFORMATION: You agree to provide truthful and accurate information
    for all events, including but not limited to:
    - Event dates, times, and locations
    - Number of passengers or seats required
    - Itinerary and route details
    - Any special requirements or restrictions

3.2 LEGAL COMPLIANCE: You are solely responsible for:
    - Obtaining all necessary permits, licenses, and authorizations for your events
    - Complying with local, state, and federal transportation regulations
    - Ensuring your events comply with all applicable laws
    - Obtaining appropriate insurance for your events if required by law

3.3 PASSENGER SAFETY: You agree to:
    - Not organize events involving illegal activities
    - Inform passengers of safety requirements
    - Provide accurate information about pickup/dropoff locations
    - Cooperate with vehicle providers on safety matters

3.4 PROHIBITED ACTIVITIES: You may NOT use the platform to:
    - Organize events for the transport of illegal goods or substances
    - Discriminate against passengers based on race, religion, gender,
      sexual orientation, disability, or national origin
    - Engage in fraudulent or deceptive practices
    - Circumvent the platform to avoid commission fees
    - Share your account credentials with third parties

--------------------------------------------------------------------------------

4. COMMISSIONS AND PAYMENTS

4.1 SERVICE FEE: TORO charges a commission of 18% (eighteen percent) on the
    total transaction amount for each completed event. This commission is
    automatically deducted before funds are transferred to the Vehicle Provider.

4.2 TRIAL PERIOD: The current commission rate may be subject to change. TORO
    reserves the right to modify the commission rate with 30 days written notice.

4.3 PAYMENT PROCESSING: All payments are processed through the TORO platform.
    Direct payments between organizers and vehicle providers that bypass the
    platform are strictly prohibited and may result in account termination.

4.4 REFUNDS AND CANCELLATIONS: Refund and cancellation policies are established
    per event. TORO may retain a portion of the commission for processing
    cancelled events, as described in the cancellation policy.

4.5 TAX RESPONSIBILITY: You are solely responsible for:
    - Reporting all income earned through the platform to relevant tax authorities
    - Paying all applicable federal, state, and local taxes
    - Issuing any required tax documents to passengers (if applicable)
    - Complying with sales tax, VAT, or other transaction tax requirements
    TORO does not provide tax advice and is not responsible for your tax obligations.

--------------------------------------------------------------------------------

5. INTELLECTUAL PROPERTY

5.1 The TORO name, logo, trademarks, and all platform content are the exclusive
    property of ${LegalConstants.companyLegalName}.

5.2 You are granted a limited, non-exclusive, non-transferable license to use
    the TORO platform for organizing transportation events.

5.3 You may not use the TORO brand in any external marketing, advertising, or
    promotional materials without prior written consent.

5.4 Any content you upload to the platform (event descriptions, images, logos)
    remains your property, but you grant TORO a non-exclusive license to
    display such content within the platform.

--------------------------------------------------------------------------------

6. PRIVACY AND DATA

6.1 TORO collects and processes personal data as described in our Privacy Policy.

6.2 Data collected from organizers may include:
    - Name, email, phone number, company information
    - Event creation and management history
    - Financial transaction records
    - Device information and IP addresses
    - GPS location data (with your consent)

6.3 We comply with applicable data protection laws including CCPA (California),
    and applicable Mexican data protection regulations (LFPDPPP).

6.4 You agree not to misuse personal data of passengers or vehicle providers
    obtained through the platform.

--------------------------------------------------------------------------------

7. LIMITATION OF LIABILITY

7.1 TORO IS A TECHNOLOGY MARKETPLACE, NOT A TRANSPORTATION PROVIDER.

7.2 TO THE MAXIMUM EXTENT PERMITTED BY LAW, TORO SHALL NOT BE LIABLE FOR:
    - Accidents, injuries, or property damage during transportation events
    - Acts, omissions, or negligence of vehicle providers
    - Delays, cancellations, or service interruptions by vehicle providers
    - Loss of revenue or business opportunities
    - Any indirect, incidental, special, or consequential damages

7.3 TORO's total liability for any claim arising from this Agreement shall not
    exceed the total commissions paid by or on behalf of you in the twelve (12)
    months preceding the claim.

7.4 THE PLATFORM IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF
    ANY KIND, EXPRESS OR IMPLIED.

--------------------------------------------------------------------------------

8. INDEMNIFICATION

8.1 You agree to indemnify, defend, and hold harmless ${LegalConstants.companyLegalName},
    its officers, directors, employees, agents, and affiliates from and against
    any and all claims, damages, losses, liabilities, costs, and expenses
    (including reasonable attorneys' fees) arising out of or related to:

    a) Your use of the platform
    b) Events you organize through the platform
    c) Your breach of this Agreement
    d) Your violation of any applicable law or regulation
    e) Any claim by a passenger, vehicle provider, or third party related to
       your events

--------------------------------------------------------------------------------

9. DISPUTE RESOLUTION

9.1 ARBITRATION: Any dispute arising from this Agreement shall be resolved
    through binding arbitration administered by the American Arbitration
    Association (AAA) under its Commercial Arbitration Rules.

9.2 CLASS ACTION WAIVER: You agree that any dispute resolution proceedings will
    be conducted only on an individual basis and not as a class, consolidated,
    or representative action.

9.3 SMALL CLAIMS: Either party may bring claims in small claims court if the
    claims qualify.

9.4 GOVERNING LAW: This Agreement shall be governed by and construed in
    accordance with the laws of the State of Delaware, United States, without
    regard to conflict of laws principles.

--------------------------------------------------------------------------------

10. TERMINATION

10.1 VOLUNTARY: You may terminate this Agreement at any time by deactivating
     your organizer account through the platform.

10.2 BY TORO: TORO may suspend or terminate your account at any time for:
     - Violation of this Agreement or platform policies
     - Fraudulent or illegal activity
     - Repeated complaints from vehicle providers or passengers
     - Inactivity exceeding 12 months
     - At TORO's sole discretion with 30 days notice

10.3 EFFECT: Upon termination:
     - All pending events will be cancelled
     - Outstanding payments will be processed within 30 days
     - Your data will be retained as required by law

--------------------------------------------------------------------------------

11. GOVERNING LAW AND JURISDICTION

11.1 FOR UNITED STATES ORGANIZERS:
     This Agreement is governed by the laws of the State of Delaware.
     Jurisdiction: Courts of the State of Delaware or the United States
     District Court for the District of Delaware.

11.2 FOR MEXICO ORGANIZERS:
     This Agreement is governed by the applicable federal laws of Mexico.
     Jurisdiction: Competent courts in Mexico City (Ciudad de Mexico).

--------------------------------------------------------------------------------

12. GENERAL PROVISIONS

12.1 ENTIRE AGREEMENT: This Agreement constitutes the entire agreement between
     you and TORO regarding the subject matter herein.

12.2 SEVERABILITY: If any provision is found to be unenforceable, the remaining
     provisions shall continue in full force and effect.

12.3 AMENDMENTS: TORO may modify this Agreement with 30 days notice. Continued
     use of the platform after modifications constitutes acceptance.

12.4 ASSIGNMENT: You may not assign your rights under this Agreement without
     TORO's written consent.

12.5 NO WAIVER: TORO's failure to enforce any provision shall not constitute
     a waiver of that provision.

================================================================================
By signing below, you acknowledge that you have read, understood, and agree to
be bound by all terms and conditions of this Organizer Platform Agreement.
================================================================================
END OF ORGANIZER PLATFORM AGREEMENT v${LegalConstants.organizerAgreementVersion}
================================================================================
''';

  // ============================================================================
  // ORGANIZER PLATFORM AGREEMENT - SPANISH
  // ============================================================================

  static String get _organizerAgreementEs => '''
================================================================================
ACUERDO DE PLATAFORMA PARA ORGANIZADORES v${LegalConstants.organizerAgreementVersion}
${LegalConstants.companyLegalName}
Fecha de vigencia: ${DateTime.now().toString().split(' ')[0]}
================================================================================

1. DEFINICIONES Y PARTES

Este Acuerdo de Plataforma para Organizadores ("Acuerdo") se celebra entre:

- ${LegalConstants.companyLegalName}, una empresa organizada bajo las leyes del
  ${LegalConstants.companyJurisdiction} ("TORO", "Empresa", "Plataforma", "nosotros")

- Usted, la persona fisica o moral que se registra como organizador de eventos
  en la plataforma TORO ("Organizador", "usted", "su")

"Plataforma" se refiere a la aplicacion movil TORO y servicios relacionados.
"Evento" se refiere a cualquier evento de transporte, viaje, tour o ruta que usted cree.
"Proveedor de Vehiculo" se refiere a conductores o duenos de vehiculos que pujan por sus eventos.
"Comision" se refiere al porcentaje cobrado por TORO sobre las transacciones.

--------------------------------------------------------------------------------

2. ALCANCE DE LA PLATAFORMA

2.1 TORO opera como un mercado tecnologico que conecta organizadores de eventos
    con proveedores de vehiculos. TORO NO:
    - Posee, opera o controla ningun vehiculo
    - Emplea o gestiona proveedores de vehiculos
    - Garantiza la disponibilidad de vehiculos
    - Proporciona servicios de transporte directamente

2.2 TORO proporciona:
    - Una plataforma digital para crear y publicar eventos de transporte
    - Un sistema de pujas para que los proveedores ofrezcan sus servicios
    - Herramientas de procesamiento de pagos y facturacion
    - Canales de comunicacion entre organizadores y proveedores
    - Rastreo GPS en tiempo real durante eventos activos

2.3 Usted reconoce que TORO actua unicamente como intermediario. El contrato
    de transporte es entre usted (Organizador) y el Proveedor de Vehiculo.

--------------------------------------------------------------------------------

3. OBLIGACIONES DEL ORGANIZADOR

3.1 INFORMACION VERAZ: Usted se compromete a proporcionar informacion veridica
    y precisa para todos los eventos, incluyendo pero no limitado a:
    - Fechas, horarios y ubicaciones del evento
    - Numero de pasajeros o asientos requeridos
    - Detalles del itinerario y ruta
    - Cualquier requisito o restriccion especial

3.2 CUMPLIMIENTO LEGAL: Usted es el unico responsable de:
    - Obtener todos los permisos, licencias y autorizaciones necesarios
    - Cumplir con las regulaciones de transporte locales, estatales y federales
    - Asegurar que sus eventos cumplan con todas las leyes aplicables
    - Obtener seguros apropiados para sus eventos si lo requiere la ley

3.3 SEGURIDAD DE PASAJEROS: Usted se compromete a:
    - No organizar eventos que involucren actividades ilegales
    - Informar a los pasajeros sobre los requisitos de seguridad
    - Proporcionar informacion precisa sobre puntos de recogida/entrega
    - Cooperar con los proveedores de vehiculos en materia de seguridad

3.4 ACTIVIDADES PROHIBIDAS: Usted NO puede usar la plataforma para:
    - Organizar eventos para el transporte de bienes o sustancias ilegales
    - Discriminar a pasajeros por raza, religion, genero, orientacion sexual,
      discapacidad u origen nacional
    - Participar en practicas fraudulentas o enganosas
    - Evadir la plataforma para evitar el pago de comisiones
    - Compartir sus credenciales de cuenta con terceros

--------------------------------------------------------------------------------

4. COMISIONES Y PAGOS

4.1 TARIFA DE SERVICIO: TORO cobra una comision del 18% (dieciocho por ciento)
    sobre el monto total de la transaccion por cada evento completado. Esta
    comision se deduce automaticamente antes de transferir los fondos al
    Proveedor de Vehiculo.

4.2 PERIODO DE PRUEBA: La tarifa de comision actual puede estar sujeta a
    cambios. TORO se reserva el derecho de modificar la tarifa de comision
    con 30 dias de aviso previo por escrito.

4.3 PROCESAMIENTO DE PAGOS: Todos los pagos se procesan a traves de la
    plataforma TORO. Los pagos directos entre organizadores y proveedores
    de vehiculos que eviten la plataforma estan estrictamente prohibidos y
    pueden resultar en la terminacion de la cuenta.

4.4 REEMBOLSOS Y CANCELACIONES: Las politicas de reembolso y cancelacion se
    establecen por evento. TORO puede retener una porcion de la comision por
    procesar eventos cancelados, segun la politica de cancelacion.

4.5 RESPONSABILIDAD FISCAL: Usted es el unico responsable de:
    - Reportar todos los ingresos obtenidos a traves de la plataforma ante
      las autoridades fiscales correspondientes
    - Pagar todos los impuestos federales, estatales y locales aplicables
    - Emitir cualquier documento fiscal requerido a los pasajeros (si aplica)
    - Cumplir con los requisitos de IVA, ISR u otros impuestos sobre transacciones
    TORO no proporciona asesoria fiscal y no es responsable de sus obligaciones tributarias.

    PARA MEXICO: Es su responsabilidad cumplir con las obligaciones ante el SAT,
    incluyendo la emision de CFDI (facturas electronicas) si asi lo requiere la ley.

--------------------------------------------------------------------------------

5. PROPIEDAD INTELECTUAL

5.1 El nombre TORO, logotipo, marcas comerciales y todo el contenido de la
    plataforma son propiedad exclusiva de ${LegalConstants.companyLegalName}.

5.2 Se le otorga una licencia limitada, no exclusiva e intransferible para
    usar la plataforma TORO para organizar eventos de transporte.

5.3 No puede usar la marca TORO en ningun material de marketing, publicidad
    o promocion externa sin consentimiento previo por escrito.

5.4 Cualquier contenido que suba a la plataforma (descripciones de eventos,
    imagenes, logotipos) sigue siendo de su propiedad, pero otorga a TORO
    una licencia no exclusiva para mostrar dicho contenido dentro de la plataforma.

--------------------------------------------------------------------------------

6. PRIVACIDAD Y DATOS

6.1 TORO recopila y procesa datos personales segun lo descrito en nuestra
    Politica de Privacidad.

6.2 Los datos recopilados de los organizadores pueden incluir:
    - Nombre, correo electronico, telefono, informacion de la empresa
    - Historial de creacion y gestion de eventos
    - Registros de transacciones financieras
    - Informacion del dispositivo y direcciones IP
    - Datos de ubicacion GPS (con su consentimiento)

6.3 Cumplimos con las leyes de proteccion de datos aplicables incluyendo CCPA
    (California) y las regulaciones mexicanas de proteccion de datos (LFPDPPP).

6.4 Usted se compromete a no hacer mal uso de los datos personales de
    pasajeros o proveedores de vehiculos obtenidos a traves de la plataforma.

--------------------------------------------------------------------------------

7. LIMITACION DE RESPONSABILIDAD

7.1 TORO ES UN MERCADO TECNOLOGICO, NO UN PROVEEDOR DE TRANSPORTE.

7.2 EN LA MAXIMA MEDIDA PERMITIDA POR LA LEY, TORO NO SERA RESPONSABLE POR:
    - Accidentes, lesiones o danos a la propiedad durante eventos de transporte
    - Actos, omisiones o negligencia de los proveedores de vehiculos
    - Retrasos, cancelaciones o interrupciones del servicio por proveedores
    - Perdida de ingresos u oportunidades de negocio
    - Cualquier dano indirecto, incidental, especial o consecuente

7.3 La responsabilidad total de TORO por cualquier reclamo derivado de este
    Acuerdo no excedera las comisiones totales pagadas por usted o en su
    nombre en los doce (12) meses anteriores al reclamo.

7.4 LA PLATAFORMA SE PROPORCIONA "TAL CUAL" Y "SEGUN DISPONIBILIDAD" SIN
    GARANTIAS DE NINGUN TIPO, EXPRESAS O IMPLICITAS.

--------------------------------------------------------------------------------

8. INDEMNIZACION

8.1 Usted acepta indemnizar, defender y mantener indemne a
    ${LegalConstants.companyLegalName}, sus directivos, empleados, agentes y
    afiliados de y contra cualquier reclamo, dano, perdida, responsabilidad,
    costo y gasto (incluyendo honorarios razonables de abogados) que surjan
    de o esten relacionados con:

    a) Su uso de la plataforma
    b) Eventos que organice a traves de la plataforma
    c) Su incumplimiento de este Acuerdo
    d) Su violacion de cualquier ley o regulacion aplicable
    e) Cualquier reclamo de un pasajero, proveedor de vehiculo o tercero
       relacionado con sus eventos

--------------------------------------------------------------------------------

9. RESOLUCION DE DISPUTAS

9.1 ARBITRAJE: Cualquier disputa que surja de este Acuerdo se resolvera
    mediante arbitraje vinculante administrado por la Asociacion Americana
    de Arbitraje (AAA) bajo sus Reglas de Arbitraje Comercial.

9.2 RENUNCIA A ACCION COLECTIVA: Usted acepta que cualquier procedimiento de
    resolucion de disputas se llevara a cabo unicamente de forma individual y
    no como una accion colectiva, consolidada o representativa.

9.3 RECLAMOS MENORES: Cualquiera de las partes puede presentar reclamos en
    tribunales de reclamos menores si los reclamos califican.

9.4 LEY APLICABLE: Este Acuerdo se regira e interpretara de acuerdo con las
    leyes del Estado de Delaware, Estados Unidos, sin tener en cuenta los
    principios de conflicto de leyes.

--------------------------------------------------------------------------------

10. TERMINACION

10.1 VOLUNTARIA: Usted puede terminar este Acuerdo en cualquier momento
     desactivando su cuenta de organizador a traves de la plataforma.

10.2 POR TORO: TORO puede suspender o terminar su cuenta en cualquier
     momento por:
     - Violacion de este Acuerdo o politicas de la plataforma
     - Actividad fraudulenta o ilegal
     - Quejas repetidas de proveedores de vehiculos o pasajeros
     - Inactividad que exceda 12 meses
     - A la entera discrecion de TORO con 30 dias de aviso

10.3 EFECTO: Al terminar:
     - Todos los eventos pendientes seran cancelados
     - Los pagos pendientes se procesaran dentro de 30 dias
     - Sus datos se conservaran segun lo requiera la ley

--------------------------------------------------------------------------------

11. LEY APLICABLE Y JURISDICCION

11.1 PARA ORGANIZADORES EN ESTADOS UNIDOS:
     Este Acuerdo se rige por las leyes del Estado de Delaware.
     Jurisdiccion: Tribunales del Estado de Delaware o el Tribunal de
     Distrito de los Estados Unidos para el Distrito de Delaware.

11.2 PARA ORGANIZADORES EN MEXICO:
     Este Acuerdo se rige por las leyes federales aplicables de Mexico.
     Jurisdiccion: Tribunales competentes en la Ciudad de Mexico.

--------------------------------------------------------------------------------

12. DISPOSICIONES GENERALES

12.1 ACUERDO COMPLETO: Este Acuerdo constituye el acuerdo completo entre
     usted y TORO con respecto al tema aqui tratado.

12.2 DIVISIBILIDAD: Si alguna disposicion se considera inaplicable, las
     disposiciones restantes continuaran en plena vigencia y efecto.

12.3 MODIFICACIONES: TORO puede modificar este Acuerdo con 30 dias de aviso.
     El uso continuado de la plataforma despues de las modificaciones
     constituye aceptacion.

12.4 CESION: Usted no puede ceder sus derechos bajo este Acuerdo sin el
     consentimiento escrito de TORO.

12.5 NO RENUNCIA: La falta de TORO de hacer cumplir cualquier disposicion
     no constituira una renuncia a dicha disposicion.

================================================================================
Al firmar a continuacion, usted reconoce que ha leido, entendido y acepta
obligarse por todos los terminos y condiciones de este Acuerdo de Plataforma
para Organizadores.
================================================================================
FIN DEL ACUERDO DE PLATAFORMA PARA ORGANIZADORES v${LegalConstants.organizerAgreementVersion}
================================================================================
''';
}
