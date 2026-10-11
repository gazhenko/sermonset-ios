import Testing
import Foundation
@testable import SermonSetCore
@Suite @MainActor struct VenueTests {
    @Test func noPreciseListenerStorage() throws {
        let candidate = VenueCandidate(churchName: "Church",city: "City",publicLatitude: 42.123456,publicLongitude: -73.654321)
        #expect(candidate.venue(precision: .city).latitude == nil)
        #expect(candidate.venue(precision: .city).churchName == nil)
        #expect(candidate.venue(precision: .privateLocation).city == nil)
        #expect(candidate.venue(precision: .venue).latitude == 42.12)
        let store = SermonStore(configuration: .preview)
        var sermon = store.libraryEntries[0].sermon
        sermon.venue = Venue(churchName: "typed",city: "city",latitude: 42.123456,longitude: -73.654321,precision: .privateLocation)
        try store.updateSermon(sermon)
        #expect(store.sermon(sermon.id)?.venue?.latitude == nil)
        #expect(store.sermon(sermon.id)?.venue?.city == nil)
    }
}
