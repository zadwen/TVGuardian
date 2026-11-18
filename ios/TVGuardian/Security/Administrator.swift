import Foundation
import Combine
import LocalAuthentication
import CommonCrypto

struct PINRecord: Codable {
    var salt: Data
    var verifier: Data
    var rounds: UInt32
    var failures = 0
    var lockedUntil: Date? = nil
}

enum PINHasher {
    static func derive(_ pin: String, salt: Data, rounds: UInt32) throws -> Data {
        guard rounds >= 600_000, salt.count >= 16 else { throw GuardianError.invalid("Invalid PIN verifier parameters.") }
        let password = Array(pin.utf8)
        var derived = Data(count: 32)
        let status = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress!.assumingMemoryBound(to: Int8.self), password.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        output.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard status == kCCSuccess else { throw GuardianError.unavailable("PIN derivation failed.") }
        return derived
    }
    static func equal(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

@MainActor final class Administrator: ObservableObject {
    @Published private(set) var isUnlocked = false
    @Published private(set) var hasPIN = false
    @Published private(set) var busy = false
    @Published var message: String?
    var onAudit: ((String, String) -> Void)?
    private let account = "administrator.pin.v1"
    private var generation = UUID()
    init() {
        do { hasPIN = try KeychainStore.read(account) != nil }
        catch { message = error.localizedDescription; hasPIN = true }
    }
    func lock() { generation = UUID(); isUnlocked = false }
    func requireUnlocked() throws {
        guard isUnlocked else { throw GuardianError.denied("Unlock the parent administrator session first.") }
    }
    func enroll(pin: String, confirmation: String) async {
        guard !busy else { return }
        let attempt = generation
        busy = true; defer { busy = false }
        do {
            guard try KeychainStore.read(account) == nil else { throw GuardianError.denied("An administrator PIN is already enrolled.") }
            guard pin == confirmation, (6...12).contains(pin.count), pin.allSatisfy({ $0.isASCII && $0.isNumber }),
                  Set(pin).count >= 3, !["123456", "654321", "12345678"].contains(pin) else {
                throw GuardianError.invalid("Use matching 6–12 digit PINs with at least three different digits. Avoid common sequences.")
            }
            let salt = try KeychainStore.random(count: 32)
            let hash = try await Task.detached { try PINHasher.derive(pin, salt: salt, rounds: 600_000) }.value
            try KeychainStore.write(JSONEncoder().encode(PINRecord(salt: salt, verifier: hash, rounds: 600_000)), account: account)
            hasPIN = true; isUnlocked = attempt == generation; message = nil
            onAudit?("enrolled", "Parent administrator PIN enrolled; separate from the Samsung TV PIN.")
        } catch { message = error.localizedDescription }
    }
    func unlock(pin: String) async {
        guard !busy else { return }
        let attempt = generation
        busy = true; defer { busy = false }
        do {
            guard (6...12).contains(pin.count), pin.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let data = try KeychainStore.read(account) else { throw GuardianError.denied("Enter the administrator PIN.") }
            var record = try JSONDecoder().decode(PINRecord.self, from: data)
            if let until = record.lockedUntil, until > Date() {
                throw GuardianError.denied("Too many attempts. Try again after \(until.formatted(date: .omitted, time: .standard)).")
            }
            let salt = record.salt, rounds = record.rounds
            let hash = try await Task.detached { try PINHasher.derive(pin, salt: salt, rounds: rounds) }.value
            if PINHasher.equal(hash, record.verifier) {
                record.failures = 0; record.lockedUntil = nil
                try KeychainStore.write(JSONEncoder().encode(record), account: account)
                isUnlocked = attempt == generation; message = nil; onAudit?("unlocked", "PIN authentication succeeded.")
            } else {
                record.failures += 1
                if record.failures >= 5 {
                    record.lockedUntil = Date().addingTimeInterval(min(900, 30 * pow(2, Double(min(record.failures - 5, 5)))))
                }
                try KeychainStore.write(JSONEncoder().encode(record), account: account)
                onAudit?("denied", "PIN authentication failed.")
                throw GuardianError.denied("Incorrect administrator PIN.")
            }
        } catch { message = error.localizedDescription }
    }
    func enableBiometrics() async throws {
        try requireUnlocked()
        let attempt = generation
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else {
            throw GuardianError.unavailable("Face ID is not available or enrolled on this iPhone.")
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable Face ID for TV Guardian"),
              let domain = context.evaluatedPolicyDomainState else { throw GuardianError.denied("Face ID enrollment was not verified.") }
        guard attempt == generation, isUnlocked else { throw GuardianError.denied("The parent session locked during Face ID verification.") }
        try KeychainStore.write(domain, account: "administrator.biometryDomain")
    }
    func unlockWithFaceID() async {
        guard !busy, hasPIN else { return }
        let attempt = generation
        busy = true; defer { busy = false }
        do {
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID,
                  let enrolled = try KeychainStore.read("administrator.biometryDomain"),
                  let current = context.evaluatedPolicyDomainState, PINHasher.equal(enrolled, current) else {
                throw GuardianError.denied("Face ID enrollment changed or is unavailable. Use the parent PIN.")
            }
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock TV Guardian parental settings") else {
                throw GuardianError.denied("Face ID was not authenticated.")
            }
            isUnlocked = attempt == generation; message = nil; onAudit?("unlocked", "Face ID authentication succeeded.")
        } catch { message = error.localizedDescription }
    }
}
