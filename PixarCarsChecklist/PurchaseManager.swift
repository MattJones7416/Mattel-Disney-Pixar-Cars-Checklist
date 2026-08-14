import StoreKit
import SwiftUI

@MainActor
final class PurchaseManager: ObservableObject {
    static let shared = PurchaseManager()
    static let proProductID = "com.mattjproductions.PixarCarsChecklist.pro"

    @AppStorage("pixarCarsProUnlockCached") private var cachedUnlock = false

    @Published private(set) var isUnlocked = false
    @Published private(set) var isProcessing = false
    @Published private(set) var product: Product?
    @Published var errorMessage: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    private init() {
        isUnlocked = cachedUnlock
        transactionUpdatesTask = observeTransactionUpdates()
        Task {
            await refreshProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    var displayPrice: String? {
        product?.displayPrice
    }

    func refreshProducts() async {
        do {
            product = try await Product.products(for: [Self.proProductID]).first
        } catch {
            errorMessage = "The Pro unlock is temporarily unavailable. Please try again later."
        }
    }

    @discardableResult
    func purchase() async -> Bool {
        if product == nil {
            await refreshProducts()
        }
        guard let product else {
            errorMessage = "The Pro unlock is not available from the App Store right now."
            return false
        }

        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            switch try await product.purchase() {
            case .success(let result):
                let transaction = try verified(result)
                guard transaction.productID == Self.proProductID,
                      transaction.revocationDate == nil else {
                    errorMessage = "The purchase could not be verified."
                    return false
                }
                setEntitlement(true)
                await transaction.finish()
                return true
            case .pending:
                errorMessage = "The purchase is pending approval."
                return false
            case .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !isUnlocked {
                errorMessage = "No previous Pro purchase was found for this Apple Account."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshEntitlement() async {
        var foundVerifiedUnlock = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.proProductID,
                  transaction.revocationDate == nil else { continue }
            foundVerifiedUnlock = true
            break
        }
        setEntitlement(foundVerifiedUnlock)
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.proProductID else { continue }
                self?.setEntitlement(transaction.revocationDate == nil)
                await transaction.finish()
            }
        }
    }

    private func setEntitlement(_ unlocked: Bool) {
        cachedUnlock = unlocked
        isUnlocked = unlocked
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }

    #if DEBUG
    func setUnlocked(_ unlocked: Bool) {
        setEntitlement(unlocked)
    }
    #endif
}

struct UnlockSheet: View {
    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 58))
                        .foregroundStyle(Color(hex: "D92D20"))
                        .padding(.top, 28)

                    VStack(spacing: 8) {
                        Text("Unlock Pro")
                            .font(.largeTitle.bold())
                        Text("One purchase. Yours for the lifetime of the app.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        proFeature("star.fill", "Favorites and wishlist")
                        proFeature("shippingbox.fill", "Unboxed status and quantities")
                        proFeature("camera.fill", "Collection photos and notes")
                        proFeature("square.and.arrow.up.fill", "Backups and collection exports")
                    }
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding()
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    if purchaseManager.isProcessing {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Button {
                            Task {
                                if await purchaseManager.purchase() {
                                    dismiss()
                                }
                            }
                        } label: {
                            Text(purchaseButtonTitle)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "D92D20"))
                        .frame(maxWidth: 420)
                    }

                    Button("Restore Purchases") {
                        Task {
                            await purchaseManager.restore()
                            if purchaseManager.isUnlocked {
                                dismiss()
                            }
                        }
                    }
                    .disabled(purchaseManager.isProcessing)

                    if let errorMessage = purchaseManager.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Pro Unlock")
            #if os(iOS) || targetEnvironment(macCatalyst)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(purchaseManager.isProcessing)
                }
            }
            .task {
                await purchaseManager.refreshProducts()
            }
        }
        .interactiveDismissDisabled(purchaseManager.isProcessing)
    }

    private var purchaseButtonTitle: String {
        if let price = purchaseManager.displayPrice {
            return "Unlock Pro — \(price)"
        }
        return "Unlock Pro"
    }

    private func proFeature(_ systemImage: String, _ title: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.medium))
    }
}
