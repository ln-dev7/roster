import SwiftUI

/// One colleague's outfit — skin, hair, shirt, pants — derived
/// deterministically from the project, so "circle" wears the same shirt
/// on every launch. The voxel body (VoxelAgents.swift) dresses itself
/// with these colors; the flat pixel sprite this type once painted has
/// retired in favor of the 3D characters.
struct SpriteLook: Equatable {

    let skin: Color
    let hair: Color
    let shirt: Color
    let pants: Color

    private static let skins: [Color] = [
        Color(hex: 0xF2C9A0), Color(hex: 0xC68642), Color(hex: 0x8D5524),
    ]
    private static let hairs: [Color] = [
        Color(hex: 0x1F1F1F), Color(hex: 0x2E2A28), Color(hex: 0x6B4A2F),
        Color(hex: 0xD9A441), Color(hex: 0x8C8C8C),
    ]
    private static let shirts: [Color] = [
        Color(hex: 0x4C8BF5), Color(hex: 0x7C6FD0), Color(hex: 0xE08A3C),
        Color(hex: 0xD5525C), Color(hex: 0x43A385), Color(hex: 0xC4699E),
    ]
    private static let pantsChoices: [Color] = [
        Color(hex: 0x31374F), Color(hex: 0x3A3F52), Color(hex: 0x4A3A30),
    ]

    /// Stable across launches: djb2 over the workstation's id (its
    /// repository path — two folders both named "api" hash apart); the
    /// seat slot shifts the shirt so two agents on one desk never twin.
    static func derive(from name: String, slot: Int = 0) -> SpriteLook {
        var hash: UInt64 = 5381
        for byte in name.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return SpriteLook(
            skin: skins[Int(hash % UInt64(skins.count))],
            hair: hairs[Int((hash / 7) % UInt64(hairs.count))],
            shirt: shirts[(Int((hash / 13) % UInt64(shirts.count)) + slot) % shirts.count],
            pants: pantsChoices[Int((hash / 3) % UInt64(pantsChoices.count))]
        )
    }

    /// Your own character, fixed.
    static let you = SpriteLook(
        skin: Color(hex: 0x8D5524),
        hair: Color(hex: 0x101010),
        shirt: Color(hex: 0x3A3F52),
        pants: Color(hex: 0x23263A)
    )
}

/// The floating name pill — the one Gather-ism everyone reads instantly.
/// Regular UI (crisp, unscaled): the status color is the same one the
/// sidebar uses.
struct NamePill: View {

    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: name)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.85)))
        .foregroundStyle(.white)
        .fixedSize()
    }
}
