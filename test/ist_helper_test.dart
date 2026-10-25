import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendance_app/utils/ist_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ISTHelper.initialize();
  });

  group('ISTHelper Date and Time formatting', () {
    final testDate = DateTime(2026, 2, 28, 14, 30, 0);

    test('Formats date as DD/MM/YYYY', () async {
      await ISTHelper.setFormatSettings('DD/MM/YYYY', '12h');
      expect(ISTHelper.formatDate(testDate), '28/02/2026');
      expect(ISTHelper.formatDate(testDate, omitYear: true), '28/02');
      expect(ISTHelper.formatDate('2026-02-28'), '28/02/2026');
    });

    test('Formats date as DD-MM-YYYY', () async {
      await ISTHelper.setFormatSettings('DD-MM-YYYY', '12h');
      expect(ISTHelper.formatDate(testDate), '28-02-2026');
      expect(ISTHelper.formatDate(testDate, omitYear: true), '28-02');
    });

    test('Formats date as MM/DD/YYYY', () async {
      await ISTHelper.setFormatSettings('MM/DD/YYYY', '12h');
      expect(ISTHelper.formatDate(testDate), '02/28/2026');
      expect(ISTHelper.formatDate(testDate, omitYear: true), '02/28');
    });

    test('Formats date as MM-DD-YYYY', () async {
      await ISTHelper.setFormatSettings('MM-DD-YYYY', '12h');
      expect(ISTHelper.formatDate(testDate), '02-28-2026');
      expect(ISTHelper.formatDate(testDate, omitYear: true), '02-28');
    });

    test('Formats date as YYYY-MM-DD', () async {
      await ISTHelper.setFormatSettings('YYYY-MM-DD', '12h');
      expect(ISTHelper.formatDate(testDate), '2026-02-28');
      expect(ISTHelper.formatDate(testDate, omitYear: true), '02-28');
    });

    test('Formats date as MMM DD, YYYY', () async {
      await ISTHelper.setFormatSettings('MMM DD, YYYY', '12h');
      expect(ISTHelper.formatDate(testDate), 'Feb 28, 2026');
      expect(ISTHelper.formatDate(testDate, omitYear: true), 'Feb 28');
    });

    test('Formats 12h time correctly (padded hours)', () async {
      await ISTHelper.setFormatSettings('DD/MM/YYYY', '12h');
      expect(ISTHelper.formatTime(DateTime(2026, 2, 28, 9, 30)), '09:30 AM');
      expect(ISTHelper.formatTime(DateTime(2026, 2, 28, 14, 30)), '02:30 PM');
      expect(ISTHelper.formatTime(const TimeOfDay(hour: 9, minute: 30)), '09:30 AM');
      expect(ISTHelper.formatTime('09:30:00'), '09:30 AM');
      expect(ISTHelper.formatTime('14:30:00'), '02:30 PM');
    });

    test('Formats 24h time correctly', () async {
      await ISTHelper.setFormatSettings('DD/MM/YYYY', '24h');
      expect(ISTHelper.formatTime(DateTime(2026, 2, 28, 9, 30)), '09:30');
      expect(ISTHelper.formatTime(DateTime(2026, 2, 28, 14, 30)), '14:30');
      expect(ISTHelper.formatTime(const TimeOfDay(hour: 14, minute: 30)), '14:30');
      expect(ISTHelper.formatTime('09:30:00'), '09:30');
      expect(ISTHelper.formatTime('14:30:00'), '14:30');
    });

    test('Formats formatTimeRange and formatDateTime', () async {
      await ISTHelper.setFormatSettings('DD/MM/YYYY', '12h');
      expect(ISTHelper.formatTimeRange('09:30:00', '18:30:00'), '09:30 AM – 06:30 PM');
      expect(ISTHelper.formatDateTime(testDate), '28/02/2026 02:30 PM');
    });
  });
}
