import SkyTraceUI
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private let pages = [
        OnboardingPage(
            symbol: "sparkles",
            title: "把整片天空握在手中",
            message: "拖动浏览星空，捏合缩放，双击随时回到舒适视角。"
        ),
        OnboardingPage(
            symbol: "location.fill",
            title: "从你的位置看宇宙",
            message: "允许定位以计算地平线方向，也可以随时手动选择城市。"
        ),
        OnboardingPage(
            symbol: "clock.arrow.circlepath",
            title: "让时间向前或倒流",
            message: "查看任意日期和时刻的天体位置，发现今晚最适合观察的目标。"
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.skyBackground, Color(red: 0.01, green: 0.09, blue: 0.17)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "开始观星" : "继续")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(Color.skyBackground)
                        .background(Color.skyCyan, in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 28)

                Button("稍后探索") {
                    onFinish()
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 18)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func pageView(_ item: OnboardingPage) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.skyCyan.opacity(0.12))
                    .frame(width: 170, height: 170)
                Circle()
                    .stroke(Color.skyCyan.opacity(0.25), lineWidth: 1)
                    .frame(width: 132, height: 132)
                Image(systemName: item.symbol)
                    .font(.system(size: 58, weight: .light))
                    .foregroundStyle(Color.skyCyan)
            }

            Text(item.title)
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(item.message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)
        }
        .padding(.bottom, 44)
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let message: String
}
