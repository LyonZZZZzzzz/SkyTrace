import Foundation

/// Keeps label density stable while the user changes the camera field of view.
struct SkyLabelCapacityPolicy {
    private(set) var capacity = 100

    mutating func update(fieldOfView: Double) -> Int {
        if capacity == 100, fieldOfView > 75 {
            capacity = 90
        }
        if capacity == 90, fieldOfView > 90 {
            capacity = 80
        }
        if capacity == 80, fieldOfView < 85 {
            capacity = 90
        }
        if capacity == 90, fieldOfView < 70 {
            capacity = 100
        }
        return capacity
    }
}

/// Allocates label slots by stability class while preserving source order.
struct SkyLabelCandidateAllocator {
    static func ordered<T>(_ groups: [[T]], capacity: Int) -> [T] {
        guard capacity > 0 else { return [] }
        var result: [T] = []
        result.reserveCapacity(capacity)
        for group in groups {
            for item in group where result.count < capacity {
                result.append(item)
            }
            if result.count == capacity { break }
        }
        return result
    }
}
