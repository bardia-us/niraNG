import 'package:flutter_test/flutter_test.dart';
import 'package:nirang/core/widgets/optical_capture_phase.dart';

void main() {
  test(
    'failed/nested scene recording cannot leak exclusion into visible scene',
    () {
      expect(OpticalCapturePhase.isActive, isFalse);
      OpticalCapturePhase.record(() {
        expect(OpticalCapturePhase.isActive, isTrue);
        expect(
          () => OpticalCapturePhase.record(
            () => throw StateError('capture failed'),
          ),
          throwsStateError,
        );
        expect(OpticalCapturePhase.isActive, isTrue);
      });
      expect(OpticalCapturePhase.isActive, isFalse);
      expect(
        () => OpticalCapturePhase.record(
          () => throw StateError('capture failed'),
        ),
        throwsStateError,
      );
      expect(OpticalCapturePhase.isActive, isFalse);
    },
  );
}
