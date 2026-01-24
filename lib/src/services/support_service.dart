import 'package:flutter/foundation.dart';
import '../config/supabase_config.dart';
import 'ticket_service.dart';

/// Support Service - Handles account recovery and help requests
/// Uses TicketService internally for actual ticket creation
class SupportService {
  static final SupportService instance = SupportService._();
  SupportService._();

  final TicketService _ticketService = TicketService();

  /// Create a help request for account recovery/issues
  Future<bool> createHelpRequest({
    required String driverId,
    required String message,
    required String category,
    String? driverName,
    String? driverEmail,
    String? driverPhone,
  }) async {
    try {
      // Get driver info if not provided
      String name = driverName ?? 'Driver';
      String? email = driverEmail;
      String? phone = driverPhone;

      if (driverName == null) {
        try {
          final driverData = await SupabaseConfig.client
              .from('drivers')
              .select('first_name, last_name, email, phone')
              .eq('id', driverId)
              .maybeSingle();

          if (driverData != null) {
            final firstName = driverData['first_name'] ?? '';
            final lastName = driverData['last_name'] ?? '';
            name = '$firstName $lastName'.trim();
            email = driverData['email'];
            phone = driverData['phone'];
          }
        } catch (e) {
          debugPrint('SupportService: Could not fetch driver info: $e');
        }
      }

      // Map category to subject
      final subject = _getSubjectForCategory(category);

      // Create ticket using TicketService
      final ticket = await _ticketService.createTicket(
        subject: subject,
        description: message,
        category: category,
        priority: _getPriorityForCategory(category),
        userId: driverId,
        userName: name,
        userEmail: email,
        userPhone: phone,
      );

      if (ticket != null) {
        debugPrint('SupportService: Help request created with ID: ${ticket['id']}');

        // Also log to audit for admin visibility
        await _logToAudit(
          driverId: driverId,
          action: 'help_request_created',
          details: {
            'ticket_id': ticket['id'],
            'category': category,
            'subject': subject,
          },
        );

        return true;
      }

      return false;
    } catch (e) {
      debugPrint('SupportService: Error creating help request: $e');
      return false;
    }
  }

  /// Get subject based on category
  String _getSubjectForCategory(String category) {
    switch (category) {
      case 'account_recovery':
        return 'Solicitud de Recuperación de Cuenta';
      case 'documents':
        return 'Problema con Documentos';
      case 'approval':
        return 'Consulta sobre Aprobación de Cuenta';
      case 'suspension':
        return 'Apelación de Suspensión';
      case 'technical':
        return 'Problema Técnico';
      default:
        return 'Solicitud de Ayuda';
    }
  }

  /// Get priority based on category
  String _getPriorityForCategory(String category) {
    switch (category) {
      case 'suspension':
      case 'account_recovery':
        return 'high';
      case 'documents':
      case 'approval':
        return 'medium';
      default:
        return 'normal';
    }
  }

  /// Log to audit table
  Future<void> _logToAudit({
    required String driverId,
    required String action,
    required Map<String, dynamic> details,
  }) async {
    try {
      await SupabaseConfig.client.from('audit_log').insert({
        'entity_type': 'driver',
        'entity_id': driverId,
        'action': action,
        'details': details,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('SupportService: Could not log to audit: $e');
    }
  }

  /// Get open help requests for a driver
  Future<List<Map<String, dynamic>>> getOpenRequests(String driverId) async {
    return await _ticketService.getDriverTickets(driverId);
  }

  /// Get count of open requests
  Future<int> getOpenRequestsCount(String driverId) async {
    return await _ticketService.getOpenTicketsCount(driverId);
  }
}
