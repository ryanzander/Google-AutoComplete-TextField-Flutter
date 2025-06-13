library google_places_flutter;

import 'dart:developer';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  final InputDecoration inputDecoration;
  final ItemClick itemClick;
  final GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  final bool isLatLngRequired;
  final TextStyle textStyle;
  final String googleAPIKey;
  final int debounceTime;
  final List<String>? countries;
  final TextEditingController textEditingController;
  final ListItemBuilder? itemBuilder;
  final Widget? seperatedBuilder;
  final BoxDecoration? boxDecoration;
  final bool isCrossBtnShown;
  final bool showError;
  final double? containerHorizontalPadding;
  final double? containerVerticalPadding;
  final FocusNode? focusNode;
  final PlaceType? placeType;
  final String? language;
  final TextInputAction? textInputAction;
  final VoidCallback? formSubmitCallback;

  final String? Function(String?, BuildContext)? validator;

  final double? latitude;
  final double? longitude;

  /// This is expressed in **meters**
  final int? radius;

  GooglePlaceAutoCompleteTextField({
    required this.textEditingController,
    required this.googleAPIKey,
    required this.itemClick,
    this.debounceTime = 600,
    this.inputDecoration = const InputDecoration(),
    this.isLatLngRequired = true,
    this.textStyle = const TextStyle(),
    this.countries,
    this.getPlaceDetailWithLatLng,
    this.itemBuilder,
    this.boxDecoration,
    this.isCrossBtnShown = true,
    this.seperatedBuilder,
    this.showError = true,
    this.containerHorizontalPadding,
    this.containerVerticalPadding,
    this.focusNode,
    this.placeType,
    this.language = 'en',
    this.validator,
    this.latitude,
    this.longitude,
    this.radius,
    this.formSubmitCallback,
    this.textInputAction,
  });

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  final LayerLink _layerLink = LayerLink();

  bool isCrossBtn = true;
  late final Dio _dio;
  late final FocusNode _focusNode;

  CancelToken? _cancelToken = CancelToken();

  @override
  void dispose() {
    subject.close();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: widget.containerHorizontalPadding ?? 0,
          vertical: widget.containerVerticalPadding ?? 0,
        ),
        alignment: Alignment.centerLeft,
        decoration:
            widget.boxDecoration ??
            BoxDecoration(
              shape: BoxShape.rectangle,
              border: Border.all(color: Colors.grey, width: 0.6),
              borderRadius: BorderRadius.all(Radius.circular(10)),
            ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                decoration: widget.inputDecoration,
                style: widget.textStyle,
                controller: widget.textEditingController,
                focusNode: _focusNode,
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                onFieldSubmitted: (value) {
                  if (widget.formSubmitCallback != null) {
                    widget.formSubmitCallback!();
                  }
                },
                validator: (inputString) {
                  return widget.validator?.call(inputString, context);
                },
                onChanged: (string) {
                  subject.add(string);
                  if (widget.isCrossBtnShown) {
                    isCrossBtn = string.isNotEmpty ? true : false;
                    setState(() {});
                  }
                },
              ),
            ),
            (!widget.isCrossBtnShown)
                ? SizedBox()
                : isCrossBtn && _showCrossIconWidget()
                ? IconButton(onPressed: clearData, icon: Icon(Icons.close))
                : SizedBox(),
          ],
        ),
      ),
    );
  }

  getLocation(String text) async {
    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];

        if (i == 0) {
          apiURL = apiURL + "&components=country:$country";
        } else {
          apiURL = apiURL + "|" + "country:" + country;
        }
      }
    }
    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (widget.latitude != null &&
        widget.longitude != null &&
        widget.radius != null) {
      apiURL =
          apiURL +
          "&location=${widget.latitude},${widget.longitude}&radius=${widget.radius}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;

      Response response = await _dio.get(url);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      if (text.length == 0) {
        alPredictions.clear();
        this._overlayEntry?.remove();
        this._overlayEntry = null;
        return;
      }

      alPredictions.clear();
      if (subscriptionResponse.predictions!.length > 0 &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
      }

      this._overlayEntry = null;
      this._overlayEntry = this._createOverlayEntry();
      if (_overlayEntry != null) {
        Overlay.of(context).insert(this._overlayEntry!);
      }
    } catch (e) {
      log('Error in getLocation: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    _focusNode = widget.focusNode ?? FocusNode();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
  }

  textChanged(String text) async {
    if (text.isNotEmpty) {
      getLocation(text);
    } else {
      alPredictions.clear();
      this._overlayEntry?.remove();
      this._overlayEntry = null;
    }
  }

  OverlayEntry? _createOverlayEntry() {
    if (context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return OverlayEntry(
        builder:
            (context) => Positioned(
              left: offset.dx,
              top: size.height + offset.dy,
              width: size.width,
              child: CompositedTransformFollower(
                showWhenUnlinked: false,
                link: this._layerLink,
                offset: Offset(0.0, size.height + 5.0),
                child: Material(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: alPredictions.length,
                    separatorBuilder:
                        (context, pos) => widget.seperatedBuilder ?? SizedBox(),
                    itemBuilder: (BuildContext context, int index) {
                      return InkWell(
                        onTap: () async {
                          var selectedData = alPredictions[index];
                          if (index < alPredictions.length) {
                            widget.itemClick(selectedData);

                            if (widget.isLatLngRequired) {
                              await getPlaceDetailsFromPlaceId(selectedData);
                            }
                            removeOverlay();
                          }
                        },
                        child:
                            widget.itemBuilder != null
                                ? widget.itemBuilder!(
                                  context,
                                  index,
                                  alPredictions[index],
                                )
                                : Container(
                                  padding: EdgeInsets.all(10),
                                  child: Text(
                                    alPredictions[index].description!,
                                  ),
                                ),
                      );
                    },
                  ),
                ),
              ),
            ),
      );
    } else {
      return null;
    }
  }

  removeOverlay() {
    alPredictions.clear();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(url);

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      final location = placeDetails.result?.geometry?.location;
      if (location != null) {
        prediction.lat = location.lat.toString();
        prediction.lng = location.lng.toString();
        widget.getPlaceDetailWithLatLng?.call(prediction);
      }
    } catch (e) {
      log('Error in getPlaceDetailsFromPlaceId: $e');
    }
  }

  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    if (this._overlayEntry != null) {
      try {
        this._overlayEntry?.remove();
        this._overlayEntry = null;
      } catch (e) {}
    }
  }

  _showCrossIconWidget() {
    return (widget.textEditingController.text.isNotEmpty);
  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
    responseBody as Map<String, dynamic>,
  );
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng =
    void Function(Prediction postalCodeResponse);

typedef ListItemBuilder =
    Widget Function(BuildContext context, int index, Prediction prediction);
