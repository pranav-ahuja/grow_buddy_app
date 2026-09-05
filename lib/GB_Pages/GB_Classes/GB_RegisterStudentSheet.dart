import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassStore.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentFormFields.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_StudentStore.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_AuthFlow.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';
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
/// length reads as four short forms rather than one long one. Only the four
/// the design implies are mandatory: name, age, gender, and address.
///
/// Call [show]; it returns the registered student, or null if the teacher
/// backed out, so the caller can react (the dashboard confirms with a snackbar).
class GB_RegisterStudentSheet extends StatefulWidget {
  const GB_RegisterStudentSheet({super.key, this.initialClassId});

  /// Preselects a class, for when the sheet is opened from inside one. Null
  /// from the dashboard, where no class is in context yet.
  final int? initialClassId;

  static Future<GB_Student?> show(BuildContext context, {int? initialClassId}) {
    return showModalBottomSheet<GB_Student>(
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
  final TextEditingController _ageController = TextEditingController();
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

  /// Null means "no class yet" — the field is optional, and the teacher can add
  /// the student to a class later.
  int? _classId;

  String? _photoPath;

  /// Gender is not a [FormField], so its error is tracked by hand and shown
  /// alongside the ones [Form.validate] raises on the text fields.
  String? _genderError;

  /// Blocks a second tap between validating and popping the sheet.
  bool _isSubmitting = false;

  static const List<String> _genderOptions = ["Male", "Female"];

  @override
  void initState() {
    super.initState();
    _classId = widget.initialClassId;
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _nameController,
      _ageController,
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

  /// Ages outside 1-30 are almost certainly a typo rather than a pupil, and
  /// letting one through would put "Age 202" on the class screen's card.
  String? _validateAge(String? value) {
    final String age = (value ?? "").trim();
    if (age.isEmpty) return "Enter the age";

    final int? parsed = int.tryParse(age);
    if (parsed == null) return "Use numbers only";
    if (parsed < 1 || parsed > 30) return "Enter an age between 1 and 30";
    return null;
  }

  /// Optional everywhere it is used, so an empty value passes. A filled one is
  /// checked loosely on digit count only: numbers arrive with spaces, dashes,
  /// and country codes, and a stricter pattern would reject valid ones.
  String? _validateOptionalMobile(String? value) {
    final String mobile = (value ?? "").trim();
    if (mobile.isEmpty) return null;

    final String digits = mobile.replaceAll(RegExp(r"\D"), "");
    if (digits.length < 7 || digits.length > 15) {
      return "Enter a valid mobile number";
    }
    return null;
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

  void _submit() {
    // Both run before either is checked, so the teacher sees every problem at
    // once rather than fixing the fields and then discovering the gender row.
    final bool fieldsValid = _formKey.currentState?.validate() ?? false;
    final bool genderValid = _gender != null;

    setState(() => _genderError = genderValid ? null : "Select a gender");
    if (!fieldsValid || !genderValid) return;

    setState(() => _isSubmitting = true);

    final GB_Student created = GB_StudentStore.addStudent(
      name: _nameController.text,
      age: _ageController.text,
      gender: _gender!,
      address: _addressController.text,
      classId: _classId,
      photoPath: _photoPath,
      mother: _contactOrNull(
        name: _motherNameController,
        mobile: _motherMobileController,
        email: _motherEmailController,
      ),
      father: _contactOrNull(
        name: _fatherNameController,
        mobile: _fatherMobileController,
        email: _fatherEmailController,
      ),
      guardian: _contactOrNull(
        name: _guardianNameController,
        mobile: _guardianMobileController,
        address: _guardianAddressController,
        relation: _guardianRelationController,
      ),
    );

    Navigator.of(context).pop(created);
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
          const Text(
            "Let's get your student list growing! Enter the details below.",
            style: TextStyle(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GB_SheetTextField(
                    controller: _ageController,
                    label: "Age",
                    isRequired: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validateAge,
                  ),
                ),
                const SizedBox(width: kFieldRowGap),
                Expanded(child: _buildClassField()),
              ],
            ),
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
            GB_SheetTextField(
              controller: _guardianMobileController,
              label: "Guardian's Mobile",
              keyboardType: TextInputType.phone,
              validator: _validateOptionalMobile,
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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GB_SheetTextField(
                controller: nameController,
                label: nameLabel,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: kFieldRowGap),
            Expanded(
              child: GB_SheetTextField(
                controller: mobileController,
                label: "Mobile",
                keyboardType: TextInputType.phone,
                validator: _validateOptionalMobile,
              ),
            ),
          ],
        ),
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
        return DropdownButtonFormField<int?>(
          value: _classId,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, color: kHomeSubtitleTextColor),
          style: const TextStyle(
            fontSize: kFieldInputTextSize,
            letterSpacing: 0.5,
            color: kHomeTitleTextColor,
          ),
          decoration: InputDecoration(
            labelText: "Class/Grade",
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
          items: [
            // The class is optional, so there has to be a way back out of a
            // choice already made.
            const DropdownMenuItem<int?>(
              value: null,
              child: Text(
                "Not assigned",
                style: TextStyle(color: kHomeSubtitleTextColor),
              ),
            ),
            ...classes.map(
              (GB_ClassInfo classInfo) => DropdownMenuItem<int?>(
                value: classInfo.id,
                child: Text(classInfo.name, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (int? value) => setState(() => _classId = value),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GB_PillButton(
            label: "Add to Class",
            onPressed: _isSubmitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
