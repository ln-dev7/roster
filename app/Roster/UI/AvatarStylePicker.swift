import SwiftUI

/// The little wardrobe — a live voxel portrait and four swatch rows.
/// Shared by the welcome card and Settings → General. It writes the
/// YouStyle defaults; RoomView observes the same keys, so the room
/// re-dresses the moment a swatch is clicked. Agents keep their hashed
/// outfits — this is only ever about you.
struct AvatarStylePicker: View {

    @AppStorage(YouStyle.skinKey) private var skin = Int(YouStyle.defaultSkin)
    @AppStorage(YouStyle.hairKey) private var hair = Int(YouStyle.defaultHair)
    @AppStorage(YouStyle.shirtKey) private var shirt = Int(YouStyle.defaultShirt)
    @AppStorage(YouStyle.pantsKey) private var pants = Int(YouStyle.defaultPants)

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // The same slowly turning portrait as the detail card —
            // VoxelPortrait rebuilds itself whenever the look changes,
            // which makes it a live mirror of the swatches.
            VoxelPortrait(look: SpriteLook(
                skin: Color(hex: UInt32(clamping: skin)),
                hair: Color(hex: UInt32(clamping: hair)),
                shirt: Color(hex: UInt32(clamping: shirt)),
                pants: Color(hex: UInt32(clamping: pants))
            ))
            .frame(width: 76, height: 96)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                row("Skin", palette: YouStyle.skins, selection: $skin)
                row("Hair", palette: YouStyle.hairs, selection: $hair)
                row("Shirt", palette: YouStyle.shirts, selection: $shirt)
                row("Pants", palette: YouStyle.pants, selection: $pants)
            }
        }
    }

    private func row(
        _ title: LocalizedStringKey,
        palette: [UInt32],
        selection: Binding<Int>
    ) -> some View {
        GridRow {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            HStack(spacing: 6) {
                ForEach(palette, id: \.self) { hex in
                    swatch(hex, isOn: selection.wrappedValue == Int(hex)) {
                        selection.wrappedValue = Int(hex)
                    }
                }
            }
        }
    }

    private func swatch(
        _ hex: UInt32, isOn: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(hex: hex))
                .frame(width: 20, height: 20)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            isOn ? Color.accentColor : .primary.opacity(0.12),
                            lineWidth: isOn ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: String(format: "#%06X", hex)))
    }
}

#Preview {
    AvatarStylePicker()
        .padding()
}
