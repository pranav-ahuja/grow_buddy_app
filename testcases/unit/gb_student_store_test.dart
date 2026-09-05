/// GB_StudentStore backs the class tiles' counts and the class screen roster.
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as
// test code, and this suite lives in testcases/ by request. These members
// are annotated @visibleForTesting and this IS the test using them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';

GB_Student _add({String name = "Aarav", int? classId}) {
  return GB_StudentStore.addStudent(
    name: name,
    age: "4",
    gender: "Male",
    address: "12 Park Road",
    classId: classId,
  );
}

void main() {
  setUp(GB_StudentStore.resetForTest);
  tearDown(GB_StudentStore.resetForTest);

  test("students_start_empty | A new teacher has no students", () {
    // Unlike classes, an empty roster is the truth rather than a missing seed.
    expect(GB_StudentStore.students.value, isEmpty);
  });

  test("student_ids_are_serial | Ids run GB-0001, GB-0002", () {
    expect(_add(name: "First").studentId, "GB-0001");
    expect(_add(name: "Second").studentId, "GB-0002");
  });

  test("student_id_is_padded | formatStudentId pads to four digits", () {
    expect(GB_StudentStore.formatStudentId(7), "GB-0007");
    expect(GB_StudentStore.formatStudentId(1234), "GB-1234");
  });

  test("student_serial_is_not_recycled | A removed id is never reissued", () {
    // These numbers go on registers and report cards, so reissuing one would
    // make two different children share an id in someone's records.
    final GB_Student first = _add(name: "First");
    GB_StudentStore.removeStudent(first.id);

    expect(_add(name: "Second").studentId, "GB-0002");
  });

  test("students_filter_by_class | inClass returns only that class", () {
    _add(name: "In One", classId: 1);
    _add(name: "In Two", classId: 2);
    _add(name: "In One Again", classId: 1);

    expect(
      GB_StudentStore.inClass(1).map((GB_Student s) => s.name),
      ["In One", "In One Again"],
    );
  });

  test("students_count_by_class | countInClass is what the tile shows", () {
    _add(classId: 3);
    _add(classId: 3);
    _add(classId: 4);

    expect(GB_StudentStore.countInClass(3), 2);
    expect(GB_StudentStore.countInClass(4), 1);
    expect(GB_StudentStore.countInClass(99), 0);
  });

  test("student_without_class | A student can be registered with no class", () {
    expect(_add().classId, isNull);
    expect(GB_StudentStore.countInClass(1), 0);
  });

  test("student_trims_fields | Surrounding spaces are stripped", () {
    final GB_Student created = GB_StudentStore.addStudent(
      name: "  Aarav  ",
      age: " 4 ",
      gender: "Male",
      address: "  12 Park Road  ",
    );

    expect(created.name, "Aarav");
    expect(created.age, "4");
    expect(created.address, "12 Park Road");
  });

  test("students_notify_listeners | Registering assigns a new list", () {
    final List<GB_Student> before = GB_StudentStore.students.value;
    int notifications = 0;
    void listener() => notifications++;
    GB_StudentStore.students.addListener(listener);
    addTearDown(() => GB_StudentStore.students.removeListener(listener));

    _add();

    expect(notifications, 1);
    expect(identical(GB_StudentStore.students.value, before), isFalse);
  });

  test("student_reset_restores_counters | resetForTest rewinds the serial", () {
    _add();
    _add();
    GB_StudentStore.resetForTest();

    expect(GB_StudentStore.students.value, isEmpty);
    expect(_add().studentId, "GB-0001");
  });
}
