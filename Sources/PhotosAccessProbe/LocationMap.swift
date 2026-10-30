import SwiftUI
import MapKit

/// Native map with wheel zoom scoped to this view. Dragging still pans the map.
struct LocationMap: NSViewRepresentable {
    let location: PhotoLocation

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.showsZoomControls = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        context.coordinator.install(on: map)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        guard context.coordinator.location != location else { return }
        context.coordinator.location = location
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        map.removeAnnotations(map.annotations)
        let pin = MKPointAnnotation()
        pin.coordinate = coordinate
        pin.title = "Proposed location"
        map.addAnnotation(pin)
        map.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2_000, longitudinalMeters: 2_000), animated: false)
    }

    static func dismantleNSView(_ map: MKMapView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        var location: PhotoLocation?
        private var wheelMonitor: Any?

        func install(on map: MKMapView) {
            removeMonitor()
            wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak map] event in
                let handled = MainActor.assumeIsolated {
                    guard let map, let window = map.window, event.window === window,
                          !map.isHiddenOrHasHiddenAncestor,
                          map.visibleRect.contains(map.convert(event.locationInWindow, from: nil)) else { return false }
                    // Consume wheel events here, before MapKit's internal views can pan
                    // or an enclosing scroll view can move the review page.
                    let delta = event.scrollingDeltaY
                    if delta != 0 {
                        let sensitivity = event.hasPreciseScrollingDeltas ? 0.012 : 0.12
                        let factor = exp(max(-1, min(1, -Double(delta) * sensitivity)))
                        let camera = map.camera.copy() as! MKMapCamera
                        camera.centerCoordinateDistance = max(40, min(40_000_000, camera.centerCoordinateDistance * factor))
                        map.setCamera(camera, animated: false)
                    }
                    return true
                }
                return handled ? nil : event
            }
        }

        func removeMonitor() {
            if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
            wheelMonitor = nil
        }
    }
}
