import SwiftUI

/// One little colleague: a 12×17 (logical pixels) sprite drawn entirely in
/// code — hair, face, shirt, pants — with three poses. The look derives
/// deterministically from the project name, so "circle" wears the same
/// shirt on every launch.
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

    /// Stable across launches: djb2 over the name; the seat slot shifts
    /// the shirt so two agents on one desk never twin.
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

enum SpritePose: Equatable {
    case seated
    case standing
    /// `frame` alternates 0/1 for the little step.
    case walking(frame: Int)
}

/// The sprite itself. Feet sit at the bottom-center of its frame.
struct PixelSprite: View {

    let look: SpriteLook
    let pose: SpritePose
    /// Logical-pixel → point scale, shared with the room.
    let scale: CGFloat
    let shadowColor: Color

    /// Logical sprite box: 12 wide, 17 tall (1 px of ground shadow).
    static let logicalSize = CGSize(width: 12, height: 17)

    var body: some View {
        Canvas { context, _ in
            context.scaleBy(x: scale, y: scale)

            func px(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: Color) {
                context.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: .color(color))
            }

            switch pose {
            case .seated:
                // Compact: torso + head only, on the chair.
                px(2, 8, 8, 5, look.shirt)
                px(3, 4, 6, 4, look.skin)
                px(3, 2, 6, 3, look.hair)
                px(2, 4, 1, 2, look.hair)
                px(9, 4, 1, 2, look.hair)

            case .standing, .walking:
                var bob: CGFloat = 0
                if case .walking(let frame) = pose, frame == 1 { bob = -1 }

                context.fill(
                    Path(ellipseIn: CGRect(x: 2, y: 14.6, width: 8, height: 1.8)),
                    with: .color(shadowColor)
                )

                // Legs — alternating on the walk.
                switch pose {
                case .walking(let frame) where frame == 1:
                    px(3, 11, 2, 4, look.pants)
                    px(7, 12, 2, 4, look.pants)
                case .walking:
                    px(3, 12, 2, 4, look.pants)
                    px(7, 11, 2, 4, look.pants)
                default:
                    px(3, 12, 2, 4, look.pants)
                    px(7, 12, 2, 4, look.pants)
                }

                px(2, 7 + bob, 8, 5, look.shirt)          // torso
                px(1, 7 + bob, 1, 3, look.skin)           // arms
                px(10, 7 + bob, 1, 3, look.skin)
                px(3, 3 + bob, 6, 4, look.skin)           // face
                px(3, 1 + bob, 6, 2, look.hair)           // hair
                px(2, 3 + bob, 1, 2, look.hair)
                px(9, 3 + bob, 1, 2, look.hair)
            }
        }
        .frame(width: Self.logicalSize.width * scale,
               height: Self.logicalSize.height * scale)
    }
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
