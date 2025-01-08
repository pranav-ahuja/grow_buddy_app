import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:grow_buddy_app/GB_Utilities/GB_Common_Utilities/GB_Constants.dart';

class GB_ImageSlider extends StatelessWidget {
  const GB_ImageSlider({
    super.key,
    required this.sliderImageList,
  });

  final List<String> sliderImageList;

  @override
  Widget build(BuildContext context) {
    return CarouselSlider(
      items: sliderImageList
          .map(
            (Image_url) => Center(
              child: Image.asset(Image_url),
            ),
          )
          .toList(),
      options: CarouselOptions(
        autoPlay: true,
        height: kCarouselImageSliderHeight,
        viewportFraction: kCarouselImageSliderViewPort,
        enlargeCenterPage: true,
      ),
    );
  }
}
