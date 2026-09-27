import 'dart:io';

import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// A section heading on the class screen, optionally with a "See All" action
/// on the right — "Students list" is the one that has it.
class GB_ClassSectionHeader extends StatelessWidget {
  const GB_ClassSectionHeader({
    super.key,
    required this.title,
    this.onSeeAll,
  });

  final String title;

  /// When null, no "See All" is drawn — that is how "Features" renders.
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: kClassSectionHeaderSize,
            height: 24.0 / kClassSectionHeaderSize,
            fontWeight: FontWeight.w500,
            color: kHomeTitleTextColor,
          ),
        ),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            // Opaque so the tap lands anywhere in the padded box, not only on
            // the glyphs themselves.
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
              child: Text(
                "See All",
                style: TextStyle(
                  fontSize: kClassSeeAllTextSize,
                  height: 1.5,
                  color: kHomeAccentColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The white rounded card shared by the feature and student rows: same size,
/// radius, and shadow, differing only in what they stack inside.
class GB_ClassRowCard extends StatelessWidget {
  const GB_ClassRowCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback? onTap;

  /// The card's secondary action, where it has one.
  ///
  /// Long press rather than a second visible control: these cards are 96pt
  /// wide in a horizontal strip, and the only thing behind this today is
  /// removing a pupil — which is irreversible and should not sit a few pixels
  /// from "open".
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPrimaryColor2,
      borderRadius: BorderRadius.circular(kFeatureCardRadius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(kFeatureCardRadius),
        child: Container(
          width: kFeatureCardWidth,
          height: kFeatureCardHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kFeatureCardRadius),
            boxShadow: const [
              BoxShadow(
                color: kClassCardShadowColor,
                blurRadius: 10.0,
                offset: Offset(0.0, 4.0),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One tile in the "Features" row: illustrated icon over a label.
class GB_FeatureCard extends StatelessWidget {
  const GB_FeatureCard({
    super.key,
    required this.feature,
    this.onTap,
  });

  final GB_ClassFeature feature;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GB_ClassRowCard(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            feature.iconPath,
            width: kFeatureIconSize,
            height: kFeatureIconSize,
            // contain, not cover: the source art is not all square, and cover
            // would crop the taller ones.
            fit: BoxFit.contain,
          ),
          const SizedBox(height: 8.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: Text(
              feature.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kFeatureLabelTextSize,
                fontWeight: FontWeight.w500,
                color: kTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One tile in the "Students list" row: round photo over name and age.
class GB_StudentCard extends StatelessWidget {
  const GB_StudentCard({
    super.key,
    required this.student,
    this.onTap,
    this.onLongPress,
  });

  final GB_Student student;
  final VoidCallback? onTap;

  /// Held down to remove the pupil — or, for a teacher, to ask the principal
  /// to. Null where the viewer may do neither, which draws no action at all
  /// rather than one that refuses.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return GB_ClassRowCard(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: kStudentAvatarRadius,
            // The registered photo when there is one, the stock asset when the
            // teacher skipped it — the photo field is optional.
            backgroundImage: student.photoPath == null
                ? AssetImage(student.imagePath) as ImageProvider
                : FileImage(File(student.photoPath!)),
          ),
          const SizedBox(height: kStudentCardGap),
          // The card is a fixed height, and the photo plus two lines of text
          // only just fill it at the default text size. A phone set to a
          // larger font overflowed it by a few points once the roll-number
          // line appeared, so the text here is capped a little above normal
          // and set in a fixed line height rather than the font's own. The
          // rest of the app still follows the system size.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: kStudentCardMaxTextScale,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    student.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: kStudentNameTextSize,
                      height: kStudentCardLineHeight,
                      fontWeight: FontWeight.w500,
                      color: kTextColor,
                    ),
                  ),
                  // The roll number, not the ST_ id: it is what a teacher
                  // calls a pupil by, while the id is a database key.
                  if (student.rollNumber != null)
                    Text(
                      "Roll No. ${student.rollNumber}",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: kStudentIdTextSize,
                        height: kStudentCardLineHeight,
                        fontWeight: FontWeight.w500,
                        color: kHomeTitleTextColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The horizontally scrolling strip the feature and student rows both sit in,
/// including the design's faint vertical wash behind the cards.
class GB_ClassCardRow extends StatelessWidget {
  const GB_ClassCardRow({
    super.key,
    required this.children,
    required this.gap,
    this.padding = const EdgeInsets.symmetric(horizontal: kHomeHorizontalPadding),
  });

  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kPrimaryColor2, kClassRowWashColor, kPrimaryColor2],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: padding,
        child: Row(
          children: [
            for (int index = 0; index < children.length; index++) ...[
              if (index > 0) SizedBox(width: gap),
              children[index],
            ],
          ],
        ),
      ),
    );
  }
}

/// The row of pastel swatches that picks a class's colour, shared by "Add a
/// class" and "Edit class" so the two offer exactly the same choice.
///
/// Stateless and driven by [selectedSlot]: the form owns the choice, because it
/// is the form that has to send it to [GB_ClassStore] on Save.
///
/// Wraps rather than scrolls. A horizontal strip would hide the later colours
/// off the edge of a sheet, and a colour a teacher cannot see is one they will
/// not pick.
class GB_ClassColorPicker extends StatelessWidget {
  const GB_ClassColorPicker({
    super.key,
    required this.selectedSlot,
    required this.onSelected,
    this.label = "Theme colour",
  });

  /// Index into [GB_ClassPalette.all].
  final int selectedSlot;

  final ValueChanged<int> onSelected;

  /// Null draws no heading — for a form that already says what the row is.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final String? label = this.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: kFieldLabelTextSize,
              color: kHomeSubtitleTextColor,
            ),
          ),
          const SizedBox(height: 8.0),
        ],
        Wrap(
          spacing: kClassSwatchGap,
          runSpacing: kClassSwatchGap,
          children: [
            for (int slot = 0; slot < GB_ClassPalette.length; slot++)
              _GB_ClassColorSwatch(
                color: GB_ClassPalette.at(slot),
                isSelected: slot == selectedSlot,
                onTap: () => onSelected(slot),
              ),
          ],
        ),
      ],
    );
  }
}

/// One swatch: a class tile in miniature, ticked when it is the chosen one.
class _GB_ClassColorSwatch extends StatelessWidget {
  const _GB_ClassColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final GB_ClassColor color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // The pastels are close enough in weight that colour alone is a poor
      // label, and it is no label at all to a screen reader.
      label: color.name,
      button: true,
      selected: isSelected,
      child: Tooltip(
        message: color.name,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: kClassSwatchSize,
            height: kClassSwatchSize,
            decoration: BoxDecoration(
              color: color.fill,
              shape: BoxShape.circle,
              // The selected swatch is ringed in the accent rather than its own
              // border: the tints are pale, and a thicker ring of the same pale
              // hue does not read as "this one".
              border: Border.all(
                color: isSelected ? kHomeAccentColor : color.border,
                width: isSelected
                    ? kClassSwatchSelectedBorderWidth
                    : kClassSwatchBorderWidth,
              ),
            ),
            child: isSelected
                ? const Icon(
                    Icons.check,
                    size: kClassSwatchCheckSize,
                    color: kHomeAccentColor,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
