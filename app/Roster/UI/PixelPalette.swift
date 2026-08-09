import SwiftUI

/// The pixel-office palette — warm tiled floor, purple pod carpets, wood
/// desks. Original colors in the spirit of the cozy virtual-office genre;
/// nothing sampled from anyone's tileset. Dark mode is the same office
/// after hours: dimmed floor, night windows, glowing screens.
struct PixelPalette {

    let floorA: Color
    let floorB: Color
    let floorLine: Color
    let wall: Color
    let wallTop: Color
    let windowGlass: Color
    let windowLite: Color
    let windowFrame: Color
    let carpet: Color
    let carpetDark: Color
    let carpetLine: Color
    let rug: Color
    let rugDark: Color
    let rugLine: Color
    let loungeCarpet: Color
    let loungeCarpetDark: Color
    let loungeCarpetLine: Color
    let desk: Color
    let deskDark: Color
    let deskLite: Color
    let monitor: Color
    let screenOn: Color
    let screenOff: Color
    let chair: Color
    let chairDark: Color
    let sofa: Color
    let sofaDark: Color
    let sofaLite: Color
    let lowTable: Color
    let lowTableDark: Color
    let plant: Color
    let plantDark: Color
    let pot: Color
    let potDark: Color
    let pingTop: Color
    let pingLine: Color
    let pingDark: Color
    let shadow: Color

    static let day = PixelPalette(
        floorA: Color(hex: 0xEBDCC0), floorB: Color(hex: 0xE4D3B2), floorLine: Color(hex: 0xDCCBA6),
        wall: Color(hex: 0x6E6880), wallTop: Color(hex: 0x8B85A0),
        windowGlass: Color(hex: 0xBBDCE8), windowLite: Color(hex: 0xD8EEF6), windowFrame: Color(hex: 0x565064),
        carpet: Color(hex: 0x928BC8), carpetDark: Color(hex: 0x817AB7), carpetLine: Color(hex: 0x9E97D2),
        rug: Color(hex: 0x8FB6C9), rugDark: Color(hex: 0x7FA6BA), rugLine: Color(hex: 0x9FC4D5),
        loungeCarpet: Color(hex: 0xC9B7D9), loungeCarpetDark: Color(hex: 0xB9A7C9), loungeCarpetLine: Color(hex: 0xD5C4E4),
        desk: Color(hex: 0xB5804C), deskDark: Color(hex: 0x8F6138), deskLite: Color(hex: 0xC69261),
        monitor: Color(hex: 0x2E3247), screenOn: Color(hex: 0xA8E0EE), screenOff: Color(hex: 0x47506B),
        chair: Color(hex: 0x4E5273), chairDark: Color(hex: 0x3D4059),
        sofa: Color(hex: 0xE58544), sofaDark: Color(hex: 0xC96B2F), sofaLite: Color(hex: 0xF09A5C),
        lowTable: Color(hex: 0xC9A26B), lowTableDark: Color(hex: 0xA98249),
        plant: Color(hex: 0x63A85C), plantDark: Color(hex: 0x417F42),
        pot: Color(hex: 0xB06B41), potDark: Color(hex: 0x8E5330),
        pingTop: Color(hex: 0x45A06F), pingLine: Color(hex: 0xF2F0E8), pingDark: Color(hex: 0x357D56),
        shadow: Color(red: 0.24, green: 0.18, blue: 0.10, opacity: 0.18)
    )

    static let night = PixelPalette(
        floorA: Color(hex: 0x4D473C), floorB: Color(hex: 0x464035), floorLine: Color(hex: 0x3E382E),
        wall: Color(hex: 0x3B3748), wallTop: Color(hex: 0x4A4560),
        windowGlass: Color(hex: 0x2E4A5C), windowLite: Color(hex: 0x3A6275), windowFrame: Color(hex: 0x2A2734),
        carpet: Color(hex: 0x5F5A88), carpetDark: Color(hex: 0x524E77), carpetLine: Color(hex: 0x6A6595),
        rug: Color(hex: 0x4E6B7A), rugDark: Color(hex: 0x435D6B), rugLine: Color(hex: 0x587886),
        loungeCarpet: Color(hex: 0x6E6280), loungeCarpetDark: Color(hex: 0x615573), loungeCarpetLine: Color(hex: 0x7A6E8C),
        desk: Color(hex: 0x7A5636), deskDark: Color(hex: 0x5E4026), deskLite: Color(hex: 0x8A6440),
        monitor: Color(hex: 0x1E2130), screenOn: Color(hex: 0x8FD0E4), screenOff: Color(hex: 0x2E3547),
        chair: Color(hex: 0x383C55), chairDark: Color(hex: 0x2B2E42),
        sofa: Color(hex: 0xA55E2F), sofaDark: Color(hex: 0x8A4C22), sofaLite: Color(hex: 0xB56E3E),
        lowTable: Color(hex: 0x8A6E48), lowTableDark: Color(hex: 0x6E5636),
        plant: Color(hex: 0x4A7E45), plantDark: Color(hex: 0x35652F),
        pot: Color(hex: 0x7E4C2E), potDark: Color(hex: 0x653C24),
        pingTop: Color(hex: 0x337753), pingLine: Color(hex: 0xC8C6BE), pingDark: Color(hex: 0x275D40),
        shadow: Color(red: 0, green: 0, blue: 0, opacity: 0.30)
    )

    static func current(for scheme: ColorScheme) -> PixelPalette {
        scheme == .dark ? .night : .day
    }
}

extension Color {
    /// 0xRRGGBB convenience — the palette reads like the mockup's CSS.
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
