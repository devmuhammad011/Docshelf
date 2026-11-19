import Flutter
import UIKit
import UniformTypeIdentifiers

class SceneDelegate: FlutterSceneDelegate {}

final class DocumentImporter: NSObject, FlutterSceneLifeCycleDelegate {
  private static let shared = DocumentImporter()

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.addSceneDelegate(shared)
    connect(registrar.messenger())
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts else { return false }
    return self.scene(scene, openURLContexts: contexts)
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    let files = URLContexts.map(\.url).filter(\.isFileURL)
    for file in files {
      Self.receive(file)
    }
    return !files.isEmpty
  }

  private static let queue = DispatchQueue(label: "docshelf.document-import")
  private static var pending: [[String: Any]] = []
  private static var channel: FlutterMethodChannel?

  static func connect(_ messenger: FlutterBinaryMessenger) {
    let bridge = FlutterMethodChannel(name: "docshelf/documents", binaryMessenger: messenger)
    channel = bridge
    bridge.setMethodCallHandler { call, reply in
      guard call.method == "takeDocument" else {
        reply(FlutterMethodNotImplemented)
        return
      }
      reply(pending.isEmpty ? nil : pending.removeFirst())
    }
  }

  private static func receive(_ url: URL) {
    guard url.isFileURL else { return }
    queue.async {
      let document: [String: Any]
      do {
        document = try importDocument(url)
      } catch {
        document = ["error": "Couldn’t import this file. Check that it is available and under 100 MB."]
      }
      DispatchQueue.main.async {
        pending.append(document)
        channel?.invokeMethod("documentAvailable", arguments: nil)
      }
    }
  }

  private static func importDocument(_ url: URL) throws -> [String: Any] {
    let allowed = ["pdf", "docx", "xlsx", "pptx", "txt", "csv"]
    guard allowed.contains(url.pathExtension.lowercased()) else {
      return ["error": "This document type isn’t supported."]
    }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard values.isRegularFile == true, let size = values.fileSize, size <= 100 * 1024 * 1024 else {
      throw CocoaError(.fileReadTooLarge)
    }
    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.copyItem(at: url, to: target)
    return ["name": url.lastPathComponent, "path": target.path, "size": size]
  }
}
