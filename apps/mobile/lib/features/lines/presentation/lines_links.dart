// Where Lines' taps go (specs/014-m09-lines-vehicles, contracts/lines.md
// "Actions"), by the ids' wire names.
import 'package:content_models/content_models.dart';
import 'package:wassal/core/economy/domain/wire.dart';
import 'package:wassal/features/trip/domain/line_ids.dart';

/// `/lines/<line>`: a line's details.
String lineLocation(LineId line) => '/lines/${toGlossaryLine(line).wireName}';

/// `/lines/vehicle/<vehicle>`: a vehicle's sheet.
String vehicleLocation(VehicleId vehicle) =>
    '/lines/vehicle/${vehicleWire[vehicle]}';
