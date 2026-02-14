// Bus Tourism Payment Split Calculator
//
// Split model:
// - Bus owner sets base price per seat
// - Passenger pays base_price * 1.21 (21% TORO surcharge)
// - TORO keeps base_price * 0.18 (18%)
// - Organizer gets base_price * 0.03 (3%, if present)
// - Bus owner receives base_price * 1.00 (full price)

class BusTourismSplitConfig {
  final double toroSurchargePercent;
  final double toroKeepPercent;
  final double organizerCommissionPercent;

  const BusTourismSplitConfig({
    this.toroSurchargePercent = 21.0,
    this.toroKeepPercent = 18.0,
    this.organizerCommissionPercent = 3.0,
  });
}

class BusTourismSplitBreakdown {
  /// The price per seat set by the bus owner.
  final double basePricePerSeat;

  /// What each passenger pays (base + TORO surcharge).
  final double passengerPricePerSeat;

  /// TORO's fee per seat (from the surcharge).
  final double toroFeePerSeat;

  /// Organizer commission per seat (0 if no organizer).
  final double organizerCommissionPerSeat;

  /// What the bus owner receives per seat (always 100% of base price).
  final double busOwnerReceivesPerSeat;

  /// Number of seats in this calculation.
  final int seatsCount;

  /// Total amount all passengers pay.
  final double totalPassengerPays;

  /// Total TORO fee across all seats.
  final double totalToroFee;

  /// Total organizer commission across all seats.
  final double totalOrganizerCommission;

  /// Total amount the bus owner receives.
  final double totalBusOwnerReceives;

  const BusTourismSplitBreakdown({
    required this.basePricePerSeat,
    required this.passengerPricePerSeat,
    required this.toroFeePerSeat,
    required this.organizerCommissionPerSeat,
    required this.busOwnerReceivesPerSeat,
    required this.seatsCount,
    required this.totalPassengerPays,
    required this.totalToroFee,
    required this.totalOrganizerCommission,
    required this.totalBusOwnerReceives,
  });

  Map<String, dynamic> toJson() => {
        'base_price_per_seat': basePricePerSeat,
        'passenger_price_per_seat': passengerPricePerSeat,
        'toro_fee_per_seat': toroFeePerSeat,
        'organizer_commission_per_seat': organizerCommissionPerSeat,
        'bus_owner_receives_per_seat': busOwnerReceivesPerSeat,
        'seats_count': seatsCount,
        'total_passenger_pays': totalPassengerPays,
        'total_toro_fee': totalToroFee,
        'total_organizer_commission': totalOrganizerCommission,
        'total_bus_owner_receives': totalBusOwnerReceives,
      };

  @override
  String toString() =>
      'BusTourismSplitBreakdown(seats: $seatsCount, '
      'passengerPays: \$$totalPassengerPays, '
      'toroFee: \$$totalToroFee, '
      'organizerCommission: \$$totalOrganizerCommission, '
      'busOwnerReceives: \$$totalBusOwnerReceives)';
}

class BusTourismSplitCalculator {
  final BusTourismSplitConfig config;

  const BusTourismSplitCalculator({
    this.config = const BusTourismSplitConfig(),
  });

  /// Rounds a value to 2 decimal places.
  double _round2(double value) =>
      double.parse(value.toStringAsFixed(2));

  /// Calculates the full payment split for a bus tourism booking.
  ///
  /// [basePricePerSeat] is the price the bus owner sets per seat.
  /// [seatsCount] is the number of seats being booked.
  /// [hasOrganizer] indicates whether an organizer is present to receive
  /// their commission share.
  BusTourismSplitBreakdown calculate({
    required double basePricePerSeat,
    required int seatsCount,
    bool hasOrganizer = false,
  }) {
    // Per-seat calculations
    final surchargePerSeat = _round2(
      basePricePerSeat * (config.toroSurchargePercent / 100),
    );
    final passengerPricePerSeat = _round2(basePricePerSeat + surchargePerSeat);
    final toroFeePerSeat = _round2(
      basePricePerSeat * (config.toroKeepPercent / 100),
    );
    final organizerCommissionPerSeat = hasOrganizer
        ? _round2(basePricePerSeat * (config.organizerCommissionPercent / 100))
        : 0.0;
    final busOwnerReceivesPerSeat = _round2(basePricePerSeat);

    // Totals (per-seat * seatsCount)
    final totalPassengerPays = _round2(passengerPricePerSeat * seatsCount);
    final totalToroFee = _round2(toroFeePerSeat * seatsCount);
    final totalOrganizerCommission =
        _round2(organizerCommissionPerSeat * seatsCount);
    final totalBusOwnerReceives =
        _round2(busOwnerReceivesPerSeat * seatsCount);

    return BusTourismSplitBreakdown(
      basePricePerSeat: _round2(basePricePerSeat),
      passengerPricePerSeat: passengerPricePerSeat,
      toroFeePerSeat: toroFeePerSeat,
      organizerCommissionPerSeat: organizerCommissionPerSeat,
      busOwnerReceivesPerSeat: busOwnerReceivesPerSeat,
      seatsCount: seatsCount,
      totalPassengerPays: totalPassengerPays,
      totalToroFee: totalToroFee,
      totalOrganizerCommission: totalOrganizerCommission,
      totalBusOwnerReceives: totalBusOwnerReceives,
    );
  }

  /// Helper to calculate the ticket price per passenger from a per-km rate.
  ///
  /// Formula: km × price_per_km = fare per passenger.
  double calculateTicketPrice({
    required double pricePerKm,
    required double distanceKm,
  }) {
    return _round2(pricePerKm * distanceKm);
  }
}
