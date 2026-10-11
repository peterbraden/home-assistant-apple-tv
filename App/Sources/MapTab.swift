import HomeAssistantKit
import MapKit
import SwiftUI

/// People, device trackers and zones on a map, with a list of who is where.
struct MapTab: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        let located = store.locatedEntities
        HStack(spacing: 0) {
            Map(initialPosition: .automatic) {
                ForEach(store.zones) { zone in
                    if let coordinate = zone.coordinate {
                        MapCircle(center: coordinate, radius: zone.attributes["radius"]?.doubleValue ?? 100)
                            .foregroundStyle(.orange.opacity(0.2))
                            .stroke(.orange, lineWidth: 2)
                        Marker(zone.friendlyName, systemImage: "house.fill", coordinate: coordinate)
                            .tint(.orange)
                    }
                }
                ForEach(located) { entity in
                    if let coordinate = entity.coordinate {
                        Annotation(entity.friendlyName, coordinate: coordinate) {
                            PersonPin(entity: entity)
                        }
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .id(located.map(\.entityId))  // Refit the map when the set of people changes.

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    ForEach(located) { entity in
                        Button {
                            store.presentedEntity = EntitySelection(id: entity.entityId)
                        } label: {
                            HStack(spacing: 24) {
                                PersonPin(entity: entity)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entity.friendlyName).font(.headline)
                                    Text(store.placeName(for: entity)).foregroundStyle(.secondary)
                                    if let changed = entity.lastChanged.flatMap(HADate.parse) {
                                        Text("since \(changed, format: .relative(presentation: .named))")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .padding(40)
            }
            .frame(width: 560)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct PersonPin: View {
    let entity: HAEntity

    var body: some View {
        ZStack {
            Circle().fill(entity.state == "home" ? Color.green : Color.blue)
            if let picture = entity.entityPicture {
                AuthorizedImage(path: picture, contentMode: .fill)
                    .clipShape(Circle())
                    .padding(4)
            } else {
                Image(systemName: entity.domain == "person" ? "person.fill" : "iphone")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 70, height: 70)
        .shadow(radius: 6)
    }
}

extension HAEntity {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = attributes["latitude"]?.doubleValue,
              let longitude = attributes["longitude"]?.doubleValue else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension HomeStore {
    /// People with a location, plus device trackers that don't belong to a person.
    var locatedEntities: [HAEntity] {
        let all = entities.values.filter { $0.coordinate != nil && !registry.isHidden($0.entityId) }
        let people = all.filter { $0.domain == "person" }
        let ownedTrackers = Set(people.flatMap {
            $0.attributes["device_trackers"]?.arrayValue?.compactMap(\.stringValue) ?? []
        })
        let trackers = all.filter { $0.domain == "device_tracker" && !ownedTrackers.contains($0.entityId) }
        return (people + trackers).sorted {
            ($0.domain == "person" ? 0 : 1, $0.friendlyName) < ($1.domain == "person" ? 0 : 1, $1.friendlyName)
        }
    }

    var zones: [HAEntity] {
        entities.values.filter { $0.domain == "zone" && $0.attributes["passive"]?.boolValue != true }
            .sorted { $0.friendlyName < $1.friendlyName }
    }

    /// "Home", a zone's name, or "Away".
    func placeName(for entity: HAEntity) -> String {
        switch entity.state {
        case "home": return "Home"
        case "not_home": return "Away"
        default: return entity.displayState
        }
    }
}
