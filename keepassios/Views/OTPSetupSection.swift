import KPModel
import KPOTP
import PhotosUI
import SwiftUI
import UIKit

/// The entry editor's one-time code section: shows the current code, and
/// sets one up from a QR code (camera or image), a pasted otpauth:// link
/// or a secret typed in by hand.
///
/// The code is stored as KeePassXC does, an otpauth:// URI in a protected
/// "otp" field, so KeePassXC and other KeePass apps read it too.
struct OTPSetupSection: View {
    @Binding var entry: Entry
    @State private var isScanning = false
    @State private var isEnteringManually = false
    @State private var photo: PhotosPickerItem?
    @State private var message: String?

    private var otp: OTP? {
        try? OTP(fields: entry.fields.mapValues { $0.reveal() })
    }

    var body: some View {
        Section {
            if let otp {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("Current Code") {
                        Text(otp.code(at: context.date))
                            .font(.body.monospaced())
                    }
                }
                Button("Remove One-Time Code", role: .destructive) {
                    setURI(nil)
                }
            } else {
                if QRCodeReader.canScanWithCamera {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") { isScanning = true }
                        .accessibilityIdentifier("editor.otp.scan")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose QR Code Image", systemImage: "photo")
                }
                Button("Paste Setup Link", systemImage: "doc.on.clipboard") { pasteLink() }
                Button("Enter Secret Manually", systemImage: "keyboard") { isEnteringManually = true }
                    .accessibilityIdentifier("editor.otp.manual")
            }
        } header: {
            Text("One-Time Code")
        } footer: {
            if let message {
                Text(message).foregroundStyle(.red)
            } else if otp == nil {
                Text(
                    "For sites with two-factor authentication: scan or choose the QR code they show, or type the setup key."
                )
            }
        }
        .sheet(isPresented: $isScanning) {
            NavigationStack {
                QRCodeScannerView { payload in
                    isScanning = false
                    use(payload)
                }
                .ignoresSafeArea()
                .navigationTitle("Scan QR Code")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isScanning = false }
                    }
                }
            }
        }
        .sheet(isPresented: $isEnteringManually) {
            NavigationStack {
                ManualOTPView(issuer: entry.title, account: entry.userName) { otp in
                    setURI(otp.uri)
                }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await useImage(item) }
        }
    }

    /// Sets up the code from a scanned or pasted otpauth:// link.
    private func use(_ payload: String) {
        if payload.lowercased().hasPrefix("otpauth-migration:") {
            message = String(
                localized:
                    "That's a Google Authenticator export, which holds several accounts. Scan the site's own QR code instead."
            )
            return
        }
        do {
            let parsed = try OTP(uri: payload)
            setURI(parsed.uri)
        } catch {
            message = String(localized: "That QR code isn't a one-time code setup (otpauth://).")
        }
    }

    private func useImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            message = String(localized: "That image couldn't be read.")
            return
        }
        let payloads = await QRCodeReader.payloads(in: image)
        guard let payload = payloads.first(where: { $0.lowercased().hasPrefix("otpauth") }) ?? payloads.first else {
            message = String(localized: "No QR code found in that image.")
            return
        }
        use(payload)
    }

    private func pasteLink() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else {
            message = String(localized: "The clipboard is empty.")
            return
        }
        use(text)
    }

    /// Writes the code in KeePassXC's format, dropping the older
    /// "TOTP Seed" / "TOTP Settings" fields so there's one source of truth.
    private func setURI(_ uri: String?) {
        message = nil
        entry.fields["TOTP Seed"] = nil
        entry.fields["TOTP Settings"] = nil
        entry.fields["otp"] = uri.map { .protected(SecretString($0)) }
    }
}

/// Typing in a setup key, with the options sites mention alongside it.
private struct ManualOTPView: View {
    @Environment(\.dismiss) private var dismiss
    let issuer: String
    let account: String
    let onDone: (OTP) -> Void

    @State private var secret = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm = OTP.Algorithm.sha1
    @State private var isSteam = false

    private var configured: OTP? {
        try? OTP(
            base32Secret: secret,
            algorithm: isSteam ? .sha1 : algorithm,
            kind: isSteam ? .steam : .totp(digits: digits),
            period: isSteam ? 30 : period,
            issuer: issuer.isEmpty ? nil : issuer,
            account: account.isEmpty ? nil : account
        )
    }

    var body: some View {
        Form {
            Section {
                TextField("Setup Key", text: $secret, axis: .vertical)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("otp.secret")
            } footer: {
                if !secret.isEmpty, configured == nil {
                    Text("That isn't a valid setup key (letters A–Z and digits 2–7).").foregroundStyle(.red)
                } else if let configured {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Current code: \(configured.code(at: context.date))")
                    }
                }
            }
            Section {
                Toggle("Steam Guard", isOn: $isSteam)
                if !isSteam {
                    Picker("Digits", selection: $digits) {
                        ForEach([6, 7, 8], id: \.self) { Text("\($0)").tag($0) }
                    }
                    Picker("Period", selection: $period) {
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                    }
                    Picker("Algorithm", selection: $algorithm) {
                        ForEach(OTP.Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            } header: {
                Text("Options")
            } footer: {
                Text("Most sites use the defaults: 6 digits, 30 seconds, SHA1.")
            }
        }
        .navigationTitle("Setup Key")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    if let configured {
                        onDone(configured)
                        dismiss()
                    }
                }
                .disabled(configured == nil)
                .accessibilityIdentifier("otp.done")
            }
        }
    }
}
