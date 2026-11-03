import Foundation

/// One entry inside a display override's `scale-resolutions` array.
///
/// The 8-byte form is a 1× timing. The 12-byte form is the HiDPI timing used by
/// one-key-hidpi (`<8-byte doubled size><00 00 00 01>`): the first two big-endian
/// words are the framebuffer, and the third word marks the 2× variant.
public enum ScaleResolution: Equatable, Sendable {
    case lowDPI(width: Int, height: Int)
    case hiDPI(pixelWidth: Int, pixelHeight: Int)

    public var byteCount: Int {
        switch self {
        case .lowDPI:
            return 8
        case .hiDPI:
            return 12
        }
    }
}

public enum ScaleResolutionCodec {
    public static func encode(_ resolution: ScaleResolution) -> Data {
        switch resolution {
        case let .lowDPI(width, height):
            return words([UInt32(width), UInt32(height)])
        case let .hiDPI(pixelWidth, pixelHeight):
            return words([UInt32(pixelWidth), UInt32(pixelHeight), 1])
        }
    }

    public static func decode(_ data: Data) -> ScaleResolution? {
        let values = readWords(data)
        switch values.count {
        case 2:
            return .lowDPI(width: Int(values[0]), height: Int(values[1]))
        case 3 where values[2] == 1:
            return .hiDPI(pixelWidth: Int(values[0]), pixelHeight: Int(values[1]))
        default:
            return nil
        }
    }

    /// LoDPI at the looks-like size, HiDPI at 2×, and a 1× timing of the framebuffer
    /// so the panel has a real mode to scale from.
    public static func entries(for mode: ScaledMode) -> [ScaleResolution] {
        [
            .lowDPI(width: mode.logicalWidth, height: mode.logicalHeight),
            .hiDPI(pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight),
            .lowDPI(width: mode.pixelWidth, height: mode.pixelHeight),
        ]
    }

    private static func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        return data
    }

    private static func readWords(_ data: Data) -> [UInt32] {
        guard data.count % 4 == 0, !data.isEmpty else {
            return []
        }
        var values: [UInt32] = []
        var index = 0
        while index + 4 <= data.count {
            let word =
                (UInt32(data[index]) << 24)
                | (UInt32(data[index + 1]) << 16)
                | (UInt32(data[index + 2]) << 8)
                | UInt32(data[index + 3])
            values.append(word)
            index += 4
        }
        return values
    }
}
