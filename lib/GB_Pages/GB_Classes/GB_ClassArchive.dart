import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// The spreadsheet a class is written to when it is deleted, and read back from
/// when the teacher uploads it into "Add a class".
///
/// Deleting a class throws away every student in it, so the delete is only
/// allowed to happen once this file exists — the archive is what makes the
/// action undoable rather than final.
///
/// Everything is written as text, including the ages and phone numbers. They
/// are all [String] on the model, and a number-typed cell would come back as
/// `4.0` or in scientific notation for a long mobile number, which is a
/// corrupted restore rather than a tidier file.
///
/// The two halves are split deliberately: [encode] and [decode] are pure and
/// unit-testable, while [GB_ClassArchiveFile] holds the platform file dialogs.

/// Raised when an uploaded file is not a class archive, or is one this build
/// cannot read.
class GB_ClassArchiveException implements Exception {
  const GB_ClassArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What [GB_ClassArchive.decode] recovers from a file.
class GB_ClassArchiveData {
  const GB_ClassArchiveData({
    required this.className,
    required this.students,
  });

  /// The name the class had when it was archived. Offered as a starting point
  /// on the upload form; the teacher can still name the restored class
  /// something else.
  final String className;

  /// The students, carrying their original student ids. Their `classId` is
  /// null — the restore assigns it once the new class exists.
  final List<GB_Student> students;
}

class GB_ClassArchive {
  const GB_ClassArchive._();

  /// Written into the Class sheet so a file from an incompatible build can be
  /// rejected with a clear message instead of parsed into nonsense.
  ///
  /// v2 carries a date of birth where v1 carried an age. A v1 file cannot be
  /// restored: an age cannot be turned back into the date the server requires.
  static const String formatVersion = "grow-buddy-class-v2";
  static const String _formatVersion1 = "grow-buddy-class-v1";

  static const String classSheetName = "Class";
  static const String studentsSheetName = "Students";

  /// The Students sheet's header row.
  ///
  /// [decode] looks columns up by these names rather than by position, so a
  /// column added here later does not invalidate files written today.
  ///
  /// "Roll Number" is written for the teacher reading the spreadsheet and
  /// ignored on restore — the server works roll numbers out from the student
  /// ids, which a restore keeps, so the order comes back as it was.
  static const List<String> studentColumns = <String>[
    "Student ID",
    "Roll Number",
    "Name",
    "Date of Birth",
    "Gender",
    "Address",
    "Photo",
    "Mother Name",
    "Mother Mobile",
    "Mother Email",
    "Father Name",
    "Father Mobile",
    "Father Email",
    "Guardian Name",
    "Guardian Relation",
    "Guardian Mobile",
    "Guardian Address",
  ];

  /// The workbook for one class: a Class sheet, a Students sheet, and one sheet
  /// per tab the class screen shows.
  static Uint8List encode({
    required String className,
    required List<GB_Student> students,
    DateTime? exportedAt,
  }) {
    final Excel workbook = Excel.createExcel();

    _writeClassSheet(
      workbook,
      className: className,
      studentCount: students.length,
      exportedAt: exportedAt ?? DateTime.now(),
    );
    _writeStudentsSheet(workbook, students);
    _writeFeatureSheets(workbook);

    // Deleted last: createExcel() seeds a "Sheet1" that would otherwise ship as
    // an empty first tab, and the package will not delete the only sheet in a
    // workbook, so ours have to exist first.
    workbook.delete("Sheet1");

    final List<int>? bytes = workbook.encode();
    if (bytes == null) {
      throw const GB_ClassArchiveException("Could not build the class file");
    }
    return Uint8List.fromList(bytes);
  }

  static void _writeClassSheet(
    Excel workbook, {
    required String className,
    required int studentCount,
    required DateTime exportedAt,
  }) {
    final Sheet sheet = workbook[classSheetName];
    sheet.appendRow(_textRow(<String>["Field", "Value"]));
    sheet.appendRow(_textRow(<String>["Class name", className]));
    sheet.appendRow(_textRow(<String>["Students", "$studentCount"]));
    sheet.appendRow(
      _textRow(<String>["Exported at", exportedAt.toIso8601String()]),
    );
    sheet.appendRow(_textRow(<String>["Format", formatVersion]));
  }

  static void _writeStudentsSheet(Excel workbook, List<GB_Student> students) {
    final Sheet sheet = workbook[studentsSheetName];
    sheet.appendRow(_textRow(studentColumns));

    for (final GB_Student student in students) {
      final GB_StudentContact mother =
          student.mother ?? const GB_StudentContact();
      final GB_StudentContact father =
          student.father ?? const GB_StudentContact();
      final GB_StudentContact guardian =
          student.guardian ?? const GB_StudentContact();

      sheet.appendRow(_textRow(<String>[
        student.studentId,
        student.rollNumber?.toString() ?? "",
        student.name,
        GB_ClassApi.formatDate(student.dateOfBirth),
        student.gender,
        student.address,
        // The photo travels as the path it had on this device. A restore onto
        // another device will not find it, which is why the card falls back to
        // the stock asset rather than assuming the file is there.
        student.photoPath ?? "",
        mother.name,
        mother.mobile,
        mother.email,
        father.name,
        father.mobile,
        father.email,
        guardian.name,
        guardian.relation,
        guardian.mobile,
        guardian.address,
      ]));
    }
  }

  /// One sheet per tab on the class screen.
  ///
  /// They carry no rows because the app stores nothing for those tabs yet —
  /// assignments, grades, and the rest are placeholder screens. The sheets are
  /// written anyway so the archive mirrors the class the teacher sees, and so
  /// there is somewhere obvious for that data to go the day it exists.
  static void _writeFeatureSheets(Excel workbook) {
    for (final GB_ClassFeature feature in GB_ClassFeature.all) {
      final Sheet sheet = workbook[feature.label];
      sheet.appendRow(_textRow(<String>[feature.label]));
      sheet.appendRow(_textRow(<String>[
        "This tab has no saved data yet, so nothing was exported for it. "
            "Rows added here by hand are ignored when the class is restored.",
      ]));
    }
  }

  /// Reads a workbook produced by [encode] back into a class and its students.
  ///
  /// Throws [GB_ClassArchiveException] with something a teacher can act on
  /// whenever the file is not one of ours — the upload form shows the message
  /// verbatim.
  static GB_ClassArchiveData decode(Uint8List bytes) {
    late final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (_) {
      // Anything from a PDF to a truncated download lands here. The cause is
      // never useful to the teacher; that it is not a class file is.
      throw const GB_ClassArchiveException(
        "That file could not be read as a class file",
      );
    }

    final Sheet? classSheet = workbook.tables[classSheetName];
    final Sheet? studentsSheet = workbook.tables[studentsSheetName];
    if (classSheet == null || studentsSheet == null) {
      throw const GB_ClassArchiveException(
        "That spreadsheet is not a Grow Buddy class file",
      );
    }

    final Map<String, String> classFields = _readClassFields(classSheet);

    final String? format = classFields["Format"];
    if (format == _formatVersion1) {
      throw const GB_ClassArchiveException(
        "That class file is from an older version of the app. It records "
        "students' ages rather than their dates of birth, so it can't be "
        "restored.",
      );
    }
    if (format != null && format != formatVersion) {
      throw const GB_ClassArchiveException(
        "That class file was made by a newer version of the app",
      );
    }

    return GB_ClassArchiveData(
      className: classFields["Class name"] ?? "",
      students: _readStudents(studentsSheet),
    );
  }

  /// The Class sheet as a field/value map, skipping its header row.
  static Map<String, String> _readClassFields(Sheet sheet) {
    final Map<String, String> fields = <String, String>{};

    for (final List<Data?> row in sheet.rows.skip(1)) {
      final String field = _cellText(row, 0);
      if (field.isEmpty) continue;
      fields[field] = _cellText(row, 1);
    }

    return fields;
  }

  static List<GB_Student> _readStudents(Sheet sheet) {
    if (sheet.rows.isEmpty) return <GB_Student>[];

    // Column positions come from the file's own header, so a file written by a
    // build with fewer columns still restores what it does carry.
    final Map<String, int> columns = <String, int>{};
    final List<Data?> header = sheet.rows.first;
    for (int index = 0; index < header.length; index++) {
      final String name = _cellText(header, index);
      if (name.isNotEmpty) columns[name] = index;
    }

    if (!columns.containsKey("Name")) {
      throw const GB_ClassArchiveException(
        "That class file has no student list",
      );
    }

    final List<GB_Student> students = <GB_Student>[];

    for (final List<Data?> row in sheet.rows.skip(1)) {
      String read(String column) {
        final int? index = columns[column];
        return index == null ? "" : _cellText(row, index);
      }

      final String name = read("Name");
      // Trailing blank rows are normal in a spreadsheet a teacher has opened
      // and saved; a student with no name is not a student.
      if (name.isEmpty) continue;

      final String photo = read("Photo");

      // Checked here rather than left to the server: a restore is all or
      // nothing, and a message naming the student is something the teacher can
      // fix in the spreadsheet, where a 422 from the server is not.
      final DateTime? dateOfBirth = DateTime.tryParse(read("Date of Birth"));
      if (dateOfBirth == null) {
        throw GB_ClassArchiveException(
          "$name has no valid date of birth in that class file. Dates are "
          "written like 2021-04-12.",
        );
      }

      students.add(
        GB_Student(
          studentId: read("Student ID"),
          name: name,
          dateOfBirth: dateOfBirth,
          gender: read("Gender"),
          address: read("Address"),
          photoPath: photo.isEmpty ? null : photo,
          imagePath: kClassAvatarImage,
          mother: _contactOrNull(
            name: read("Mother Name"),
            mobile: read("Mother Mobile"),
            email: read("Mother Email"),
          ),
          father: _contactOrNull(
            name: read("Father Name"),
            mobile: read("Father Mobile"),
            email: read("Father Email"),
          ),
          guardian: _contactOrNull(
            name: read("Guardian Name"),
            mobile: read("Guardian Mobile"),
            address: read("Guardian Address"),
            relation: read("Guardian Relation"),
          ),
        ),
      );
    }

    return students;
  }

  static GB_StudentContact? _contactOrNull({
    String name = "",
    String mobile = "",
    String email = "",
    String address = "",
    String relation = "",
  }) {
    final GB_StudentContact contact = GB_StudentContact(
      name: name,
      mobile: mobile,
      email: email,
      address: address,
      relation: relation,
    );
    return contact.isEmpty ? null : contact;
  }

  static List<CellValue?> _textRow(List<String> values) {
    return values.map<CellValue?>((String value) => TextCellValue(value)).toList();
  }

  /// One cell as trimmed text, treating a missing cell and an empty one alike.
  static String _cellText(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return "";
    final CellValue? value = row[index]?.value;
    return value == null ? "" : value.toString().trim();
  }

  /// The name the archive is offered under, e.g. "Daycare_class_2026-09-05.xlsx".
  ///
  /// The class name is stripped of anything a filesystem objects to rather than
  /// passed through — a class called "Grade 1/2" would otherwise produce a path
  /// with a directory separator in the middle of it.
  static String fileNameFor(String className, {DateTime? on}) {
    final DateTime date = on ?? DateTime.now();
    final String stamp = "${date.year.toString().padLeft(4, "0")}-"
        "${date.month.toString().padLeft(2, "0")}-"
        "${date.day.toString().padLeft(2, "0")}";

    final String safeName = className
        .trim()
        .replaceAll(RegExp(r"[^A-Za-z0-9 _-]"), "")
        .replaceAll(RegExp(r"\s+"), "_");

    return "${safeName.isEmpty ? "class" : safeName}_class_$stamp.xlsx";
  }
}
