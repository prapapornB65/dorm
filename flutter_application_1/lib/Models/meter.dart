class Meter {
  final int id;
  final String deviceId;
  final String? name;
  final String? roomNo;
  final bool isCut;
  final double creditKwh;
  final double? thresholdLow;
  final double? thresholdCritical;

  Meter({
    required this.id,
    required this.deviceId,
    this.name,
    this.roomNo,
    required this.isCut,
    required this.creditKwh,
    this.thresholdLow,
    this.thresholdCritical,
  });

  factory Meter.fromJson(Map<String, dynamic> j) => Meter(
    id: j['id'],
    deviceId: j['deviceId'] ?? j['DeviceID'],
    name: j['name'],
    roomNo: j['roomNo'],
    isCut: j['is_cut'] ?? j['isCut'] ?? false,
    creditKwh: (j['creditKwh'] ?? j['credit_kwh'] ?? 0).toDouble(),
    thresholdLow: (j['threshold_low_kwh'] ?? j['thresholdLow'])?.toDouble(),
    thresholdCritical: (j['threshold_critical_kwh'] ?? j['thresholdCritical'])?.toDouble(),
  );
}
