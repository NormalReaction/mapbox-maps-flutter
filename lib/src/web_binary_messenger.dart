part of mapbox_maps_flutter;

enum GestureEvent {
  click,
  dragStart,
  drag,
  dragEnd
}

class WebBinaryMessenger implements BinaryMessenger {
  final BinaryMessenger defaultMessenger;
  final js.JsObject mapInstance;
  final MessageCodec<Object?> mapInterfacesCodec = MapInterfaces_PigeonCodec();
  final MessageCodec<Object?> gesturesCodec = GestureListeners_PigeonCodec();
  final MessageCodec<Object?> settingsCodec = Settings_PigeonCodec();
  final Map<String, MessageHandler> messageHandlers = {};
  // ignore: library_private_types_in_public_api
  final Set<_MapEvent> subscribedEvents = {};

  bool hasGeolocateControl = false;

  WebBinaryMessenger(this.defaultMessenger, this.mapInstance, List<int> initialEvents) {
    subscribedEvents.addAll(
      initialEvents.map((index) => _MapEvent.values[index])
    );
    setupEventHandlers();
  }

  void setupEventHandlers() {
    // Set up camera change listener
    mapInstance.callMethod('on', ['move', js.allowInterop((e) {
      if (subscribedEvents.contains(_MapEvent.cameraChanged)) {
        handleCameraChanged();
      }
    })]);

    // https://docs.mapbox.com/mapbox-gl-js/api/map/#map-events
    mapInstance.callMethod('on', ['click', js.allowInterop((e) {
      handleGestures(GestureEvent.click, e);
    })]);

    mapInstance.callMethod('on', ['dragstart', js.allowInterop((e) {
      handleGestures(GestureEvent.dragStart, e);
    })]);

    mapInstance.callMethod('on', ['drag', js.allowInterop((e) {
      handleGestures(GestureEvent.drag, e);
    })]);

    mapInstance.callMethod('on', ['dragend', js.allowInterop((e) {
      handleGestures(GestureEvent.dragEnd, e);
    })]);
  }

  void handleCameraChanged() {
    // Get camera state from map
    final center = mapInstance.callMethod('getCenter');
    final zoom = mapInstance.callMethod('getZoom');
    final bearing = mapInstance.callMethod('getBearing');
    final pitch = mapInstance.callMethod('getPitch');

    final eventData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'cameraState': {
        'center': {'coordinates': [center['lng'], center['lat']]},
        'padding': {'top': 0, 'left': 0, 'bottom': 0, 'right': 0},
        'zoom': zoom,
        'bearing': bearing,
        'pitch': pitch,
      },
    };

    // Find the handler for the camera events channel
    final handler = messageHandlers['com.mapbox.maps.flutter.map_events.0'];
    if (handler != null) {
      // Encode the method call
      final methodCall = MethodCall('event#${_MapEvent.cameraChanged.index}', 
          json.encode(eventData));
      final encodedMethodCall = const StandardMethodCodec()
          .encodeMethodCall(methodCall);
      
      // Send to the handler
      handler(encodedMethodCall);
    }

  }

  void handleGestures(GestureEvent gestureEvent, js.JsObject eventData) {
    String handlerName = '';
    GestureState gestureState = GestureState.changed;
    
    switch (gestureEvent) {
      case GestureEvent.click:
        handlerName = 'dev.flutter.pigeon.mapbox_maps_flutter.GestureListener.onTap.0';
        gestureState = GestureState.changed;
        break;
      case GestureEvent.dragStart:
        handlerName = 'dev.flutter.pigeon.mapbox_maps_flutter.GestureListener.onScroll.0';
        gestureState = GestureState.started;
        break;
      case GestureEvent.drag:
        handlerName = 'dev.flutter.pigeon.mapbox_maps_flutter.GestureListener.onScroll.0';
        gestureState = GestureState.changed;
        break;
      case GestureEvent.dragEnd:
        handlerName = 'dev.flutter.pigeon.mapbox_maps_flutter.GestureListener.onScroll.0';
        gestureState = GestureState.ended;
        break;
      default:
        throw ArgumentError('WebBinaryMessenger does not support gesture event $gestureEvent');
    }

    final touchPosition;
    if (eventData['point'] == null) {
      touchPosition = ScreenCoordinate(x: 0, y: 0);
    } else {
      touchPosition = ScreenCoordinate(x: eventData['point']['x'], y: eventData['point']['y']);
    }

    final point;
    if (eventData['lngLat'] == null) {
      point = Point(coordinates: Position(0, 0));
    } else {
      point = Point(coordinates: Position(eventData['lngLat']['lng'], eventData['lngLat']['lat']));
    }
    MapContentGestureContext gestureContext = MapContentGestureContext(
      touchPosition: touchPosition,
      point: point,
      gestureState: gestureState
    );

    // Find the handler for the camera events channel
    final handler = messageHandlers[handlerName];    
    if (handler != null) {
      final List<Object?> args = [gestureContext];
      // Send to the handler
      handler(gesturesCodec.encodeMessage(args));
    }
  }

  CameraState getCameraState() {
    // Get camera state from map
    final center = mapInstance.callMethod('getCenter');
    final zoom = mapInstance.callMethod('getZoom');
    final bearing = mapInstance.callMethod('getBearing');
    final pitch = mapInstance.callMethod('getPitch');
    final padding = mapInstance.callMethod('getPadding');

    return CameraState( 
      center: Point(coordinates: turf.Position(center['lng'], center['lat'])),
      zoom: zoom,
      bearing: bearing, 
      pitch: pitch,
      padding: MbxEdgeInsets(top: padding['top'], left: padding['left'], bottom: padding['bottom'], right: padding['right']),
    );
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {

    try {
      // Handle subscription messages for map events
      if (channel.contains('map_events')) {
        final methodCall = const StandardMethodCodec().decodeMethodCall(message);
        if (methodCall.method == 'subscribeToEvents') {
          final List<int> eventIndices = List<int>.from(methodCall.arguments);
          subscribedEvents.clear();
          subscribedEvents.addAll(
            eventIndices.map((index) => _MapEvent.values[index])
          );
          print('Subscribed to events: $subscribedEvents');
          return Future.value(const StandardMethodCodec().encodeSuccessEnvelope(null));
        }
      }

      // For other messages, use the existing handling
      if (channel.startsWith('dev.flutter.pigeon.mapbox_maps_flutter')) {
        final methodName = getMethodName(channel);
        final codec = getMessageCodec(methodName);
        final List<Object?> arguments = (message != null) ? codec.decodeMessage(message) as List<Object?> : [];
        return callWebMethod(methodName, arguments, codec);
      }

      // Fall back to default messenger for unhandled channels
      return defaultMessenger.send(channel, message);
    } catch (e) {
      print('Error in send: $e');
      rethrow;
    }
  }

  MessageCodec<Object?> getMessageCodec(String methodName)
  {
    if (methodName == 'updateSettings') return settingsCodec;

    if (methodName == 'onTap' ||
        methodName == 'onLongPress' ||
        methodName == 'onScroll') return gesturesCodec;

    return mapInterfacesCodec;
  }

  String getMethodName(String channel)
  {
      final methodParts = channel.split('.');
      return methodParts.length >= 5 ? methodParts[5].split('\$')[0] : '';
  }

  Future<ByteData?> callWebMethod(String methodName, List<Object?> arguments, MessageCodec<Object?> codec) async {
    switch (methodName) {
      case 'getCameraState':
        return Future.value(codec.encodeMessage([getCameraState()]));
      case 'addStyleLayer':
        final properties = arguments[0] as String;
        final jsArgs = [js.JsObject.jsify(json.decode(properties))];
        final result = mapInstance.callMethod('addLayer', jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[]));
      case 'addStyleImage':
        final properties = arguments[0] as String;
        final jsArgs = [js.JsObject.jsify(json.decode(properties))];
        final result = mapInstance.callMethod('addImage', jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[])); 
      case 'setCamera':
        final cameraOptions = arguments[0] as CameraOptions;
        final Map<String, dynamic> options = {};
        
        // Only add center if coordinates are not null
        if (cameraOptions.center?.coordinates != null) {
          options['center'] = [
            cameraOptions.center!.coordinates.lng,
            cameraOptions.center!.coordinates.lat,
          ];
        }
        
        // Add other fields only if they're not null
        if (cameraOptions.zoom != null) options['zoom'] = cameraOptions.zoom;
        if (cameraOptions.bearing != null) options['bearing'] = cameraOptions.bearing;
        if (cameraOptions.pitch != null) options['pitch'] = cameraOptions.pitch;

        final jsArgs = [js.JsObject.jsify(options)];
        final result = mapInstance.callMethod('jumpTo', jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[]));
      case 'easeTo':
        final cameraOptions = arguments[0] as CameraOptions;
        final animationOptions = arguments[1] as MapAnimationOptions;
        final Map<String, dynamic> options = {};
        
        // Only add center if coordinates are not null
        if (cameraOptions.center?.coordinates != null) {
          options['center'] = [
            cameraOptions.center!.coordinates.lng,
            cameraOptions.center!.coordinates.lat,
          ];
        }
        
        // Add other fields only if they're not null
        if (cameraOptions.zoom != null) options['zoom'] = cameraOptions.zoom;
        if (cameraOptions.bearing != null) options['bearing'] = cameraOptions.bearing;
        if (cameraOptions.pitch != null) options['pitch'] = cameraOptions.pitch;
        if (animationOptions.duration != null) options['duration'] = animationOptions.duration;
        if (animationOptions.startDelay != null) options['startDelay'] = animationOptions.startDelay;
  
        final jsArgs = [js.JsObject.jsify(options)];
        
        final result = mapInstance.callMethod('easeTo', jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[]));
      case 'addStyleSource':
        final sourceId = arguments[0] as String;
        final properties = json.decode(arguments[1] as String);
        final jsArgs = [sourceId, js.JsObject.jsify(properties)];
        final result = mapInstance.callMethod('addSource', jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[]));

      case 'setStyleSourceProperties':
        final sourceId = arguments[0] as String;
        final properties = json.decode(arguments[1] as String);
        // In GL JS, we need to getSource first, then set properties
        final source = mapInstance.callMethod('getSource', [sourceId]);
        for (final key in properties.keys) {
          source?.callMethod('setProperty', [key, js.JsObject.jsify(properties[key])]);
        }
        return Future.value(codec.encodeMessage(<Object?>[]));

      case 'setStyleSourceProperty':
        final sourceId = arguments[0] as String;
        final propertyName = arguments[1] as String;
        final valueStr = arguments[2] as String;
        
        // Get source
        final source = mapInstance.callMethod('getSource', [sourceId]);

        if (source != null && propertyName == 'data') {
          
          try {
            // Parse directly as GeoJSON since it's coming from featureCollection.toJson()
            final geoJson = json.decode(valueStr);
            source.callMethod('setData', [js.JsObject.jsify(geoJson)]);
          } catch (e) {
            print('Error converting GeoJSON: $e');
            print('Value that failed: $valueStr');
          }
        }
        return Future.value(codec.encodeMessage(<Object?>[]));
      case 'updateSettings':
        
        final settings = arguments[0] as LocationComponentSettings;
        // Check if we've already added the control
        if (!hasGeolocateControl) {
          final geolocateControl = js.JsObject(js.context['mapboxgl']['GeolocateControl'], [
            js.JsObject.jsify({
              'positionOptions': {
                'enableHighAccuracy': true
              },
              'trackUserLocation': true,
              'showAccuracyCircle': settings.showAccuracyRing,
              'showUserLocation': settings.enabled,
              'showUserHeading': settings.puckBearingEnabled,
            })
          ]);

          // Set up position event listeners
          geolocateControl.callMethod('on', ['geolocate', js.allowInterop((e) {
            // e is the event object containing the position
            final position = js.JsObject.fromBrowserObject(e);
            final coords = js.JsObject.fromBrowserObject(position['coords']);
            
            final location = {
              'latitude': coords['latitude'],
              'longitude': coords['longitude'],
              'accuracy': coords['accuracy'],
              'bearing': coords['heading'],
              'speed': coords['speed'],
              'timestamp': position['timestamp'],
            };
            
            // Send location back to Flutter
            // sendLocationUpdate(location);
          })]);
          mapInstance.callMethod('addControl', [geolocateControl]);
          hasGeolocateControl = true;
          
          // If puck is enabled, trigger location tracking
          if (settings.enabled != null && settings.enabled!) {
            geolocateControl.callMethod('trigger');
          }
        }
        return Future.value(codec.encodeMessage(<Object?>[]));

      default:
        // For simple methods, just convert to JS objects
        final jsArgs = arguments.map((arg) => js.JsObject.jsify(arg!)).toList();
        final result = mapInstance.callMethod(methodName, jsArgs);
        return Future.value(codec.encodeMessage(<Object?>[]));
    }
  }

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {
    if (callback == null) {
      return;
    }
    ServicesBinding.instance.channelBuffers.push(
      channel,
      data,
      callback,
    );
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {
    print('Setting message handler for channel: $channel');
    if (handler == null) {
      messageHandlers.remove(channel);
    } else {
      messageHandlers[channel] = handler;
    }
    defaultMessenger.setMessageHandler(channel, handler);
  }

  void debugPrintJsObject(dynamic jsObject, [String prefix = '']) {
    if (jsObject == null) return;
    
    try {
      final dartObj = dartify(jsObject);
      print('$prefix${JsonEncoder.withIndent('  ').convert(dartObj)}');
    } catch (e) {
      print('$prefix Failed to convert JS object: $e');
    }
  }
}