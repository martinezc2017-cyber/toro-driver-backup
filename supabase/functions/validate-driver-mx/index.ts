// Edge Function: validate-driver-mx
// Validates Mexican driver documents and RFC

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface ValidateRequest {
  driver_id: string
  validation_type: 'rfc' | 'documents' | 'all'
  rfc?: string
}

interface ValidationResult {
  is_valid: boolean
  field: string
  message: string
}

interface ValidateResponse {
  success: boolean
  data?: {
    is_complete: boolean
    validations: ValidationResult[]
    missing_documents: string[]
    expiring_soon: string[]
    rfc_validated: boolean
  }
  error?: string
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      {
        auth: {
          autoRefreshToken: false,
          persistSession: false
        }
      }
    )

    const body: ValidateRequest = await req.json()
    const { driver_id, validation_type, rfc } = body

    if (!driver_id) {
      return new Response(
        JSON.stringify({ success: false, error: 'driver_id is required' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Get driver
    const { data: driver, error: driverError } = await supabaseClient
      .from('drivers')
      .select('*')
      .eq('id', driver_id)
      .single()

    if (driverError || !driver) {
      return new Response(
        JSON.stringify({ success: false, error: 'Driver not found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    const validations: ValidationResult[] = []
    let rfcValidated = driver.rfc_validated || false

    // Validate RFC if provided or requested
    if (validation_type === 'rfc' || validation_type === 'all') {
      const rfcToValidate = rfc || driver.rfc

      if (rfcToValidate) {
        const rfcValidation = validateRfc(rfcToValidate)
        validations.push(rfcValidation)

        if (rfcValidation.is_valid) {
          // Update driver RFC
          await supabaseClient
            .from('drivers')
            .update({
              rfc: rfcToValidate.toUpperCase(),
              rfc_validated: true
            })
            .eq('id', driver_id)

          rfcValidated = true
        }
      } else {
        validations.push({
          is_valid: false,
          field: 'rfc',
          message: 'RFC no proporcionado'
        })
      }
    }

    // Check documents
    let missingDocuments: string[] = []
    let expiringSoon: string[] = []

    if (validation_type === 'documents' || validation_type === 'all') {
      // Get required documents for driver's country/state
      const { data: requirements } = await supabaseClient
        .rpc('get_required_documents', {
          p_country_code: driver.country_code || 'MX',
          p_state_code: driver.state_code
        })

      // Get driver's uploaded documents
      const { data: uploadedDocs } = await supabaseClient
        .from('driver_documents_mx')
        .select('*')
        .eq('driver_id', driver_id)

      const { data: legacyDocs } = await supabaseClient
        .from('documents')
        .select('*')
        .eq('driver_id', driver_id)

      const uploadedDocTypes = new Set([
        ...(uploadedDocs || []).map(d => d.document_type),
        ...(legacyDocs || []).map(d => d.type)
      ])

      const approvedDocTypes = new Set([
        ...(uploadedDocs || []).filter(d => d.verification_status === 'approved').map(d => d.document_type),
        ...(legacyDocs || []).filter(d => d.status === 'approved').map(d => d.type)
      ])

      // Check each requirement
      for (const req of (requirements || [])) {
        if (req.is_required && !approvedDocTypes.has(req.document_type)) {
          missingDocuments.push(req.document_type)

          validations.push({
            is_valid: false,
            field: req.document_type,
            message: `${req.display_name} es requerido`
          })
        }
      }

      // Check expiring documents
      const thirtyDaysFromNow = new Date()
      thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30)

      for (const doc of (uploadedDocs || [])) {
        if (doc.expiry_date) {
          const expiryDate = new Date(doc.expiry_date)
          if (expiryDate <= thirtyDaysFromNow) {
            expiringSoon.push(doc.document_type)

            validations.push({
              is_valid: true, // Still valid but warning
              field: doc.document_type,
              message: `${doc.document_type} vence el ${doc.expiry_date}`
            })
          }
        }
      }

      // Check driver's insurance
      if (driver.insurance_expiry) {
        const insuranceExpiry = new Date(driver.insurance_expiry)
        if (insuranceExpiry <= new Date()) {
          validations.push({
            is_valid: false,
            field: 'seguro',
            message: 'Seguro vencido'
          })
          missingDocuments.push('seguroERT')
        } else if (insuranceExpiry <= thirtyDaysFromNow) {
          expiringSoon.push('seguro')
          validations.push({
            is_valid: true,
            field: 'seguro',
            message: `Seguro vence el ${driver.insurance_expiry}`
          })
        }
      }

      // Check SEMOVI constancias for CDMX
      if (driver.state_code === 'CDMX') {
        if (driver.semovi_constancia_expiry) {
          const constanciaExpiry = new Date(driver.semovi_constancia_expiry)
          if (constanciaExpiry <= new Date()) {
            validations.push({
              is_valid: false,
              field: 'constanciaSemovi',
              message: 'Constancia SEMOVI vencida'
            })
            missingDocuments.push('constanciaSemovi')
          }
        }

        if (driver.semovi_vehicular_expiry) {
          const vehicularExpiry = new Date(driver.semovi_vehicular_expiry)
          if (vehicularExpiry <= new Date()) {
            validations.push({
              is_valid: false,
              field: 'constanciaVehicular',
              message: 'Constancia Vehicular vencida'
            })
            missingDocuments.push('constanciaVehicular')
          }
        }
      }
    }

    const isComplete = missingDocuments.length === 0 &&
      validations.every(v => v.is_valid) &&
      rfcValidated

    const response: ValidateResponse = {
      success: true,
      data: {
        is_complete: isComplete,
        validations,
        missing_documents: missingDocuments,
        expiring_soon: expiringSoon,
        rfc_validated: rfcValidated
      }
    }

    return new Response(
      JSON.stringify(response),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})

function validateRfc(rfc: string): ValidationResult {
  if (!rfc) {
    return {
      is_valid: false,
      field: 'rfc',
      message: 'RFC es requerido'
    }
  }

  const cleanRfc = rfc.toUpperCase().replace(/\s/g, '')

  // Check length (12 for moral, 13 for física)
  if (cleanRfc.length < 12 || cleanRfc.length > 13) {
    return {
      is_valid: false,
      field: 'rfc',
      message: 'RFC debe tener 12 o 13 caracteres'
    }
  }

  // Pattern validation
  let pattern: RegExp
  if (cleanRfc.length === 13) {
    // Persona física: AAAA######XXX
    pattern = /^[A-ZÑ&]{4}[0-9]{6}[A-Z0-9]{3}$/
  } else {
    // Persona moral: AAA######XXX
    pattern = /^[A-ZÑ&]{3}[0-9]{6}[A-Z0-9]{3}$/
  }

  if (!pattern.test(cleanRfc)) {
    return {
      is_valid: false,
      field: 'rfc',
      message: 'Formato de RFC inválido'
    }
  }

  // Validate date portion (AAMMDD or YYMMDD)
  const dateStart = cleanRfc.length === 13 ? 4 : 3
  const year = parseInt(cleanRfc.substring(dateStart, dateStart + 2))
  const month = parseInt(cleanRfc.substring(dateStart + 2, dateStart + 4))
  const day = parseInt(cleanRfc.substring(dateStart + 4, dateStart + 6))

  if (month < 1 || month > 12) {
    return {
      is_valid: false,
      field: 'rfc',
      message: 'Mes inválido en RFC'
    }
  }

  if (day < 1 || day > 31) {
    return {
      is_valid: false,
      field: 'rfc',
      message: 'Día inválido en RFC'
    }
  }

  return {
    is_valid: true,
    field: 'rfc',
    message: 'RFC válido'
  }
}
