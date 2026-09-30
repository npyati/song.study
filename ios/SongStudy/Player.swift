import AVFoundation
import MediaPlayer

/// AVPlayer with a 30 Hz tick. Time-stretching keeps pitch at 0.75× and 0.5×.
@MainActor
final class Player: ObservableObject {
    @Published private(set) var time: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var playing = false
    @Published private(set) var rate: Float = 1

    var title = ""
    /// (time, song-seconds elapsed since the last tick, playing)
    var onTick: ((Double, Double, Bool) -> Void)?
    var onEnd: (() -> Void)?

    private let av = AVPlayer()
    private var observer: Any?
    private var endObs: NSObjectProtocol?
    private var lastWall: CFTimeInterval = 0

    init() {
        av.automaticallyWaitsToMinimizeStalling = false
        observer = av.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
        NowPlaying.shared.current = self
    }

    deinit {
        if let observer { av.removeTimeObserver(observer) }
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
    }

    func load(_ url: URL, title: String) {
        self.title = title
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        av.replaceCurrentItem(with: item)
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        endObs = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.playing = false
                self?.onEnd?()
                self?.publishNowPlaying()
            }
        }
        Task {
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite { self.duration = d.seconds }
            self.publishNowPlaying()
        }
    }

    private func tick(_ t: Double) {
        guard t.isFinite else { return }
        let now = CACurrentMediaTime()
        let dt = lastWall == 0 ? 0 : min(0.5, now - lastWall)
        lastWall = now
        time = t
        onTick?(t, playing ? dt * Double(rate) : 0, playing)
    }

    func play() {
        NowPlaying.activateSession()
        NowPlaying.shared.current = self
        if duration > 0, time >= duration - 0.05 { seek(0) }
        av.playImmediately(atRate: rate)
        playing = true
        publishNowPlaying()
    }

    func pause() {
        av.pause()
        playing = false
        publishNowPlaying()
    }

    func toggle() { playing ? pause() : play() }

    func seek(_ t: Double) {
        let c = max(0, min(t, max(0, duration - 0.05)))
        av.seek(to: CMTime(seconds: c, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        time = c
        publishNowPlaying()
    }

    func setRate(_ r: Float) {
        rate = r
        if playing { av.rate = r }
        publishNowPlaying()
    }

    func publishNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: "song.study",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(rate) : 0,
        ]
    }
}

/// Lock screen and headphone controls, routed to whichever player is current.
@MainActor
final class NowPlaying {
    static let shared = NowPlaying()
    weak var current: Player?

    static func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    func install() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in self?.current?.play(); return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.current?.pause(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in self?.current?.toggle(); return .success }
        c.skipBackwardCommand.preferredIntervals = [5]
        c.skipForwardCommand.preferredIntervals = [5]
        c.skipBackwardCommand.addTarget { [weak self] _ in
            guard let p = self?.current else { return .commandFailed }
            p.seek(p.time - 5); return .success
        }
        c.skipForwardCommand.addTarget { [weak self] _ in
            guard let p = self?.current else { return .commandFailed }
            p.seek(p.time + 5); return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let p = self?.current, let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            p.seek(e.positionTime); return .success
        }
    }
}

/// Min/max envelope for the waveform, decoded at 8 kHz mono — plenty for a picture.
enum Peaks {
    static func compute(_ url: URL, bins: Int = 900) async -> [SIMD2<Float>] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return [] }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 8000,
        ])
        guard reader.canAdd(out) else { return [] }
        reader.add(out)
        guard reader.startReading() else { return [] }
        var samples: [Int16] = []
        samples.reserveCapacity(8000 * 300)
        while let buf = out.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buf) {
            let len = CMBlockBufferGetDataLength(block)
            var chunk = [Int16](repeating: 0, count: len / 2)
            chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: $0.baseAddress!) }
            samples.append(contentsOf: chunk)
        }
        guard !samples.isEmpty else { return [] }
        let step = Double(samples.count) / Double(bins)
        return (0..<bins).map { i in
            let s = Int(Double(i) * step), e = min(samples.count, max(s + 1, Int(Double(i + 1) * step)))
            var lo: Int16 = 0, hi: Int16 = 0
            for j in s..<e { lo = min(lo, samples[j]); hi = max(hi, samples[j]) }
            return SIMD2(Float(lo) / 32768, Float(hi) / 32768)
        }
    }
}
