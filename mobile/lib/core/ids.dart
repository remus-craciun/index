import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Client-generated, time-ordered row ID, so rows created offline keep
/// their identity when synced.
String newId() => _uuid.v7();
