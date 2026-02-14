// Edge Function: generate-cfdi
// Generates CFDI (Mexican electronic invoice) via PAC integration

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface CfdiRequest {
  ride_id?: string
  delivery_id?: string
  rider_id: string
  receptor_rfc: string
  receptor_nombre: string
  receptor_regimen: string
  receptor_codigo_postal: string
  receptor_uso_cfdi: string
}

interface CfdiResponse {
  success: boolean
  data?: {
    invoice_id: string
    uuid_fiscal: string
    xml_url: string
    pdf_url: string
    total: number
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

    const body: CfdiRequest = await req.json()
    const {
      ride_id,
      delivery_id,
      rider_id,
      receptor_rfc,
      receptor_nombre,
      receptor_regimen,
      receptor_codigo_postal,
      receptor_uso_cfdi
    } = body

    // Validate required fields
    if (!rider_id || !receptor_rfc || !receptor_regimen || !receptor_codigo_postal) {
      return new Response(
        JSON.stringify({ success: false, error: 'Missing required fields' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
      )
    }

    // Get platform CFDI config
    const { data: platformConfig, error: configError } = await supabaseClient
      .from('cfdi_platform_config')
      .select('*')
      .eq('country_code', 'MX')
      .eq('is_active', true)
      .single()

    if (configError || !platformConfig) {
      return new Response(
        JSON.stringify({ success: false, error: 'CFDI platform not configured' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // Get transaction details
    let subtotal = 0
    let conceptos: any[] = []

    if (ride_id) {
      const { data: ride } = await supabaseClient
        .from('rides')
        .select('*, ride_fares(*)')
        .eq('id', ride_id)
        .single()

      if (ride) {
        subtotal = ride.ride_fares?.subtotal || ride.fare || 0
        conceptos = [{
          ClaveProdServ: '78101802', // Servicios de taxi
          NoIdentificacion: ride_id,
          Cantidad: 1,
          ClaveUnidad: 'E48', // Unidad de servicio
          Unidad: 'Servicio',
          Descripcion: `Servicio de transporte privado - ${ride.pickup_address} a ${ride.dropoff_address}`,
          ValorUnitario: subtotal,
          Importe: subtotal,
          ObjetoImp: '02', // Sí objeto de impuesto
          Impuestos: {
            Traslados: [{
              Base: subtotal,
              Impuesto: '002', // IVA
              TipoFactor: 'Tasa',
              TasaOCuota: 0.16,
              Importe: Math.round(subtotal * 0.16 * 100) / 100
            }]
          }
        }]
      }
    } else if (delivery_id) {
      const { data: delivery } = await supabaseClient
        .from('package_deliveries')
        .select('*')
        .eq('id', delivery_id)
        .single()

      if (delivery) {
        subtotal = delivery.final_price || delivery.estimated_price || 0
        conceptos = [{
          ClaveProdServ: '78102200', // Servicios de mensajería
          NoIdentificacion: delivery_id,
          Cantidad: 1,
          ClaveUnidad: 'E48',
          Unidad: 'Servicio',
          Descripcion: `Servicio de entrega - ${delivery.pickup_address} a ${delivery.destination_address}`,
          ValorUnitario: subtotal,
          Importe: subtotal,
          ObjetoImp: '02',
          Impuestos: {
            Traslados: [{
              Base: subtotal,
              Impuesto: '002',
              TipoFactor: 'Tasa',
              TasaOCuota: 0.16,
              Importe: Math.round(subtotal * 0.16 * 100) / 100
            }]
          }
        }]
      }
    }

    if (subtotal === 0) {
      return new Response(
        JSON.stringify({ success: false, error: 'Transaction not found or has no amount' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
      )
    }

    const ivaAmount = Math.round(subtotal * 0.16 * 100) / 100
    const total = subtotal + ivaAmount

    // Generate CFDI via PAC
    // This is a placeholder - actual implementation depends on PAC provider
    const pacProvider = platformConfig.pac_provider
    let cfdiResult: any

    if (pacProvider === 'facturama') {
      cfdiResult = await generateViaFacturama(platformConfig, {
        receptor: {
          Rfc: receptor_rfc.toUpperCase(),
          Nombre: receptor_nombre,
          RegimenFiscalReceptor: receptor_regimen,
          DomicilioFiscalReceptor: receptor_codigo_postal,
          UsoCFDI: receptor_uso_cfdi
        },
        conceptos,
        subtotal,
        ivaAmount,
        total
      })
    } else {
      // Sandbox/mock response for development
      cfdiResult = {
        success: true,
        uuid: `MOCK-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`.toUpperCase(),
        xml_url: `https://storage.example.com/cfdi/${Date.now()}.xml`,
        pdf_url: `https://storage.example.com/cfdi/${Date.now()}.pdf`
      }
    }

    if (!cfdiResult.success) {
      // Save failed attempt
      await supabaseClient
        .from('cfdi_invoices')
        .insert({
          ride_id,
          delivery_id,
          rider_id,
          emisor_rfc: platformConfig.emisor_rfc,
          emisor_nombre: platformConfig.emisor_nombre,
          emisor_regimen: platformConfig.emisor_regimen,
          receptor_rfc: receptor_rfc.toUpperCase(),
          receptor_nombre,
          receptor_regimen,
          receptor_codigo_postal,
          receptor_uso_cfdi,
          subtotal,
          iva_rate: 0.16,
          iva_amount: ivaAmount,
          total,
          conceptos,
          status: 'error',
          error_message: cfdiResult.error,
          pac_provider: pacProvider
        })

      return new Response(
        JSON.stringify({ success: false, error: cfdiResult.error }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
      )
    }

    // Save successful invoice
    const { data: invoice, error: insertError } = await supabaseClient
      .from('cfdi_invoices')
      .insert({
        ride_id,
        delivery_id,
        rider_id,
        emisor_rfc: platformConfig.emisor_rfc,
        emisor_nombre: platformConfig.emisor_nombre,
        emisor_regimen: platformConfig.emisor_regimen,
        receptor_rfc: receptor_rfc.toUpperCase(),
        receptor_nombre,
        receptor_regimen,
        receptor_codigo_postal,
        receptor_uso_cfdi,
        uuid_fiscal: cfdiResult.uuid,
        fecha_timbrado: new Date().toISOString(),
        subtotal,
        iva_rate: 0.16,
        iva_amount: ivaAmount,
        total,
        conceptos,
        xml_url: cfdiResult.xml_url,
        pdf_url: cfdiResult.pdf_url,
        status: 'timbrado',
        pac_provider: pacProvider
      })
      .select()
      .single()

    if (insertError) {
      console.error('Error saving invoice:', insertError)
    }

    // Update rider profile with fiscal data
    await supabaseClient
      .from('profiles')
      .update({
        rfc: receptor_rfc.toUpperCase(),
        regimen_fiscal: receptor_regimen,
        codigo_postal: receptor_codigo_postal
      })
      .eq('id', rider_id)

    const response: CfdiResponse = {
      success: true,
      data: {
        invoice_id: invoice?.id || '',
        uuid_fiscal: cfdiResult.uuid,
        xml_url: cfdiResult.xml_url,
        pdf_url: cfdiResult.pdf_url,
        total
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

// Facturama integration (placeholder)
async function generateViaFacturama(config: any, data: any): Promise<any> {
  const facturamaUser = Deno.env.get('FACTURAMA_USER')
  const facturamaPassword = Deno.env.get('FACTURAMA_PASSWORD')
  const isSandbox = Deno.env.get('FACTURAMA_SANDBOX') === 'true'

  if (!facturamaUser || !facturamaPassword) {
    return { success: false, error: 'Facturama credentials not configured' }
  }

  const baseUrl = isSandbox
    ? 'https://apisandbox.facturama.mx'
    : 'https://api.facturama.mx'

  try {
    // Build CFDI request
    const cfdiRequest = {
      Serie: 'T',
      Currency: 'MXN',
      ExpeditionPlace: config.lugar_expedicion,
      PaymentConditions: 'CONTADO',
      Folio: Date.now().toString(),
      CfdiType: 'I', // Ingreso
      PaymentForm: config.forma_pago || '03',
      PaymentMethod: config.metodo_pago || 'PUE',
      Receiver: data.receptor,
      Items: data.conceptos.map((c: any) => ({
        ProductCode: c.ClaveProdServ,
        IdentificationNumber: c.NoIdentificacion,
        Description: c.Descripcion,
        Unit: c.Unidad,
        UnitCode: c.ClaveUnidad,
        UnitPrice: c.ValorUnitario,
        Quantity: c.Cantidad,
        Subtotal: c.Importe,
        TaxObject: c.ObjetoImp,
        Taxes: c.Impuestos?.Traslados?.map((t: any) => ({
          Total: t.Importe,
          Name: 'IVA',
          Base: t.Base,
          Rate: t.TasaOCuota,
          IsRetention: false
        })),
        Total: c.Importe + (c.Impuestos?.Traslados?.[0]?.Importe || 0)
      }))
    }

    const response = await fetch(`${baseUrl}/3/cfdis`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Basic ' + btoa(`${facturamaUser}:${facturamaPassword}`)
      },
      body: JSON.stringify(cfdiRequest)
    })

    if (!response.ok) {
      const errorText = await response.text()
      return { success: false, error: `Facturama error: ${errorText}` }
    }

    const result = await response.json()

    return {
      success: true,
      uuid: result.Complement?.TaxStamp?.Uuid,
      xml_url: `${baseUrl}/cfdi/xml/${result.Id}`,
      pdf_url: `${baseUrl}/cfdi/pdf/${result.Id}`
    }

  } catch (error) {
    return { success: false, error: `Facturama error: ${error.message}` }
  }
}
