// Utility class for IST timezone conversions
class ISTHelper {
  // Convert UTC DateTime to IST (UTC+5:30)
  static DateTime toIST(DateTime utcTime) {
    return utcTime.add(const Duration(hours: 5, minutes: 30));
  }

  // Get current time in IST
  static DateTime nowIST() {
    return toIST(DateTime.now().toUtc());
  }

  // Parse UTC string and convert to IST
  static DateTime parseUTCtoIST(String utcString) {
    final utcTime = DateTime.parse(utcString);
    return toIST(utcTime);
  }
}
