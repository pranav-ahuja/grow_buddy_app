/// GB_ClassStore is the only place classes are mutated, and the dashboard
/// repaints off its ValueNotifier.
library;

// The analyzer only treats test/, integration_test/ and test_driver/ as
// test code, and this suite lives in testcases/ by request. These members
// are annotated @visibleForTesting and this IS the test using them.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter_test/flutter_test.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';

void main() {
  setUp(GB_ClassStore.resetForTest);
  tearDown(GB_ClassStore.resetForTest);

  test("classes_seeded | The five designed classes are there on first run", () {
    expect(GB_ClassStore.classes.value, hasLength(5));
    expect(
      GB_ClassStore.classes.value.map((GB_ClassInfo c) => c.name),
      ["Daycare", "Playgroup", "Pre Nursery", "Nursery", "KG"],
    );
  });

  test("class_add_appends | Adding a class returns it and grows the list", () {
    final GB_ClassInfo created = GB_ClassStore.addClass(name: "Grade 1");

    expect(created.name, "Grade 1");
    expect(GB_ClassStore.classes.value, hasLength(6));
    expect(GB_ClassStore.classes.value.last.name, "Grade 1");
  });

  test("class_add_trims_name | Surrounding spaces are stripped", () {
    expect(GB_ClassStore.addClass(name: "  Grade 2  ").name, "Grade 2");
  });

  test("class_ids_never_collide | A new class cannot reuse a seeded id", () {
    final GB_ClassInfo created = GB_ClassStore.addClass(name: "Grade 3");
    final Set<int> ids =
        GB_ClassStore.classes.value.map((GB_ClassInfo c) => c.id).toSet();

    expect(ids, hasLength(GB_ClassStore.classes.value.length));
    expect(created.id, greaterThanOrEqualTo(5));
  });

  test("class_palette_cycles | The sixth class reuses the first tint", () {
    // Without the cycle a sixth class would index past the palette and either
    // crash or arrive uncoloured, which became reachable the moment teachers
    // could add their own classes.
    final GB_ClassInfo sixth = GB_ClassStore.addClass(name: "Grade 4");

    expect(sixth.fillColor, GB_ClassPalette.fillAt(0));
    expect(sixth.borderColor, GB_ClassPalette.borderAt(0));
  });

  test("class_name_exists_ignores_case | Duplicate detection is forgiving", () {
    expect(GB_ClassStore.nameExists("nursery"), isTrue);
    expect(GB_ClassStore.nameExists("  NURSERY  "), isTrue);
    expect(GB_ClassStore.nameExists("Grade 9"), isFalse);
  });

  test("class_remove | Removing drops exactly one class", () {
    GB_ClassStore.removeClass(0);

    expect(GB_ClassStore.classes.value, hasLength(4));
    expect(
      GB_ClassStore.classes.value.any((GB_ClassInfo c) => c.name == "Daycare"),
      isFalse,
    );
  });

  test("class_notifies_listeners | Adding assigns a new list so listeners fire",
      () {
    // The store never mutates in place: ValueNotifier compares with ==, so an
    // in-place add would leave the identical List instance in the field and no
    // listener would ever be told. Asserting on identity is asserting on the
    // thing that makes the dashboard repaint.
    final List<GB_ClassInfo> before = GB_ClassStore.classes.value;
    int notifications = 0;
    void listener() => notifications++;
    GB_ClassStore.classes.addListener(listener);
    addTearDown(() => GB_ClassStore.classes.removeListener(listener));

    GB_ClassStore.addClass(name: "Grade 5");

    expect(notifications, 1);
    expect(identical(GB_ClassStore.classes.value, before), isFalse);
  });

  test("class_reset_restores_seed | resetForTest undoes everything", () {
    GB_ClassStore.addClass(name: "Temp");
    GB_ClassStore.resetForTest();

    expect(GB_ClassStore.classes.value, hasLength(5));
    expect(GB_ClassStore.nameExists("Temp"), isFalse);
  });
}
