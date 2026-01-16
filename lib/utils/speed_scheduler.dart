import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nadekodon/utils/settings.dart';

enum SpeedMode { fixed, scheduled }

class ScheduleRule {
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double speedLimit; // MB/s

  ScheduleRule({
    required this.startTime,
    required this.endTime,
    required this.speedLimit,
  });

  Map<String, dynamic> toJson() => {
    'start_hour': startTime.hour,
    'start_minute': startTime.minute,
    'end_hour': endTime.hour,
    'end_minute': endTime.minute,
    'speed_limit': speedLimit,
  };

  factory ScheduleRule.fromJson(Map<String, dynamic> json) {
    return ScheduleRule(
      startTime: TimeOfDay(
        hour: json['start_hour'],
        minute: json['start_minute'],
      ),
      endTime: TimeOfDay(hour: json['end_hour'], minute: json['end_minute']),
      speedLimit: (json['speed_limit'] as num).toDouble(),
    );
  }

  bool isTimeInSpan(TimeOfDay now) {
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    final nowMinutes = now.hour * 60 + now.minute;

    if (startMinutes <= endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    } else {
      // Span crosses midnight
      return nowMinutes >= startMinutes || nowMinutes < endMinutes;
    }
  }
}

class SpeedScheduler {
  static Timer? _timer;
  static bool _isActive = false;
  static double? _lastSentSpeed;
  static final currentSpeed = ValueNotifier<double>(0.0);

  static void init() {
    _isActive = true;

    // Determine initial speed without sending signal yet.
    // main.dart's sendAllSettings() will handle the first signal.
    double targetSpeed;
    if (SettingsManager.speedMode.value == SpeedMode.fixed) {
      targetSpeed = SettingsManager.speedLimit.value;
    } else {
      final now = TimeOfDay.now();
      double? scheduledSpeed;
      for (final rule in SettingsManager.speedSchedule.value) {
        if (rule.isTimeInSpan(now)) {
          scheduledSpeed = rule.speedLimit;
          break;
        }
      }
      targetSpeed = scheduledSpeed ?? 0.0;
    }

    _lastSentSpeed = targetSpeed;
    currentSpeed.value = targetSpeed;

    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndApply();
    });

    SettingsManager.speedMode.addListener(_onSettingsChanged);
    SettingsManager.speedSchedule.addListener(_onSettingsChanged);

    // Also listen to speedLimit change to update _lastSentSpeed if in Fixed mode
    SettingsManager.speedLimit.addListener(_onFixedSpeedChanged);
  }

  static void dispose() {
    _isActive = false;
    _timer?.cancel();
    SettingsManager.speedMode.removeListener(_onSettingsChanged);
    SettingsManager.speedSchedule.removeListener(_onSettingsChanged);
    SettingsManager.speedLimit.removeListener(_onFixedSpeedChanged);
    currentSpeed.dispose();
  }

  static void _onSettingsChanged() {
    _lastSentSpeed = null;
    _checkAndApply();
  }

  static void _onFixedSpeedChanged() {
    if (SettingsManager.speedMode.value == SpeedMode.fixed) {
      _lastSentSpeed = SettingsManager.speedLimit.value;
      currentSpeed.value = SettingsManager.speedLimit.value;
    }
  }

  static void _checkAndApply() {
    if (!_isActive) return;

    if (SettingsManager.speedMode.value == SpeedMode.fixed) {
      final fixedSpeed = SettingsManager.speedLimit.value;
      if (_lastSentSpeed != fixedSpeed) {
        SettingsManager.sendSpeedLimit(fixedSpeed);
        _lastSentSpeed = fixedSpeed;
      }
      // Also update currentSpeed for UI
      if (currentSpeed.value != fixedSpeed) {
        currentSpeed.value = fixedSpeed;
      }
    } else {
      final now = TimeOfDay.now();
      double? scheduledSpeed;

      for (final rule in SettingsManager.speedSchedule.value) {
        if (rule.isTimeInSpan(now)) {
          scheduledSpeed = rule.speedLimit;
          break;
        }
      }

      final targetSpeed = scheduledSpeed ?? 0.0;
      if (_lastSentSpeed != targetSpeed) {
        SettingsManager.sendSpeedLimit(targetSpeed);
        _lastSentSpeed = targetSpeed;
      }
      // Update currentSpeed for UI
      if (currentSpeed.value != targetSpeed) {
        currentSpeed.value = targetSpeed;
      }
    }
  }
}
