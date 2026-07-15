import StoreKit
import SwiftUI

struct SubscriptionUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var subscription: AppleSubscriptionManager

    let currentEntryCount: Int
    let requiredTier: SubscriptionTier

    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 42))
                            .foregroundColor(.wanderAccent)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(lang.s.subUpgradeTitle)
                            .font(.wanderSerif(28))
                            .foregroundColor(.wanderInk)
                        Text(lang.s.subUpgradeDesc)
                            .font(.system(size: 14))
                            .foregroundColor(.wanderMuted)
                            .lineSpacing(4)
                    }
                    .padding(.top, 24)

                    currentPlanCard

                    VStack(spacing: 12) {
                        ForEach(SubscriptionTier.paidTiers) { tier in
                            tierButton(tier)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer(minLength: 40)
                }
                .padding(24)
            }
            .background(Color.wanderWarm)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.wanderInk)
                            .frame(width: 36, height: 36)
                            .background(Color.wanderBlush)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    private var currentPlanCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lang.s.subCurrentPlan)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.wanderMuted)
            Text(lang.s.subFreePlan)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.wanderInk)
            Text(lang.s.subEntriesUsed(currentEntryCount, SubscriptionTier.free.maxEntries))
                .font(.system(size: 13))
                .foregroundColor(.wanderMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.wanderBlush.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func tierButton(_ tier: SubscriptionTier) -> some View {
        let isRecommended = tier == requiredTier
        return Button {
            Task {
                let success = await subscription.purchase(tier)
                if success {
                    dismiss()
                } else if let message = subscription.lastError {
                    errorMessage = message
                }
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("\(subscription.displayPrice(for: tier))\(lang.s.subPriceMonthly)")
                            .font(.system(size: 21, weight: .bold))
                        if isRecommended {
                            Text(lang.s.subAutoUpgrade)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.wanderAccent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(lang.s.subEntriesUsed(currentEntryCount, tier.maxEntries))
                        .font(.system(size: 13))
                        .foregroundColor(isRecommended ? Color.wanderCream.opacity(0.82) : .wanderMuted)
                }
                Spacer()
                if subscription.isPurchasing {
                    ProgressView().tint(isRecommended ? .wanderCream : .wanderAccent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundColor(isRecommended ? .wanderCream : .wanderInk)
            .padding(18)
            .background(isRecommended ? Color.wanderInk : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(isRecommended ? 0.14 : 0.05), radius: 8, y: 3)
        }
        .disabled(subscription.isPurchasing)
    }
}

struct SubscriptionManagementCard: View {
    @EnvironmentObject var lang: LanguageManager
    @EnvironmentObject var subscription: AppleSubscriptionManager

    let currentEntryCount: Int

    var body: some View {
        if subscription.state.isPaid {
            VStack(alignment: .leading, spacing: 14) {
                Label(lang.s.subManageSubscription, systemImage: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.wanderMuted)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lang.s.subCurrentPlan)
                            .font(.system(size: 12))
                            .foregroundColor(.wanderMuted)
                        Text(subscription.displayPrice(for: subscription.state.tier) + lang.s.subPriceMonthly)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.wanderInk)
                        Text(subscription.state.source == .server ? lang.s.subWhitelistActive : lang.s.subAppleActive)
                            .font(.system(size: 12))
                            .foregroundColor(.wanderMuted)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(lang.s.subEntriesUsed(currentEntryCount, subscription.state.tier.maxEntries))
                        .font(.system(size: 13))
                        .foregroundColor(.wanderMuted)
                    GeometryReader { geo in
                        let maxEntries = subscription.state.tier.maxEntries
                        let progress = maxEntries == Int.max ? 0.5 : CGFloat(currentEntryCount) / CGFloat(max(maxEntries, 1))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.wanderBlush).frame(height: 5)
                            Capsule().fill(Color.wanderAccent)
                                .frame(width: geo.size.width * min(progress, 1), height: 5)
                        }
                    }
                    .frame(height: 5)
                }

                Divider()

                if subscription.state.source == .apple {
                    Button {
                        subscription.openManageSubscriptions()
                    } label: {
                        ActionContent(icon: "arrow.up.forward.app.fill", title: lang.s.subManageApple, subtitle: lang.s.subManageAppleDesc)
                    }
                }
            }
            .padding(20)
            .cardStyle()
        }
    }
}

private struct ActionContent: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.wanderAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(.wanderInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.wanderMuted)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(.wanderMuted)
        }
        .padding(.vertical, 8)
    }
}
