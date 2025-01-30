part of mapbox_maps_flutter;

typedef OnPlatformViewCreatedCallback = void Function(int);

class _MapboxMapsPlatform {
  late MethodChannel _channel;
  BinaryMessenger binaryMessenger;
  final int channelSuffix;
  js.JsObject? _webMap;
  int currentViewId = 0;
  bool initialized = false;

  _MapboxMapsPlatform(
      {required this.binaryMessenger, required this.channelSuffix}) {
    _channel = MethodChannel(
        'plugins.flutter.io.${channelSuffix.toString()}',
        const StandardMethodCodec(),
        binaryMessenger);
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  _MapboxMapsPlatform.instance(int channelSuffix)
      : this(
            binaryMessenger: ServicesBinding.instance.defaultBinaryMessenger,
            channelSuffix: channelSuffix);

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print(
        "Handle method call ${call.method}, arguments: ${call.arguments} not supported");
  }

  Widget buildView(
      AndroidPlatformViewHostingMode androidHostingMode,
      Map<String, dynamic> creationParams,
      OnPlatformViewCreatedCallback onPlatformViewCreated,
      Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
      {Key? key}) {

    if (kIsWeb) {
      ui.platformViewRegistry.registerViewFactory(
        'plugins.flutter.io/mapbox_maps',
        (int viewId) => createMapboxElement(viewId, creationParams),
      );
      
      return HtmlElementView(
        key: key,
        viewType: 'plugins.flutter.io/mapbox_maps',
        onPlatformViewCreated: onPlatformViewCreated,
      );
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      switch (androidHostingMode) {
        case AndroidPlatformViewHostingMode.TLHC_VD:
        case AndroidPlatformViewHostingMode.TLHC_HC:
        case AndroidPlatformViewHostingMode.HC:
          return PlatformViewLink(
            key: key,
            viewType: "plugins.flutter.io/mapbox_maps",
            surfaceFactory: (context, controller) {
              return AndroidViewSurface(
                  controller: controller as AndroidViewController,
                  hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                  gestureRecognizers: gestureRecognizers ?? {});
            },
            onCreatePlatformView: (params) {
              final AndroidViewController controller =
                  _androidViewControllerFactoryForMode(androidHostingMode)(
                id: params.id,
                viewType: 'plugins.flutter.io/mapbox_maps',
                layoutDirection: TextDirection.ltr,
                creationParams: creationParams,
                creationParamsCodec: const MapInterfaces_PigeonCodec(),
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                params.onPlatformViewCreated,
              );
              controller.addOnPlatformViewCreatedListener(
                onPlatformViewCreated,
              );

              controller.create();
              return controller;
            },
          );
        case AndroidPlatformViewHostingMode.VD:
          return AndroidView(
            key: key,
            viewType: 'plugins.flutter.io/mapbox_maps',
            onPlatformViewCreated: onPlatformViewCreated,
            gestureRecognizers: gestureRecognizers,
            creationParams: creationParams,
            creationParamsCodec: const MapInterfaces_PigeonCodec(),
          );
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        key: key,
        viewType: 'plugins.flutter.io/mapbox_maps',
        onPlatformViewCreated: onPlatformViewCreated,
        gestureRecognizers: gestureRecognizers,
        creationParams: creationParams,
        creationParamsCodec: const MapInterfaces_PigeonCodec(),
      );
    }

    return Text(
        '$defaultTargetPlatform is not yet supported by the maps plugin');
  }

  AndroidViewController Function(
          {required int id,
          required String viewType,
          required TextDirection layoutDirection,
          dynamic creationParams,
          MessageCodec<dynamic>? creationParamsCodec,
          VoidCallback? onFocus})
      _androidViewControllerFactoryForMode(
          AndroidPlatformViewHostingMode hostingMode) {
    switch (hostingMode) {
      case AndroidPlatformViewHostingMode.TLHC_VD:
        return PlatformViewsService.initAndroidView;
      case AndroidPlatformViewHostingMode.TLHC_HC:
        return PlatformViewsService.initSurfaceAndroidView;
      case AndroidPlatformViewHostingMode.HC:
        return PlatformViewsService.initExpensiveAndroidView;
      case AndroidPlatformViewHostingMode.VD:
        throw "Unexpected hostring mode(VD) when selecting an android view controller";
    }
  }

  html.Element createMapboxElement(int viewId, Map<String, dynamic> params) {
    final element = html.DivElement()
      ..id = 'mapbox-container-$viewId'
      ..style.width = '100%'
      ..style.height = '100%';
    
    // Schedule initialization after element is attached
    html.window.requestAnimationFrame((_) {
      initializeMapbox(element, params, viewId);
    });
    
    return element;
  }

  // Add this method to initialize the Mapbox map
  void initializeMapbox(html.Element element, Map<String, dynamic> params, int viewId) {
    final cameraOptions = params['cameraOptions'] as CameraOptions;
    final subscribedEvents = params['eventTypes'] as List<int>;
    
    js.context['mapboxgl']['accessToken'] = MapboxOptions.getAccessToken();

    final options = <String, dynamic>{
      'container': element.id,
      'style': params['styleUri'],
      'center': [
        cameraOptions.center!.coordinates.lng,
        cameraOptions.center!.coordinates.lat,
      ],
      'zoom': cameraOptions.zoom,
    };
    
    try {
      final mapObj = js.JsObject(js.context['mapboxgl']['Map'], [js.JsObject.jsify(options)]);
      
      // Replace the default binary messenger here, right after map creation
      binaryMessenger = WebBinaryMessenger(binaryMessenger, mapObj, subscribedEvents);

      _channel = MethodChannel(
        'plugins.flutter.io.${channelSuffix.toString()}',
        const StandardMethodCodec(),
        binaryMessenger);

      _channel.setMethodCallHandler(_handleMethodCall);

      /*mapObj.callMethod('on', ['styledata', js.allowInterop((e) {
        print('Style data received');
      })]);

      mapObj.callMethod('on', ['style.load', js.allowInterop((e) {
        print('Style loaded completely');
      })]);*/

      /*mapObj.callMethod('on', ['data', js.allowInterop((e) {
        final data = js.JsObject.fromBrowserObject(e);
        print('Data event: ${data['dataType']}');
      })]);

      mapObj.callMethod('on', ['idle', js.allowInterop((e) {
        print('Map is idle - all loading complete');
      })]);*/
      
      mapObj.callMethod('on', ['load', js.allowInterop((e) {
        print('Map loaded successfully');
        initialized = true;
      })]);
      
      mapObj.callMethod('on', ['error', js.allowInterop((e) {
        final error = js.JsObject.fromBrowserObject(e);
        print('Mapbox error: ${error['error']}');
        if (error['error'] != null) {
          final errorDetails = js.JsObject.fromBrowserObject(error['error']);
          print('Error message: ${errorDetails['message']}');
          print('Error status: ${errorDetails['status']}');
          print('Error stack: ${errorDetails['stack']}');
        }
      })]);

      // Add style specific error handler
      mapObj.callMethod('on', ['style.error', js.allowInterop((e) {
        final error = js.JsObject.fromBrowserObject(e);
        print('Style error: ${error}');
      })]);

      // Store the map instance for later use if needed
      _webMap = mapObj;
      currentViewId = viewId;
    } catch (e) {
      print('Error initializing map: $e');
    }
  }

  Future<void> waitForMapLoad() async {
    if (!kIsWeb) return;
    
    while (!initialized) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    
    return;
  }

  Future<void> submitViewSizeHint(
      {required double width, required double height}) {
    if (kIsWeb) {
      // Handle web-specific size update
      final viewId = currentViewId;
      final mapObj = _webMap;
      if (mapObj != null) {
        // Trigger a resize event on the map
        html.window.requestAnimationFrame((_) {
          mapObj.callMethod('resize');
        });
      }
      return Future.value();
    }
    
    return _channel!
        .invokeMethod('mapView#submitViewSizeHint', <String, dynamic>{
      'width': width,
      'height': height,
    });
  }

  void dispose() async {
    try {
      await _channel.invokeMethod('platform#releaseMethodChannels');
    } catch (e) {
      print("Error releasing method channels: $e");
    }

    _channel.setMethodCallHandler(null);
  }

  Future<dynamic> createAnnotationManager(String type,
      {String? id, String? belowLayerId}) async {
    try {
      return _channel
          .invokeMethod('annotation#create_manager', <String, dynamic>{
        'type': type,
        'id': id,
        'belowLayerId': belowLayerId,
      });
    } on PlatformException catch (e) {
      return new Future.error(e);
    }
  }

  Future<void> removeAnnotationManager(String id) {
    try {
      return _channel.invokeMethod(
          'annotation#remove_manager', <String, dynamic>{'id': id});
    } on PlatformException catch (e) {
      return new Future.error(e);
    }
  }

  Future<dynamic> addGestureListeners() async {
    try {
      return _channel.invokeMethod('gesture#add_listeners');
    } on PlatformException catch (e) {
      return new Future.error(e);
    }
  }

  Future<dynamic> removeGestureListeners() async {
    try {
      return _channel.invokeMethod('gesture#remove_listeners');
    } on PlatformException catch (e) {
      return new Future.error(e);
    }
  }

  Future<Uint8List> snapshot() async {
    try {
      final List<int> data = await _channel.invokeMethod('map#snapshot');
      return Uint8List.fromList(data);
    } on PlatformException catch (e) {
      return new Future.error(e);
    }
  }
}

/// A registry to hold suffixes for Channels.
///
class _SuffixesRegistry {
  _SuffixesRegistry._instance();

  int _suffix = -1;
  final Set<int> suffixesInUse = {};
  final Set<int> suffixesAvailable = {};

  int getSuffix() {
    int suffix;

    if (suffixesAvailable.isEmpty) {
      _suffix++;
      suffix = _suffix;
    } else {
      suffix = suffixesAvailable.first;
      suffixesAvailable.remove(suffix);
    }
    suffixesInUse.add(suffix);

    return suffix;
  }

  void releaseSuffix(int suffix) {
    suffixesInUse.remove(suffix);
    suffixesAvailable.add(suffix);
  }
}
