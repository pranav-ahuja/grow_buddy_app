import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentFormFields.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Services/GB_ApiClient.dart';
import 'package:grow_buddy_app/GB_Services/GB_ClassApi.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Globals.dart';
import 'package:image_picker/image_picker.dart';

/// What the photo chooser came back with. An enum rather than an [ImageSource]
/// because "remove the photo I already picked" is a third answer that
/// ImageSource has no value for.
enum _PhotoAction { camera, gallery, remove }

/// The "register a new student" form, shown as a bottom sheet from the
/// dashboard's floating action button.
///
/// Layout follows the Figma frame `360-44515`: a gold-edged sheet fading from
/// cream to white, a round photo above a stack of outlined fields, and the
/// "Add to Class" pill in the bottom-right corner.
///
/// The design draws five of the fields. The form collects more than that —
/// address, both parents' names and emails, and a guardian block — because a
/// student record needs them; they are grouped under headings so the extra
/// length reads as four short forms rather than one long one. Mandatory: name,
/// date of birth, class, gender, and address.
///
/// Call [show]; it returns the registered student, or null if the teacher
/// backed out, so the caller can react (the dashboard confirms with a snackbar).
///
/// [edit] opens the same form on an existing pupil: prefilled, the class
/// locked, and **Delete** beside **Save**. Saving goes straight in for staff;
/// deleting is a request to the principal from a teacher, as it always was.
class GB_RegisterStudentSheet extends StatefulWidget {
  const GB_RegisterStudentSheet({super.key, this.initialClassId, this.student});

  /// Preselects a class, for when the sheet is opened from inside one. Null
  /// from the dashboard, where no class is in context yet.
  final String? initialClassId;

  /// The pupil being edited, or null when registering a new one.
  final GB_Student? student;

  /// Opens the form on [student]. Returns what the save or delete produced,
  /// or null if the sheet was dismissed.
  static Future<GB_ActionResult?> edit(
    BuildContext context, {
    required GB_Student student,
  }) {
    return showModalBottomSheet<GB_ActionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) =>
          GB_RegisterStudentSheet(student: student),
    );
  }

  static Future<GB_ActionResult?> show(
    BuildContext context, {
    String? initialClassId,
  }) {
    return showModalBottomSheet<GB_ActionResult>(
      context: context,
      // The form is taller than the screen and the keyboard covers half of what
      // is left, so the sheet has to be free to size itself.
      isScrollControlled: true,
      useSafeArea: true,
      // The sheet paints its own gradient and gold edge; a background colour
      // here would sit on top of them as an opaque rectangle.
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => GB_RegisterStudentSheet(
        initialClassId: initialClassId,
      ),
    );
  }

  @override
  State<GB_RegisterStudentSheet> createState() =>
      _GB_RegisterStudentSheetState();
}

class _GB_RegisterStudentSheetState extends State<GB_RegisterStudentSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();

  /// Shows [_dateOfBirth] as text. The field is read-only; the date picker is
  /// the only way to change it, so the text can never be an unparseable date.
  final TextEditingController _dateOfBirthController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  final TextEditingController _motherNameController = TextEditingController();
  final TextEditingController _motherMobileController = TextEditingController();
  final TextEditingController _motherEmailController = TextEditingController();

  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _fatherMobileController = TextEditingController();
  final TextEditingController _fatherEmailController = TextEditingController();

  final TextEditingController _guardianNameController = TextEditingController();
  final TextEditingController _guardianRelationController =
      TextEditingController();
  final TextEditingController _guardianMobileController =
      TextEditingController();
  final TextEditingController _guardianAddressController =
      TextEditingController();

  /// Null until the teacher picks one. Not defaulted to "Male": a default here
  /// is a wrong answer that submits silently, where an empty field asks.
  String? _gender;

  /// Required: a student is always registered into a class. Null only until
  /// the teacher picks one, unless the sheet was opened from inside a class.
  String? _classId;

  /// Null until picked. The age is worked out from it wherever one is shown.
  DateTime? _dateOfBirth;

  String? _photoPath;

  /// Gender is not a [FormField], so its error is tracked by hand and shown
  /// alongside the ones [Form.validate] raises on the text fields.
  String? _genderError;

  /// Blocks a second tap between validating and popping the sheet.
  bool _isSubmitting = false;

  /// Why the last save or delete failed, shown above the buttons. Not a
  /// SnackBar: the sheet is painted over the Scaffold's snack, so one would
  /// be invisible and the button would appear to do nothing.
  String? _submitError;

  void _showSubmitError(GB_ApiException error) {
    setState(() {
      _isSubmitting = false;
      _submitError = error.statusCode == 401
          ? "Your session has expired. Log out from Settings and sign in "
              "again, then retry."
          : error.message;
    });
  }

  static const List<String> _genderOptions = ["Male", "Female"];

  bool get _isEditing => widget.student != null;

  @override
  void initState() {
    super.initState();
    _classId = widget.initialClassId;

    final GB_Student? student = widget.student;
    if (student == null) return;

    _classId = student.classId;
    _nameController.text = student.name;
    _dateOfBirth = student.dateOfBirth;
    _dateOfBirthController.text = _formatDate(student.dateOfBirth);
    _addressController.text = student.address;
    // A restored class file can carry a blank gender; that stays unpicked
    // rather than being guessed.
    _gender = _genderOptions.contains(student.gender) ? student.gender : null;
    _photoPath = student.photoPath;

    final GB_StudentContact mother =
        student.mother ?? const GB_StudentContact();
    _motherNameController.text = mother.name;
    _motherMobileController.text = mother.mobile;
    _motherEmailController.text = mother.email;

    final GB_StudentContact father =
        student.father ?? const GB_StudentContact();
    _fatherNameController.text = father.name;
    _fatherMobileController.text = father.mobile;
    _fatherEmailController.text = father.email;

    final GB_StudentContact guardian =
        student.guardian ?? const GB_StudentContact();
    _guardianNameController.text = guardian.name;
    _guardianRelationController.text = guardian.relation;
    _guardianMobileController.text = guardian.mobile;
    _guardianAddressController.text = guardian.address;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _nameController,
      _dateOfBirthController,
      _addressController,
      _motherNameController,
      _motherMobileController,
      _motherEmailController,
      _fatherNameController,
      _fatherMobileController,
      _fatherEmailController,
      _guardianNameController,
      _guardianRelationController,
      _guardianMobileController,
      _guardianAddressController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------- validation

  String? _validateRequired(String? value, String field) {
    if (value == null || value.trim().isEmpty) return "Enter the $field";
    return null;
  }

  String? _validateDateOfBirth(String? _) {
    return _dateOfBirth == null ? "Pick the date of birth" : null;
  }

  String? _validateClass(String? classId) {
    if (classId != null) return null;
    // An empty dropdown is not something the teacher can fix by looking at it
    // harder, so say what to do instead.
    return GB_ClassStore.classes.value.isEmpty
        ? "Add a class first"
        : "Choose a class";
  }

  String? _validateOptionalEmail(String? value) {
    final String email = (value ?? "").trim();
    if (email.isEmpty) return null;

    // Deliberately loose: the only thing worth catching here is a plainly
    // malformed address, and anything stricter starts rejecting real ones.
    if (!RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$").hasMatch(email)) {
      return "Enter a valid email address";
    }
    return null;
  }

  // ------------------------------------------------------------------- actions

  /// Opens the calendar on the date already picked, or on a typical preschool
  /// age when there is none, so the teacher is not starting from today and
  /// paging back four years.
  Future<void> _pickDateOfBirth() async {
    final DateTime today = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate:
          _dateOfBirth ?? DateTime(today.year - 4, today.month, today.day),
      // Thirty years back matches the widest age the form ever accepted.
      firstDate: DateTime(today.year - 30),
      lastDate: today,
      helpText: "Date of birth",
    );

    if (picked == null || !mounted) return;
    setState(() {
      _dateOfBirth = picked;
      _dateOfBirthController.text = _formatDate(picked);
    });
  }

  static const List<String> _monthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ];

  /// "12 Apr 2021" — day first, and a month name rather than a number, so it
  /// cannot be misread the way 04/12/2021 can.
  static String _formatDate(DateTime date) {
    return "${date.day} ${_monthNames[date.month - 1]} ${date.year}";
  }

  Future<void> _pickPhoto() async {
    final _PhotoAction? action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: kPrimaryColor2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(kClassPanelRadius),
        ),
      ),
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: kHomeAccentColor),
              title: const Text("Take a photo"),
              onTap: () => Navigator.of(context).pop(_PhotoAction.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: kHomeAccentColor),
              title: const Text("Choose from gallery"),
              onTap: () => Navigator.of(context).pop(_PhotoAction.gallery),
            ),
            if (_photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: kHomeSubtitleTextColor),
                title: const Text("Remove photo"),
                onTap: () => Navigator.of(context).pop(_PhotoAction.remove),
              ),
          ],
        ),
      ),
    );

    // Null is a dismissal, which is not the same as choosing "Remove photo" —
    // hence the explicit action rather than an ImageSource that has no value
    // meaning "clear the one already picked".
    if (action == null || !mounted) return;

    if (action == _PhotoAction.remove) {
      setState(() => _photoPath = null);
      return;
    }

    try {
      // Downscaled on the way in: the photo is only ever drawn at 80pt here and
      // 60pt on the class screen's card, and a full-resolution camera capture
      // would be megabytes held for a thumbnail.
      final XFile? picked = await ImagePicker().pickImage(
        source: action == _PhotoAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        maxWidth: 800.0,
        maxHeight: 800.0,
        imageQuality: 85,
      );

      if (picked == null || !mounted) return;
      setState(() => _photoPath = picked.path);
    } on PlatformException {
      // Thrown when the picker is unavailable or permission was refused. The
      // photo is optional, so this is worth saying once and not worth blocking
      // the rest of the form over.
      if (!mounted) return;
      gShowSnack(context, "Couldn't open the photo picker");
    }
  }

  /// Packs one block's fields into a contact, or null when the teacher left the
  /// whole block empty.
  GB_StudentContact? _contactOrNull({
    TextEditingController? name,
    TextEditingController? mobile,
    TextEditingController? email,
    TextEditingController? address,
    TextEditingController? relation,
  }) {
    final GB_StudentContact contact = GB_StudentContact(
      name: name?.text.trim() ?? "",
      mobile: mobile?.text.trim() ?? "",
      email: email?.text.trim() ?? "",
      address: address?.text.trim() ?? "",
      relation: relation?.text.trim() ?? "",
    );

    return contact.isEmpty ? null : contact;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    // Both run before either is checked, so the teacher sees every problem at
    // once rather than fixing the fields and then discovering the gender row.
    final bool fieldsValid = _formKey.currentState?.validate() ?? false;
    final bool genderValid = _gender != null;

    setState(() => _genderError = genderValid ? null : "Select a gender");
    if (!fieldsValid || !genderValid) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    final GB_StudentContact? mother = _contactOrNull(
      name: _motherNameController,
      mobile: _motherMobileController,
      email: _motherEmailController,
    );
    final GB_StudentContact? father = _contactOrNull(
      name: _fatherNameController,
      mobile: _fatherMobileController,
      email: _fatherEmailController,
    );
    final GB_StudentContact? guardian = _contactOrNull(
      name: _guardianNameController,
      mobile: _guardianMobileController,
      address: _guardianAddressController,
      relation: _guardianRelationController,
    );

    try {
      final GB_Student? editing = widget.student;
      if (editing != null) {
        final GB_ActionResult result = await GB_StudentStore.updateStudent(
          GB_Student(
            studentId: editing.studentId,
            name: _nameController.text.trim(),
            dateOfBirth: _dateOfBirth!,
            gender: _gender!,
            address: _addressController.text.trim(),
            classId: editing.classId,
            rollNumber: editing.rollNumber,
            photoPath: _photoPath,
            imagePath: editing.imagePath,
            mother: mother,
            father: father,
            guardian: guardian,
          ),
        );
        if (!mounted) return;
        Navigator.of(context).pop(result);
        return;
      }

      // The server assigns the student id, so it is only known once this
      // returns — which is why the sheet waits rather than closing at once.
      //
      // A teacher's registration goes straight in, as the principal's does,
      // and the principal is notified (since 2026-09-27). The caller still
      // words its confirmation from the result rather than assuming.
      final GB_ActionResult result = await GB_StudentStore.addStudent(
        name: _nameController.text,
        dateOfBirth: _dateOfBirth!,
        gender: _gender!,
        address: _addressController.text,
        classId: _classId!,
        photoPath: _photoPath,
        mother: mother,
        father: father,
        guardian: guardian,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      // The sheet stays open with everything the teacher typed, so a dropped
      // connection costs a retry rather than filling in the whole form again.
      _showSubmitError(error);
    }
  }

  /// Removes the pupil, or asks the principal to.
  ///
  /// Confirmed first, and worded for the role: a principal is about to delete
  /// a child's record and their whole attendance history, with no class file
  /// to bring them back from. A teacher is only about to ask.
  Future<void> _delete() async {
    final GB_Student student = widget.student!;
    if (_isSubmitting) return;

    final bool asksFirst = !gIsPrincipal();
    final String className = GB_ClassStore.classes.value
            .where((GB_ClassInfo item) => item.id == student.classId)
            .map((GB_ClassInfo item) => item.name)
            .firstOrNull ??
        "their class";

    final bool confirmed = await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            backgroundColor: kPrimaryColor2,
            title: Text(
              asksFirst
                  ? "Ask to delete ${student.name}?"
                  : "Delete ${student.name}?",
            ),
            content: Text(
              asksFirst
                  ? "The principal will be asked to approve it. Nothing "
                      "changes until they do."
                  : "This removes them from $className along with their "
                      "attendance record. It cannot be undone.",
              style: const TextStyle(
                fontSize: kEventSubtitleTextSize,
                height: 1.4,
                color: kHomeSubtitleTextColor,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text("Cancel"),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                child: Text(asksFirst ? "Ask" : "Delete"),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final GB_ActionResult result =
          await GB_StudentStore.removeStudent(student.studentId);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on GB_ApiException catch (error) {
      if (!mounted) return;
      _showSubmitError(error);
    }
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);

    return Padding(
      // viewInsets, not viewPadding: this is the keyboard's height, and it is
      // what the sheet has to clear while the teacher types.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        // A share of the screen rather than all of it, so the dashboard stays
        // visible behind the sheet and it still reads as a sheet.
        constraints: BoxConstraints(
          maxHeight: media.size.height * kSheetHeightFraction,
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kSheetGradientTopColor, kPrimaryColor2],
            ),
            // Border.all rather than the design's three-sided edge: Flutter
            // will not paint a non-uniform border with a borderRadius. The
            // fourth side sits on the bottom of the screen, where it is not
            // visible anyway.
            border: Border.all(color: kSheetBorderColor),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kSheetTopRadius),
            ),
          ),
          // The sheet's own Material sits *behind* this gradient, so ink
          // splashes from the photo picker and the gender boxes would be
          // painted under it and never seen. A transparent Material in front
          // gives them a surface at the right depth; the ClipRRect keeps them
          // inside the rounded top corners.
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(kSheetTopRadius),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  _buildHeader(),
                  // The fields scroll; the header and the button do not, so
                  // "Add to Class" stays reachable without scrolling past
                  // fifteen fields.
                  Expanded(child: _buildForm()),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kSheetHorizontalPadding,
        12.0,
        kSheetHorizontalPadding,
        0.0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The grab handle from the design's sheets.
          Center(
            child: Container(
              width: 32.0,
              height: 4.0,
              decoration: BoxDecoration(
                color: kSheetHandleColor,
                borderRadius: BorderRadius.circular(kPillButtonRadius),
              ),
            ),
          ),
          const SizedBox(height: 24.0),
          Text(
            _isEditing
                ? "Edit ${widget.student!.name}'s details below."
                : "Let's get your student list growing! Enter the details "
                    "below.",
            style: const TextStyle(
              fontSize: kSheetIntroTextSize,
              height: 24.0 / kSheetIntroTextSize,
              letterSpacing: 0.0256,
              color: kHomeTitleTextColor,
            ),
          ),
          const SizedBox(height: 12.0),
          const Divider(height: 1.0, color: kFieldBorderColor),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        kSheetHorizontalPadding,
        20.0,
        kSheetHorizontalPadding,
        20.0,
      ),
      child: Form(
        key: _formKey,
        // The form is long enough that validating only on submit would send the
        // teacher scrolling back up; once they have submitted once, each field
        // corrects itself as they type.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GB_StudentPhotoPicker(
                photoPath: _photoPath,
                onTap: _pickPhoto,
              ),
            ),
            const SizedBox(height: 24.0),
            GB_SheetTextField(
              controller: _nameController,
              label: "Student's Name",
              isRequired: true,
              textCapitalization: TextCapitalization.words,
              validator: (String? value) =>
                  _validateRequired(value, "student's name"),
            ),
            const SizedBox(height: kFieldGap),
            // Full width rather than paired with the class as the age was: a
            // date and its label need more room than a two-digit number did.
            GB_SheetTextField(
              controller: _dateOfBirthController,
              label: "Date of Birth",
              isRequired: true,
              suffixIcon: Icons.calendar_today_outlined,
              onTap: _pickDateOfBirth,
              validator: _validateDateOfBirth,
            ),
            const SizedBox(height: kFieldGap),
            _buildClassField(),
            const SizedBox(height: kFieldGap),
            GB_GenderSelector(
              options: _genderOptions,
              selected: _gender,
              errorText: _genderError,
              onChanged: (String value) => setState(() {
                _gender = value;
                _genderError = null;
              }),
            ),
            const SizedBox(height: kFieldGap),
            GB_SheetTextField(
              controller: _addressController,
              label: "Address",
              isRequired: true,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.streetAddress,
              maxLines: 2,
              validator: (String? value) => _validateRequired(value, "address"),
            ),
            const SizedBox(height: 28.0),
            // The parents' numbers and emails are their logins: an account
            // that proves one of them sees this child automatically.
            const Text(
              "Parents log in to the app with the mobile number or email "
              "entered below, and will see this child in their account.",
              style: TextStyle(
                fontSize: kEventSubtitleTextSize,
                height: 1.4,
                color: kHomeSubtitleTextColor,
              ),
            ),
            const SizedBox(height: 16.0),
            const GB_SheetSectionHeader(
              title: "Mother's details",
              isOptional: true,
            ),
            const SizedBox(height: kFieldGap),
            _buildParentFields(
              nameController: _motherNameController,
              mobileController: _motherMobileController,
              emailController: _motherEmailController,
              nameLabel: "Mother's Name",
            ),
            const SizedBox(height: 28.0),
            const GB_SheetSectionHeader(
              title: "Father's details",
              isOptional: true,
            ),
            const SizedBox(height: kFieldGap),
            _buildParentFields(
              nameController: _fatherNameController,
              mobileController: _fatherMobileController,
              emailController: _fatherEmailController,
              nameLabel: "Father's Name",
            ),
            const SizedBox(height: 28.0),
            const GB_SheetSectionHeader(
              title: "Guardian's details",
              isOptional: true,
            ),
            const SizedBox(height: kFieldGap),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GB_SheetTextField(
                    controller: _guardianNameController,
                    label: "Guardian's Name",
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                const SizedBox(width: kFieldRowGap),
                Expanded(
                  child: GB_SheetTextField(
                    controller: _guardianRelationController,
                    label: "Relation",
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            ),
            const SizedBox(height: kFieldGap),
            GB_SheetPhoneField(
              controller: _guardianMobileController,
              label: "Guardian's Mobile",
            ),
            const SizedBox(height: kFieldGap),
            GB_SheetTextField(
              controller: _guardianAddressController,
              label: "Guardian's Address",
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.streetAddress,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  /// Name, mobile, and email — the same three fields for either parent.
  Widget _buildParentFields({
    required TextEditingController nameController,
    required TextEditingController mobileController,
    required TextEditingController emailController,
    required String nameLabel,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GB_SheetTextField(
          controller: nameController,
          label: nameLabel,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: kFieldGap),
        // Full width, unlike the name beside it used to be: the country
        // picker needs the room, and a half-width field left three digits
        // visible.
        GB_SheetPhoneField(controller: mobileController, label: "Mobile"),
        const SizedBox(height: kFieldGap),
        GB_SheetTextField(
          controller: emailController,
          label: "Email",
          keyboardType: TextInputType.emailAddress,
          validator: _validateOptionalEmail,
        ),
      ],
    );
  }

  /// The class picker, styled to match the text fields it sits beside.
  ///
  /// A dropdown rather than the design's free-text "Class/Grade" box: the
  /// classes already exist in [GB_ClassStore], and typing "nursery" into a text
  /// field would create a student nothing could file under the "Nursery" class.
  Widget _buildClassField() {
    return ValueListenableBuilder<List<GB_ClassInfo>>(
      valueListenable: GB_ClassStore.classes,
      builder: (BuildContext context, List<GB_ClassInfo> classes, _) {
        return DropdownButtonFormField<String>(
          // Cleared if the class it named has gone — deleted on another
          // device, say — rather than left pointing at nothing.
          value: classes.any((GB_ClassInfo item) => item.id == _classId)
              ? _classId
              : null,
          validator: _validateClass,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: kHomeSubtitleTextColor),
          style: const TextStyle(
            fontSize: kFieldInputTextSize,
            letterSpacing: 0.5,
            color: kHomeTitleTextColor,
          ),
          decoration: InputDecoration(
            labelText: "Class/Grade *",
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 16.0,
            ),
            labelStyle: const TextStyle(
              fontSize: kFieldInputTextSize,
              color: kHomeSubtitleTextColor,
            ),
            floatingLabelStyle: const TextStyle(
              fontSize: kFieldInputTextSize,
              letterSpacing: 0.4,
              color: kHomeTitleTextColor,
            ),
            border: _fieldOutline(kFieldBorderColor),
            enabledBorder: _fieldOutline(kFieldBorderColor),
            focusedBorder: _fieldOutline(kHomeAccentColor),
          ),
          // No "Not assigned" entry: a student is always registered into a
          // class.
          items: classes
              .map(
                (GB_ClassInfo classInfo) => DropdownMenuItem<String>(
                  value: classInfo.id,
                  child: Text(classInfo.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          // Locked when editing: this form edits the record, it does not move
          // the pupil to another class.
          onChanged: _isEditing
              ? null
              : (String? value) => setState(() => _classId = value),
        );
      },
    );
  }

  OutlineInputBorder _fieldOutline(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(kFieldRadius),
      borderSide: BorderSide(color: color),
    );
  }

  /// The pinned bottom bar carrying "Add to Class".
  ///
  /// The hairline above it is what separates the button from the field that
  /// happens to be scrolled under it; without it the button floats over the
  /// form with nothing to sit on.
  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        color: kPrimaryColor2,
        border: Border(top: BorderSide(color: kFieldBorderColor)),
      ),
      padding: const EdgeInsets.fromLTRB(
        kSheetHorizontalPadding,
        12.0,
        kSheetHorizontalPadding,
        16.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_submitError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                _submitError!,
                style: TextStyle(
                  fontSize: kEventSubtitleTextSize,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          _buildFooterButtons(),
        ],
      ),
    );
  }

  Widget _buildFooterButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Delete lives only here, inside the edit form, so removing a child
        // always passes an open record and a confirmation first.
        if (_isEditing) ...[
          TextButton.icon(
            onPressed: _isSubmitting ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text("Delete"),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
          ),
          const Spacer(),
        ],
        GB_PillButton(
          label: _isEditing ? "Save" : "Add to Class",
          onPressed: _isSubmitting ? null : _submit,
        ),
      ],
    );
  }
}
