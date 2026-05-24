import CoreGraphics

let event = CGEvent(source: nil)
let location = event?.location ?? .zero
print(String(format: "%.0f", location.x))
print(String(format: "%.0f", location.y))
