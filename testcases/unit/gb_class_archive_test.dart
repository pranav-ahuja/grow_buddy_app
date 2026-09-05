/// The .xlsx a deleted class is written to, and read back from on upload.
///
/// This file is the only thing standing between a mistaken delete and a lost
/// class, so what matters here is that a round trip loses nothing — and that a
/// file which is not ours is refused with something a teacher can act on,
/// rather than being half-parsed into a class with missing children in it.
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as
// test code, and this suite lives in testcases/ by request. These members
// are annotated @visibleForTesting and this IS the test using them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassArchive.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

GB_Student _student({
  String studentId = "GB-0001",
  String name = "Aarav Shah",
  GB_StudentContact? mother,
  GB_StudentContact? father,
  GB_StudentContact? guardian,
  String? photoPath,
}) {
  return GB_Student(
    studentId: studentId,
    name: name,
    age: "4",
    gender: "Male",
    address: "12 Patel Nagar, Pune",
    imagePath: kClassAvatarImage,
    photoPath: photoPath,
    mother: mother,
    father: father,
    guardian: guardian,
  );
}

/// Encodes and decodes in one step — the only journey this file ever makes.
GB_ClassArchiveData _roundTrip(String className, List<GB_Student> students) {
  return GB_ClassArchive.decode(
    GB_ClassArchive.encode(className: className, students: students),
  );
}

void main() {
  group("round trip", () {
    test("archive_keeps_the_class_name | The name survives the file", () {
      expect(_roundTrip("Daycare", <GB_Student>[]).className, "Daycare");
    });

    test("archive_keeps_an_empty_class | A class with no students is valid", () {
      // A teacher can delete a class they just made. That file still has to
      // restore, rather than being rejected as having no student list.
      expect(_roundTrip("Daycare", <GB_Student>[]).students, isEmpty);
    });

    test("archive_keeps_every_student | None are dropped", () {
      final GB_ClassArchiveData restored = _roundTrip("Daycare", <GB_Student>[
        _student(studentId: "GB-0001", name: "First"),
        _student(studentId: "GB-0002", name: "Second"),
        _student(studentId: "GB-0003", name: "Third"),
      ]);

      expect(restored.students.map((GB_Student s) => s.name),
          <String>["First", "Second", "Third"]);
    });

    test("archive_keeps_the_student_id | Ids come back unchanged", () {
      // The id is on paper registers, so a restore that renumbered the class
      // would quietly break every record written against it.
      final GB_ClassArchiveData restored =
          _roundTrip("Daycare", <GB_Student>[_student(studentId: "GB-0042")]);

      expect(restored.students.single.studentId, "GB-0042");
    });

    test("archive_keeps_the_core_fields | Age, gender, and address survive", () {
      final GB_Student restored =
          _roundTrip("Daycare", <GB_Student>[_student()]).students.single;

      expect(restored.age, "4");
      expect(restored.gender, "Male");
      expect(restored.address, "12 Patel Nagar, Pune");
    });

    test("archive_keeps_the_parents | Both contact blocks survive", () {
      final GB_Student restored = _roundTrip("Daycare", <GB_Student>[
        _student(
          mother: const GB_StudentContact(
            name: "Meera Shah",
            mobile: "9876543210",
            email: "meera@example.com",
          ),
          father: const GB_StudentContact(
            name: "Raj Shah",
            mobile: "9876500000",
          ),
        ),
      ]).students.single;

      expect(restored.mother!.name, "Meera Shah");
      expect(restored.mother!.mobile, "9876543210");
      expect(restored.mother!.email, "meera@example.com");
      expect(restored.father!.name, "Raj Shah");
    });

    test("archive_keeps_the_guardian | Relation and address survive too", () {
      final GB_Student restored = _roundTrip("Daycare", <GB_Student>[
        _student(
          guardian: const GB_StudentContact(
            name: "Anil Shah",
            mobile: "9000000000",
            address: "8 Hill Road",
            relation: "Uncle",
          ),
        ),
      ]).students.single;

      expect(restored.guardian!.relation, "Uncle");
      expect(restored.guardian!.address, "8 Hill Road");
    });

    test("archive_leaves_empty_contacts_null | No blank parent rows", () {
      // An all-empty contact would render as an empty "Mother" block on the
      // profile, which reads as missing data rather than as data not collected.
      final GB_Student restored =
          _roundTrip("Daycare", <GB_Student>[_student()]).students.single;

      expect(restored.mother, isNull);
      expect(restored.father, isNull);
      expect(restored.guardian, isNull);
    });

    test("archive_keeps_a_long_mobile_as_typed | No scientific notation", () {
      // The reason every cell is written as text: a number-typed cell brings a
      // long mobile back as 9.198765e+11.
      final GB_Student restored = _roundTrip("Daycare", <GB_Student>[
        _student(mother: const GB_StudentContact(mobile: "919876543210")),
      ]).students.single;

      expect(restored.mother!.mobile, "919876543210");
    });

    test("archive_treats_a_missing_photo_as_null | Not an empty path", () {
      final GB_Student restored =
          _roundTrip("Daycare", <GB_Student>[_student()]).students.single;

      expect(restored.photoPath, isNull);
    });

    test("archive_keeps_a_photo_path | A picked photo travels", () {
      final GB_Student restored = _roundTrip("Daycare", <GB_Student>[
        _student(photoPath: "/data/user/0/pics/aarav.jpg"),
      ]).students.single;

      expect(restored.photoPath, "/data/user/0/pics/aarav.jpg");
    });
  });

  group("rejecting files that are not ours", () {
    test("archive_rejects_junk | A non-spreadsheet is refused", () {
      expect(
        () => GB_ClassArchive.decode(
          Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        ),
        throwsA(isA<GB_ClassArchiveException>()),
      );
    });

    test("archive_rejects_an_empty_file | Zero bytes are refused", () {
      expect(
        () => GB_ClassArchive.decode(Uint8List(0)),
        throwsA(isA<GB_ClassArchiveException>()),
      );
    });
  });

  group("file name", () {
    test("archive_file_name_carries_the_class | It is findable later", () {
      final String name = GB_ClassArchive.fileNameFor(
        "Daycare",
        on: DateTime(2026, 9, 5),
      );

      expect(name, "Daycare_class_2026-09-05.xlsx");
    });

    test("archive_file_name_is_path_safe | A slash cannot become a folder", () {
      // "Grade 1/2" would otherwise produce a path with a directory separator
      // in the middle of the file name.
      final String name = GB_ClassArchive.fileNameFor(
        "Grade 1/2",
        on: DateTime(2026, 9, 5),
      );

      expect(name, "Grade_12_class_2026-09-05.xlsx");
    });

    test("archive_file_name_survives_a_nameless_class | Never bare .xlsx", () {
      final String name =
          GB_ClassArchive.fileNameFor("***", on: DateTime(2026, 9, 5));

      expect(name, "class_class_2026-09-05.xlsx");
    });
  });

  group("student id serials", () {
    test("archive_reads_a_serial | GB-0007 is 7", () {
      expect(GB_ClassArchive.serialInStudentId("GB-0007"), 7);
    });

    test("archive_ignores_a_foreign_id | Not ours means no serial", () {
      expect(GB_ClassArchive.serialInStudentId("X-1"), isNull);
      expect(GB_ClassArchive.serialInStudentId(""), isNull);
    });
  });

  group("restoring into the store", () {
    setUp(GB_StudentStore.resetForTest);
    tearDown(GB_StudentStore.resetForTest);

    test("restore_files_students_under_the_class | They land in the roster", () {
      GB_StudentStore.restoreStudents(
        <GB_Student>[_student(studentId: "GB-0001")],
        classId: 9,
      );

      expect(GB_StudentStore.countInClass(9), 1);
    });

    test("restore_keeps_ids_and_advances_the_counter | No id is reissued", () {
      // The counter has to jump past the restored ids, or the next child
      // registered would be handed GB-0001 a second time.
      GB_StudentStore.restoreStudents(
        <GB_Student>[
          _student(studentId: "GB-0001"),
          _student(studentId: "GB-0009", name: "Ninth"),
        ],
        classId: 9,
      );

      final GB_Student next = GB_StudentStore.addStudent(
        name: "New",
        age: "5",
        gender: "Female",
        address: "1 Road",
        classId: 9,
      );

      expect(next.studentId, "GB-0010");
    });

    test("restore_gives_fresh_internal_ids | The list keys stay unique", () {
      GB_StudentStore.restoreStudents(
        <GB_Student>[
          _student(studentId: "GB-0001", name: "First"),
          _student(studentId: "GB-0002", name: "Second"),
        ],
        classId: 9,
      );

      final List<int> ids = GB_StudentStore.students.value
          .map((GB_Student student) => student.id)
          .toList();

      expect(ids.toSet(), hasLength(ids.length));
    });
  });
}
