import 'package:flutter/material.dart';
import 'package:grow_buddy_app/GB_Pages/GB_Classes/GB_ClassModels.dart';
import 'package:grow_buddy_app/GB_Pages/GB_HomeScreen/GB_HomeModels.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

/// A single event card in the carousel: image on top, then the title with a
/// share button beside it, then the subtitle.
///
/// Measurements come from the "event 2" component in the Figma frame — 14pt
/// padding, 24pt radius, a 140pt image, and a 10pt gap before the text block.
class GB_EventCard extends StatelessWidget {
  const GB_EventCard({
    super.key,
    required this.event,
    this.onShare,
    this.onTap,
  });

  final GB_Event event;
  final VoidCallback? onShare;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: kPrimaryColor2,
          borderRadius: BorderRadius.circular(kEventCardRadius),
          border: Border.all(color: kHomeCardBorderColor),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1AA9A5A5),
              blurRadius: 10.0,
              offset: Offset(0.0, 2.0),
            ),
          ],
        ),
        padding: const EdgeInsets.all(kEventCardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4.0),
              child: Image.asset(
                event.imagePath,
                height: kEventImageHeight,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10.0),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kHomeCardTitleTextSize,
                          height: 28.0 / kHomeCardTitleTextSize,
                          fontWeight: FontWeight.w500,
                          color: kHomeTitleTextColor,
                        ),
                      ),
                      const SizedBox(height: 2.0),
                      Text(
                        event.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kEventSubtitleTextSize,
                          height: 28.0 / kEventSubtitleTextSize,
                          color: kHomeSubtitleTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8.0),
                // Stripped of the default 48x48 tap padding so the 24pt glyph
                // lines up with the title's cap height, as it does in the design.
                IconButton(
                  onPressed: onShare,
                  icon: const Icon(Icons.share),
                  iconSize: 24.0,
                  color: kHomeIconColor,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24.0,
                    minHeight: 24.0,
                  ),
                  tooltip: "Share",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The carousel's page indicator: the active page is a 40x8 pill, the rest are
/// 8pt hollow circles, spaced 8pt apart.
class GB_CarouselIndicator extends StatelessWidget {
  const GB_CarouselIndicator({
    super.key,
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (int index) {
        final bool isActive = index == activeIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4.0),
          height: 8.0,
          width: isActive ? 40.0 : 8.0,
          decoration: BoxDecoration(
            color: isActive ? kHomeDotColor : Colors.transparent,
            border: isActive ? null : Border.all(color: kHomeDotColor),
            borderRadius: BorderRadius.circular(8.0),
          ),
        );
      }),
    );
  }
}

/// One row of the class list: a 48pt circular photo, the class name, and the
/// student count beneath it, on the class's own tint.
class GB_ClassTile extends StatelessWidget {
  const GB_ClassTile({
    super.key,
    required this.classInfo,
    this.subtitle,
    this.onTap,
    this.onDelete,
  });

  final GB_ClassInfo classInfo;

  /// Overrides [GB_ClassInfo.subtitle] — how the dashboard swaps the design's
  /// "no. of students" caption for the real count once students are registered.
  /// Null falls back to whatever the class itself carries.
  final String? subtitle;

  final VoidCallback? onTap;

  /// Shown as a trailing bin icon when set. Null draws no button at all, so a
  /// tile can be listed somewhere deleting is not on offer.
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kClassTileGap),
      child: Material(
        // Material + InkWell rather than GestureDetector: the ripple needs a
        // Material ancestor to paint on, and clipping it to the same radius
        // keeps the splash inside the rounded corners.
        color: classInfo.fillColor,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kClassTileRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kClassTileRadius),
              border: Border.all(color: classInfo.borderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40E0DBDB),
                  blurRadius: 10.0,
                  offset: Offset(0.0, 4.0),
                ),
              ],
            ),
            padding: const EdgeInsets.all(kClassTilePadding),
            child: Row(
              children: [
                CircleAvatar(
                  radius: kClassTileAvatarRadius,
                  backgroundImage: AssetImage(classInfo.imagePath),
                ),
                const SizedBox(width: 24.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        classInfo.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kHomeCardTitleTextSize,
                          fontWeight: FontWeight.w500,
                          color: kTextColor,
                        ),
                      ),
                      const SizedBox(height: 4.0),
                      Text(
                        subtitle ?? classInfo.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: kClassSubtitleTextSize,
                          color: kHomeSubtitleTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  // An IconButton, not a bare Icon in a GestureDetector: it
                  // handles its own taps, so pressing the bin cannot fall
                  // through to the InkWell and open the class instead of
                  // deleting it.
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    color: kHomeSubtitleTextColor,
                    iconSize: kClassDeleteIconSize,
                    // Sits inside a 80pt tile, so the default 48pt tap target
                    // plus its padding would push the row taller than the
                    // design's card.
                    visualDensity: VisualDensity.compact,
                    tooltip: "Delete ${classInfo.name}",
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tile that closes the class list and opens the add-class form.
///
/// Sits in the list rather than in the app bar or beside the FAB: adding a
/// class is a thing you do *to this list*, and the design already spends the
/// FAB on registering a student. Its outline and muted fill keep it reading as
/// an action rather than as another class.
class GB_AddClassTile extends StatelessWidget {
  const GB_AddClassTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kClassTileGap),
      child: Material(
        color: kPrimaryColor2,
        borderRadius: BorderRadius.circular(kClassTileRadius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kClassTileRadius),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(kClassTileRadius),
              border: Border.all(color: kHomeNavBorderColor),
            ),
            padding: const EdgeInsets.all(kClassTilePadding),
            child: Row(
              children: [
                Container(
                  width: kClassTileAvatarRadius * 2,
                  height: kClassTileAvatarRadius * 2,
                  decoration: const BoxDecoration(
                    color: kClassRowWashColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: kHomeAccentColor),
                ),
                const SizedBox(width: 24.0),
                const Expanded(
                  child: Text(
                    "Add a class",
                    style: TextStyle(
                      fontSize: kHomeCardTitleTextSize,
                      fontWeight: FontWeight.w500,
                      color: kHomeAccentColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Your classes at a glance!" style heading above a list.
class GB_HomeSectionHeader extends StatelessWidget {
  const GB_HomeSectionHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: kHomeSectionHeaderTextSize,
        height: 28.0 / kHomeSectionHeaderTextSize,
        fontWeight: FontWeight.w500,
        color: kHomeTitleTextColor,
      ),
    );
  }
}
