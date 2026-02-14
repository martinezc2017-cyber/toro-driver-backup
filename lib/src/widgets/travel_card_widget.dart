import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../utils/app_colors.dart';

class TravelCardWidget extends StatelessWidget {
  final String eventName;
  final String originName;
  final String destinationName;
  final String formattedDate;
  final String eventStatus;
  final int stopsCount;
  final int availableSeats;
  final int totalSeats;
  final double ticketPrice;
  final bool showPrice;
  final String personName;
  final String personRole;
  final String personCompany;
  final String personAvatarUrl;
  final String personLogoUrl;
  final String personPhone;
  final String personEmail;
  final String personWebsite;
  final String personDescription;
  final String invitationCode;

  const TravelCardWidget({
    super.key,
    required this.originName,
    required this.destinationName,
    required this.formattedDate,
    required this.invitationCode,
    this.eventName = '',
    this.eventStatus = 'active',
    this.stopsCount = 0,
    this.availableSeats = 0,
    this.totalSeats = 0,
    this.ticketPrice = 0,
    this.showPrice = true,
    this.personName = '',
    this.personRole = 'Organiza',
    this.personCompany = '',
    this.personAvatarUrl = '',
    this.personLogoUrl = '',
    this.personPhone = '',
    this.personEmail = '',
    this.personWebsite = '',
    this.personDescription = '',
  });

  int get _bookedSeats => totalSeats - availableSeats;

  String get _displayTitle {
    if (personCompany.isNotEmpty) return personCompany;
    if (personName.isNotEmpty) return personName;
    return 'Toro Ride';
  }

  String get _heroImageUrl {
    if (personLogoUrl.isNotEmpty) return personLogoUrl;
    if (personAvatarUrl.isNotEmpty) return personAvatarUrl;
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A1628),
            Color(0xFF0E1F33),
            Color(0xFF0C2A3A),
            Color(0xFF0E1F33),
            Color(0xFF111820),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF1A3A4A).withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeroHeader(),
          _line(),
          if (_hasContact) _buildContactRow(),
          _buildRouteSection(),
          _line(),
          _buildQrRow(),
          _buildFooter(),
        ],
      ),
    ),
      ),
    );
  }

  Widget _line() =>
      Container(height: 1, color: Colors.white.withValues(alpha: 0.06));

  bool get _hasContact =>
      personPhone.isNotEmpty ||
      personEmail.isNotEmpty ||
      personWebsite.isNotEmpty;

  // ═══════════════════════════════════════════════════════════════════════════
  // 1. HERO HEADER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildHeroHeader() {
    return SizedBox(
      height: 160,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_heroImageUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: Image.network(
                  _heroImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0A1628).withValues(alpha: 0.85),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    if (_heroImageUrl.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          _heroImageUrl,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _miniInitial(),
                        ),
                      ),
                      const SizedBox(width: 14),
                    ] else ...[
                      _miniInitial(),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: Text(
                        _displayTitle,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(personRole,
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (eventName.isNotEmpty &&
                    eventName.toLowerCase() != _displayTitle.toLowerCase()) ...[
                  const SizedBox(height: 8),
                  Text(
                    eventName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniInitial() {
    final initial =
        _displayTitle.isNotEmpty ? _displayTitle[0].toUpperCase() : '?';
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 24,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 2. ROUTE + DATE + STATUS
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildRouteSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$originName  \u2192  $destinationName',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              _statusBadge(),
            ],
          ),
          if (formattedDate.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 7),
                Text(
                  formattedDate,
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 16),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge() {
    Color color;
    String label;
    switch (eventStatus) {
      case 'full':
        color = AppColors.warning;
        label = 'Lleno';
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'Cancelado';
        break;
      case 'completed':
        color = AppColors.textTertiary;
        label = 'Finalizado';
        break;
      default:
        color = AppColors.success;
        label = 'Activo';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 3. CONTACT ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildContactRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (personPhone.isNotEmpty)
            _contactChip(Icons.phone, personPhone),
          if (personEmail.isNotEmpty)
            _contactChip(Icons.email_outlined, personEmail),
          if (personWebsite.isNotEmpty)
            _contactChip(Icons.language, personWebsite),
        ],
      ),
    );
  }

  Widget _contactChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(text,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 4. QR ROW
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildQrRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQrCard(),
          const SizedBox(width: 20),
          Expanded(child: _buildTripStats()),
        ],
      ),
    );
  }

  Widget _buildQrCard() {
    ImageProvider? embeddedImage;
    final logoUrl =
        personLogoUrl.isNotEmpty ? personLogoUrl : personAvatarUrl;
    if (logoUrl.isNotEmpty) {
      embeddedImage = NetworkImage(logoUrl);
    } else {
      embeddedImage = const AssetImage('assets/images/toro_logo_new.png');
    }

    return Container(
      width: 185,
      height: 185,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.04),
            blurRadius: 14,
          ),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: QrImageView(
        data: 'tororider://tourism/invite/$invitationCode',
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        size: 165,
        backgroundColor: Colors.white,
        embeddedImage: embeddedImage,
        embeddedImageStyle: const QrEmbeddedImageStyle(
          size: Size(32, 32),
        ),
        eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square, color: Colors.black),
        dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      ),
    );
  }

  Widget _buildTripStats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stopsCount > 0) ...[
          _statRow(Icons.place, 'Paradas', '$stopsCount'),
          const SizedBox(height: 18),
        ],
        if (totalSeats > 0) ...[
          _statRow(Icons.event_seat, 'Libres / Total',
              '$availableSeats / $totalSeats'),
          const SizedBox(height: 18),
        ],
        if (showPrice && ticketPrice > 0)
          _statRow(Icons.confirmation_number_outlined, 'Boleto',
              '\$${ticketPrice.toStringAsFixed(0)} MXN'),
      ],
    );
  }

  Widget _statRow(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 5. FOOTER
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        children: [
          Text(
            invitationCode,
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 15, height: 1.3),
              children: const [
                TextSpan(text: 'Escanea el '),
                TextSpan(
                    text: 'codigo QR',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
                TextSpan(text: ' para unirte al viaje'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
