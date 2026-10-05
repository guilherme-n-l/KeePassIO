import KPModel
import KPOTP
import Observation
import PhotosUI
import SwiftUI
import UIKit

/// One-time code setup for the entry editor: the state and actions shared
/// by the section (inside the editor's Form) and the camera and setup-key
/// screens (presented from the editor itself).
///
/// The screens can't be presented from the section: a sheet attached to a
/// view inside a Form is dismissed as soon as the Form re-evaluates that
/// row, which opening the camera does, so the camera closed right away.
///
/// The code is stored as KeePassXC does, an otpauth:// URI in a protected
/// "otp" field, so KeePassXC and other KeePass apps read it too.
@MainActor
@Observable
final class OTPSetup {
    var isScanning = false
    var isEnteringManually = false
    var message: String?

    static func otp(of entry: Entry) -> OTP? {
        try? OTP(fields: entry.fields.mapValues { $0.reveal() })
    }

    /// Sets up the code from a scanned or pasted otpauth:// link.
    func use(_ payload: String, in entry: Binding<Entry>) {
        if payload.lowercased().hasPrefix("otpauth-migration:") {
            message = String(
                localized:
                    "That's a Google Authenticator export, which holds several accounts. Scan the site's own QR code instead."
            )
            return
        }
        do {
            let parsed = try OTP(uri: payload)
            setURI(parsed.uri, in: entry)
        } catch {
            message = String(localized: "That QR code isn't a one-time code setup (otpauth://).")
        }
    }

    func useImage(_ item: PhotosPickerItem, in entry: Binding<Entry>) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            message = String(localized: "That image couldn't be read.")
            return
        }
        let payloads = await QRCodeReader.payloads(in: image)
        guard let payload = payloads.first(where: { $0.lowercased().hasPrefix("otpauth") }) ?? payloads.first else {
            message = String(localized: "No QR code found in that image.")
            return
        }
        use(payload, in: entry)
    }

    func pasteLink(in entry: Binding<Entry>) {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else {
            message = String(localized: "The clipboard is empty.")
            return
        }
        use(text, in: entry)
    }

    /// Writes the code in KeePassXC's format, dropping the older
    /// "TOTP Seed" / "TOTP Settings" fields so there's one source of truth.
    func setURI(_ uri: String?, in entry: Binding<Entry>) {
        message = nil
        entry.wrappedValue.fields["TOTP Seed"] = nil
        entry.wrappedValue.fields["TOTP Settings"] = nil
        entry.wrappedValue.fields["otp"] = uri.map { .protected(SecretString($0)) }
    }
}

/// The editor's one-time code section: the current code, or the ways to
/// set one up.
struct OTPSetupSection: View {
    @Binding var entry: Entry
    let setup: OTPSetup
    @State private var photo: PhotosPickerItem?

    var body: some View {
        Section {
            if let otp = OTPSetup.otp(of: entry) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("Current Code") {
                        Text(otp.code(at: context.date))
                            .font(.body.monospaced())
                    }
                }
                Button("Remove One-Time Code", role: .destructive) {
                    setup.setURI(nil, in: $entry)
                }
            } else {
                if QRCodeReader.canScanWithCamera {
                    Button("Scan QR Code", systemImage: "qrcode.viewfinder") { setup.isScanning = true }
                        .accessibilityIdentifier("editor.otp.scan")
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose QR Code Image", systemImage: "photo")
                }
                Button("Paste Setup Link", systemImage: "doc.on.clipboard") { setup.pasteLink(in: $entry) }
                Button("Enter Secret Manually", systemImage: "keyboard") { setup.isEnteringManually = true }
                    .accessibilityIdentifier("editor.otp.manual")
            }
        } header: {
            Text("One-Time Code")
        } footer: {
            if let message = setup.message {
                Text(message).foregroundStyle(.red)
            } else if OTPSetup.otp(of: entry) == nil {
                Text(
                    "For sites with two-factor authentication: scan or choose the QR code they show, or type the setup key."
                )
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task { await setup.useImage(item, in: $entry) }
        }
    }
}

/// The camera and setup-key screens, attached to the editor itself (not
/// inside its Form; see `OTPSetup`).
struct OTPSetupScreens: ViewModifier {
    @Binding var entry: Entry
    @Bindable var setup: OTPSetup

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $setup.isScanning) {
                NavigationStack {
                    QRCodeScannerView { payload in
                        setup.isScanning = false
                        setup.use(payload, in: $entry)
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan QR Code")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { setup.isScanning = false }
                        }
                    }
                }
            }
            .sheet(isPresented: $setup.isEnteringManually) {
                NavigationStack {
                    ManualOTPView(issuer: entry.title, account: entry.userName) { otp in
                        setup.setURI(otp.uri, in: $entry)
                    }
                }
            }
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
