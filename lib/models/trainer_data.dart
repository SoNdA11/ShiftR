class TrainerData {
  final double speed;
  final double cadence;
  final int power;
  final int heartRate;
  final int gear;
  final int resistance;

  const TrainerData({
    this.speed = 0,
    this.cadence = 0,
    this.power = 0,
    this.heartRate = 0,
    this.gear = 1,
    this.resistance = 0,
  });

  TrainerData copyWith({
    double? speed,
    double? cadence,
    int? power,
    int? heartRate,
    int? gear,
    int? resistance,
  }) {
    return TrainerData(
      speed: speed ?? this.speed,
      cadence: cadence ?? this.cadence,
      power: power ?? this.power,
      heartRate: heartRate ?? this.heartRate,
      gear: gear ?? this.gear,
      resistance: resistance ?? this.resistance,
    );
  }
}
