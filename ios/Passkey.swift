import AuthenticationServices
import Foundation

@objc(Passkey)
class Passkey: NSObject {
  var passKeyDelegate: PasskeyDelegate?;

  @objc(register:withChallenge:withDisplayName:withUserId:withSecurityKey:withResolver:withRejecter:)
  func register(_ identifier: String, challenge: String, displayName: String, userId: String, securityKey: Bool, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {
    guard let challengeData = Data.fromBase64Url(challenge) else {
        reject(PassKeyError.invalidChallenge.rawValue, PassKeyError.invalidChallenge.rawValue, nil);
        return
    }

    guard let userIdData = Data.fromBase64Url(userId) else {
        reject(PassKeyError.invalidUserId.rawValue, PassKeyError.invalidUserId.rawValue, nil);
        return
    }

    // Check if Passkeys are supported on this OS version
    if #available(iOS 15.0, *) {
      let authController: ASAuthorizationController;

      // Check if registration should proceed with a security key
      if (securityKey) {
        // Create a new registration request with security key
        let securityKeyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: identifier);
        let authRequest = securityKeyProvider.createCredentialRegistrationRequest(challenge: challengeData, displayName: displayName, name: displayName, userID: userIdData)
        authRequest.credentialParameters = [ ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier.ES256) ];
        authController = ASAuthorizationController(authorizationRequests: [authRequest]);
      } else {
        // Create a new registration request without security key
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: identifier);
        let authRequest = platformProvider.createCredentialRegistrationRequest(challenge: challengeData, name: displayName, userID: userIdData);
        authController = ASAuthorizationController(authorizationRequests: [authRequest]);
      }

      // Set up a PasskeyDelegate instance with a callback function
      self.passKeyDelegate = PasskeyDelegate { error, result in
        // Check if authorization process returned an error and throw if thats the case
        if (error != nil) {
          let passkeyError = self.handleErrorCode(error: error!);
          reject(passkeyError.rawValue, passkeyError.rawValue, nil);
          return;
        }

        // Check if the result object contains a valid registration result
        if let registrationResult = result?.registrationResult {
          // Return a NSDictionary instance with the received authorization data
          let authResponse: NSDictionary = [
            "rawAttestationObject": registrationResult.rawAttestationObject.toBase64URL(),
            "rawClientDataJSON": registrationResult.rawClientDataJSON.toBase64URL()
          ];

          let authResult: NSDictionary = [
            "credentialID": registrationResult.credentialID.toBase64URL(),
            "response": authResponse
          ]
          resolve(authResult);
        } else {
          // If result didn't contain a valid registration result throw an error
          reject(PassKeyError.requestFailed.rawValue, PassKeyError.requestFailed.rawValue, nil);
        }
      }

      if let passKeyDelegate = self.passKeyDelegate {
        // Perform the authorization request
        passKeyDelegate.performAuthForController(controller: authController);
      }
    } else {
      // If Passkeys are not supported throw an error
      reject(PassKeyError.notSupported.rawValue, PassKeyError.notSupported.rawValue, nil);
    }
  }

  @objc(authenticate:withChallenge:withSecurityKey:withCredentialId:withResolver:withRejecter:)
func authenticate(_ identifier: String, challenge: String, securityKey: Bool, credentialId: String?, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) -> Void {

  // Convert challenge to correct type
  guard let challengeData = Data.fromBase64URL(challenge) else {
    reject(PassKeyError.invalidChallenge.rawValue, PassKeyError.invalidChallenge.rawValue, nil);
    return
  }

  // Check if Passkeys are supported on this OS version
  if #available(iOS 15.0, *) {
    let authController: ASAuthorizationController;

    // Check if authentication should proceed with a security key
    if (securityKey) {
      // Create a new assertion request with security key
      let securityKeyProvider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: identifier);
      let authRequest = securityKeyProvider.createCredentialAssertionRequest(challenge: challengeData);
      authController = ASAuthorizationController(authorizationRequests: [authRequest]);
    } else {
      // Create a new assertion request without security key
      let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: identifier);
      let authRequest = platformProvider.createCredentialAssertionRequest(challenge: challengeData);
      
      // Add allowed credentials if credentialId is provided
      if let credentialId = credentialId, let credentialData = Data.fromBase64URL(credentialId) {
        authRequest.allowedCredentials = [ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: credentialData)];
      }
      
      authController = ASAuthorizationController(authorizationRequests: [authRequest]);
    }

    // Set up a PasskeyDelegate instance with a callback function
    self.passKeyDelegate = PasskeyDelegate { error, result in
      // Check if authorization process returned an error and throw if thats the case
      if (error != nil) {
        let passkeyError = self.handleErrorCode(error: error!);
        reject(passkeyError.rawValue, passkeyError.rawValue, nil);
        return;
      }
      // Check if the result object contains a valid authentication result
      if let assertionResult = result?.assertionResult {
        // Return a NSDictionary instance with the received authorization data
        let authResponse: NSDictionary = [
          "rawAuthenticatorData": assertionResult.rawAuthenticatorData.toBase64URL(),
          "rawClientDataJSON": assertionResult.rawClientDataJSON.toBase64URL(),
          "signature": assertionResult.signature.toBase64URL(),
        ];

        let authResult: NSDictionary = [
          "credentialID": assertionResult.credentialID.toBase64URL(),
          "userID": assertionResult.userID.toBase64URL(),
          "response": authResponse
        ]
        resolve(authResult);
      } else {
        // If result didn't contain a valid authentication result throw an error
        reject(PassKeyError.requestFailed.rawValue, PassKeyError.requestFailed.rawValue, nil);
      }
    }

    if let passKeyDelegate = self.passKeyDelegate {
      // Perform the authorization request
      passKeyDelegate.performAuthForController(controller: authController);
    }
  } else {
    // If Passkeys are not supported throw an error
    reject(PassKeyError.notSupported.rawValue, PassKeyError.notSupported.rawValue, nil);
  }
}

  // Handles ASAuthorization error codes
  func handleErrorCode(error: Error) -> PassKeyError {
    let errorCode = (error as NSError).code;
    switch errorCode {
      case 1001:
        return PassKeyError.cancelled;
      case 1004:
        return PassKeyError.requestFailed;
      case 4004:
        return PassKeyError.notConfigured;
      default:
        return PassKeyError.unknown;
    }
  }
}

enum PassKeyError: String, Error {
  case notSupported = "NotSupported"
  case requestFailed = "RequestFailed"
  case cancelled = "UserCancelled"
  case invalidChallenge = "InvalidChallenge" 
  case invalidUserId = "InvalidUserId"
  case notConfigured = "NotConfigured"
  case unknown = "UnknownError"
}

struct AuthRegistrationResult {
  var passkey: PassKeyRegistrationResult
  var type: PasskeyOperation
}

struct AuthAssertionResult {
  var passkey: PassKeyAssertionResult
  var type: PasskeyOperation
}

struct PassKeyResult {
  var registrationResult: PassKeyRegistrationResult?
  var assertionResult: PassKeyAssertionResult?
}

struct PassKeyRegistrationResult {
  var credentialID: Data
  var rawAttestationObject: Data
  var rawClientDataJSON: Data
}

struct PassKeyAssertionResult {
  var credentialID: Data
  var rawAuthenticatorData: Data
  var rawClientDataJSON: Data
  var signature: Data
  var userID: Data
}

enum PasskeyOperation {
  case Registration
  case Assertion
}

public extension Data {
    /// Same as ``Data(base64Encoded:)``, but adds padding automatically
    /// (if missing, instead of returning `nil`).
    static func fromBase64(_ encoded: String) -> Data? {
        // Prefixes padding-character(s) (if needed).
        var encoded = encoded
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded = encoded.padding(
                toLength: encoded.count + 4 - remainder,
                withPad: "=", startingAt: 0
            )
        }

        // Finally, decode.
        return Data(base64Encoded: encoded)
    }

    static func fromBase64URL(_ encoded: String) -> Data? {
        let base64String = base64UrlToBase64(base64Url: encoded)
        return fromBase64(base64String)
    }

    private static func base64UrlToBase64(base64Url: String) -> String {
        let base64 = base64Url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        return base64
    }
}

public extension String {
    static func fromBase64(_ encoded: String) -> String? {
        if let data = Data.fromBase64(encoded) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}

extension Data {
    func toBase64URL() -> String {
        let current = self

        var result = current.base64EncodedString()
        result = result.replacingOccurrences(of: "+", with: "-")
        result = result.replacingOccurrences(of: "/", with: "_")
        result = result.replacingOccurrences(of: "=", with: "")
        return result
    }
}
