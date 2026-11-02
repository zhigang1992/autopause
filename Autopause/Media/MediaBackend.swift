import Foundation

/// Something that can pause and resume one player.
///
/// Pause mode tries public backends first. `MediaRemoteBackend` is the private
/// fallback for players those cannot see (browser media). Callers must resume
/// only a backend that reported `didPause == true`.
protocol MediaBackend: AnyObject {
    var id: String { get }
    var usesPrivateAPI: Bool { get }
    func isPlaying() -> Bool
    /// Pauses only when this backend currently sees playback. Returns true when
    /// a pause command was sent for something that was playing.
    func pauseIfPlaying() -> Bool
    func resume()
}
