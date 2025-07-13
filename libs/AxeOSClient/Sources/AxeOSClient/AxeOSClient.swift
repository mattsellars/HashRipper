
import Foundation

public enum AxeOSClientError: Error {
    case deviceResponseError(String)
    case unknownError(String)
}


public class AxeOSClient: Identifiable {
    private var urlSession: URLSession

    public var id: String { deviceIpAddress }
    
    public let deviceIpAddress: String
    
    let baseURL: URL

    public init(deviceIpAddress: String, urlSession: URLSession) {
        self.baseURL = URL(string: "http://\(deviceIpAddress)")!
        self.deviceIpAddress = deviceIpAddress
        self.urlSession = urlSession
    }

    public func configureURLSession(_ urlSession: URLSession) {
        self.urlSession = urlSession
    }

    public func restartClient() async -> Result<Bool, AxeOSClientError> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system/restart"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknownError("Unknown/Unexpected response type from miner: \(String(describing: response))"))
            }

            guard
                httpResponse.statusCode == 200
            else {
                return .failure(.deviceResponseError(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)))
            }

            print("Issued restart to miner")
            return .success(true)
        } catch let error {
            return .failure(.unknownError(String(describing: error)))
        }
    }

    public func getSystemInfo() async -> Result<AxeOSDeviceInfo, Error> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system/info"))
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               httpResponse.value(forHTTPHeaderField: "Content-Type") == "application/json"
            else {
                return .failure(
                    AxeOSClientError.deviceResponseError(
                        "Request failed with response: \(String(describing: response))"
                    )
                )
            }

            return try .success(JSONDecoder().decode(AxeOSDeviceInfo.self, from: data))
        } catch let error {
            return .failure(error)
        }
    }

    public func updateSystemSettings(
        settings: MinerSettings
    ) async -> Result<Bool, AxeOSClientError> {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("/api/system"))
            request.httpMethod = "PATCH"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(settings)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unknownError("Unknown/Unexpected response type from miner: \(String(describing: response))"))
            }

            guard (200..<300).contains(http.statusCode) else {
                return .failure(.deviceResponseError(HTTPURLResponse.localizedString(forStatusCode: http.statusCode)))
            }
            return .success(true)

        } catch let error {
            return .failure(.unknownError(String(describing: error)))
        }
    }
}

/// Miner device settings returned by /api/system
public struct MinerSettings: Codable, Equatable {
    // MARK: ‑ Stratum
    let stratumURL: String?
    let fallbackStratumURL: String?
    let stratumUser: String?
    let stratumPassword: String?          // write‑only in spec — may be absent on GET
    let fallbackStratumUser: String?
    let fallbackStratumPassword: String?  // write‑only
    let stratumPort: Int?
    let fallbackStratumPort: Int?

    // MARK: ‑ Network / Wi‑Fi
    let ssid: String?
    let wifiPass: String?                 // write‑only
    let hostname: String?

    // MARK: ‑ ASIC & fan tuning
    let coreVoltage: Int?
    let frequency: Int?
    let flipscreen: Int?          // 0 | 1
    let overheatMode: Int?        // 0
    let overclockEnabled: Int?    // 0 | 1
    let invertscreen: Int?        // 0 | 1
    let invertfanpolarity: Int?   // 0 | 1
    let autofanspeed: Int?        // 0 | 1
    let fanspeed: Int?            // 0‑100 %

    // Map JSON keys that don’t follow Swift’s camelCase conventions
    enum CodingKeys: String, CodingKey {
        case stratumURL
        case fallbackStratumURL
        case stratumUser
        case stratumPassword
        case fallbackStratumUser
        case fallbackStratumPassword
        case stratumPort
        case fallbackStratumPort
        case ssid
        case wifiPass
        case hostname
        case coreVoltage
        case frequency
        case flipscreen
        case overheatMode        = "overheat_mode"
        case overclockEnabled
        case invertscreen
        case invertfanpolarity
        case autofanspeed
        case fanspeed
    }

    public init(
        stratumURL: String?,
        fallbackStratumURL: String?,
        stratumUser: String?,
        stratumPassword: String?,
        fallbackStratumUser: String?,
        fallbackStratumPassword: String?, stratumPort: Int?, fallbackStratumPort: Int?, ssid: String?, wifiPass: String?, hostname: String?, coreVoltage: Int?, frequency: Int?, flipscreen: Int?, overheatMode: Int?, overclockEnabled: Int?, invertscreen: Int?, invertfanpolarity: Int?, autofanspeed: Int?, fanspeed: Int?) {
        self.stratumURL = stratumURL
        self.fallbackStratumURL = fallbackStratumURL
        self.stratumUser = stratumUser
        self.stratumPassword = stratumPassword
        self.fallbackStratumUser = fallbackStratumUser
        self.fallbackStratumPassword = fallbackStratumPassword
        self.stratumPort = stratumPort
        self.fallbackStratumPort = fallbackStratumPort
        self.ssid = ssid
        self.wifiPass = wifiPass
        self.hostname = hostname
        self.coreVoltage = coreVoltage
        self.frequency = frequency
        self.flipscreen = flipscreen
        self.overheatMode = overheatMode
        self.overclockEnabled = overclockEnabled
        self.invertscreen = invertscreen
        self.invertfanpolarity = invertfanpolarity
        self.autofanspeed = autofanspeed
        self.fanspeed = fanspeed
    }
}

public struct StratumAccountInfo {
    let user: String
    let password: String
    let url: String
    let port: Int

    init(user: String, password: String, url: String, port: Int) {
        self.user = user
        self.password = password
        self.url = url
        self.port = port
    }
}
