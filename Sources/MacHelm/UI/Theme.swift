import SwiftUI

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

struct StatusDot: View {
    let status: MachineStatus
    var body: some View {
        Circle().fill(status.color).frame(width: 9, height: 9)
            .shadow(color: status == .online ? status.color.opacity(0.7) : .clear, radius: 4)
    }
}

struct StatusPill: View {
    let status: MachineStatus
    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: status)
            Text(status.label).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(status.color.opacity(0.14)))
    }
}

struct RingGauge: View {
    var value: Double       // 0...1
    var label: String
    var detail: String
    var tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(tint.opacity(0.16), lineWidth: 9)
                Circle().trim(from: 0, to: max(0.002, min(1, value)))
                    .stroke(tint.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth, value: value)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
            }
            .frame(width: 86, height: 86)
            Text(label).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct MiniBar: View {
    var value: Double
    var tint: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule().fill(tint.gradient).frame(width: max(4, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 5)
        .animation(.smooth, value: value)
    }
}

struct ActionTile: View {
    var title: String
    var icon: String
    var tint: Color = .accentColor
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22, weight: .medium)).foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.14)))
                Text(title).font(.caption.weight(.medium)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct OutputBox: View {
    var text: String
    var minHeight: CGFloat = 80
    var body: some View {
        ScrollView {
            Text(text.isEmpty ? " " : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(minHeight: minHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.28)))
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).tracking(0.8)
    }
}

/// The MacHelm mark, drawn in vector so it stays crisp at any size.
struct HelmMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let cyan = Color(red: 0.49, green: 0.97, blue: 1)
            let shading = GraphicsContext.Shading.color(.white)
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)) }
            ctx.stroke(circle(s * 0.26), with: shading, lineWidth: s * 0.05)
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4 + .pi / 8
                var p = Path()
                p.move(to: CGPoint(x: c.x + cos(a) * s * 0.07, y: c.y + sin(a) * s * 0.07))
                p.addLine(to: CGPoint(x: c.x + cos(a) * s * 0.335, y: c.y + sin(a) * s * 0.335))
                ctx.stroke(p, with: shading, style: StrokeStyle(lineWidth: s * 0.034, lineCap: .round))
                let hp = CGPoint(x: c.x + cos(a) * s * 0.36, y: c.y + sin(a) * s * 0.36)
                ctx.fill(Path(ellipseIn: CGRect(x: hp.x - s * 0.046, y: hp.y - s * 0.046, width: s * 0.092, height: s * 0.092)),
                         with: .color(i % 2 == 0 ? cyan : .white))
            }
            ctx.fill(circle(s * 0.088), with: .color(cyan))
        }
        .shadow(color: Color(red: 0.3, green: 0.9, blue: 1).opacity(0.6), radius: 6)
    }
}

struct BrandBadge: View {
    var size: CGFloat = 34
    var body: some View {
        HelmMark().frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.22), Color(red: 0.42, green: 0.17, blue: 0.77)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
    }
}
