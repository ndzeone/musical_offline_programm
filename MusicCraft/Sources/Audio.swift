import AVFoundation
import Accelerate

/// Проигрывание через AVAudioEngine: плеер → эквалайзер (басы/высокие) → лимитер → выход.
/// С эквалайзера снимается спектр для визуализации.
final class AudioEngine {
    let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 2)
    private let limiter: AVAudioUnitEffect

    private(set) var file: AVAudioFile?
    private(set) var sampleRate: Double = 44100
    private(set) var isPlaying = false
    private var startFrame: AVAudioFramePosition = 0
    private var pausedTime: Double = 0
    private var generation = 0
    var onEnded: (() -> Void)?

    // Спектр
    static let fftSize = 2048
    private let log2n = vDSP_Length(11)
    private let fftSetup: FFTSetup
    private var window = [Float](repeating: 0, count: AudioEngine.fftSize)
    private let lock = NSLock()
    private var spectrum = [Float](repeating: 0, count: AudioEngine.fftSize / 2)

    init() {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        limiter = AVAudioUnitEffect(audioComponentDescription: desc)
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))

        let low = eq.bands[0]
        low.filterType = .lowShelf; low.frequency = 100; low.gain = 0; low.bypass = false
        let high = eq.bands[1]
        high.filterType = .highShelf; high.frequency = 7000; high.gain = 0; high.bypass = false

        engine.attach(player); engine.attach(eq); engine.attach(limiter)
        engine.connect(player, to: eq, format: nil)
        engine.connect(eq, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
        installTap()

        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                               queue: .main) { [weak self] _ in self?.handleConfigChange() }
    }

    var duration: Double {
        guard let f = file else { return 0 }
        return Double(f.length) / sampleRate
    }

    var currentTime: Double {
        guard file != nil else { return 0 }
        if !isPlaying { return pausedTime }
        if let nt = player.lastRenderTime, let pt = player.playerTime(forNodeTime: nt) {
            return min(Double(startFrame + pt.sampleTime) / sampleRate, duration)
        }
        return Double(startFrame) / sampleRate
    }

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    func setEQ(bass: Float, bassFreq: Float, treble: Float) {
        eq.bands[0].gain = bass
        eq.bands[0].frequency = bassFreq
        eq.bands[1].gain = treble
        // Запас по громкости, чтобы сильные басы не перегружали звук
        eq.globalGain = -(max(0, bass) * 0.35 + max(0, treble) * 0.25)
    }

    func load(url: URL) throws -> Double {
        let f = try AVAudioFile(forReading: url)
        generation += 1
        player.stop()
        isPlaying = false
        engine.stop()
        file = f
        sampleRate = f.processingFormat.sampleRate
        let fmt = f.processingFormat
        eq.removeTap(onBus: 0)
        engine.connect(player, to: eq, format: fmt)
        engine.connect(eq, to: limiter, format: fmt)
        engine.connect(limiter, to: engine.mainMixerNode, format: fmt)
        installTap()
        engine.prepare()
        try engine.start()
        startFrame = 0
        pausedTime = 0
        schedule()
        return duration
    }

    func play() {
        guard file != nil else { return }
        if !engine.isRunning { try? engine.start() }
        player.play()
        isPlaying = true
    }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        player.pause()
        isPlaying = false
    }

    func seek(to t: Double) {
        guard let f = file else { return }
        let was = isPlaying
        generation += 1
        player.stop()
        startFrame = max(0, min(f.length - 1, AVAudioFramePosition(t * sampleRate)))
        pausedTime = Double(startFrame) / sampleRate
        schedule()
        if was { player.play() }
    }

    func unload() {
        generation += 1
        player.stop()
        isPlaying = false
        file = nil
        pausedTime = 0
    }

    func spectrumSnapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return spectrum
    }

    // MARK: - Внутреннее

    private func schedule() {
        guard let f = file else { return }
        generation += 1
        let gen = generation
        let remaining = f.length - startFrame
        guard remaining > 0 else { return }
        player.scheduleSegment(f, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil,
                               completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                self.isPlaying = false
                self.pausedTime = self.duration
                self.onEnded?()
            }
        }
    }

    private func handleConfigChange() {
        guard file != nil else { return }
        let was = isPlaying, t = currentTime
        isPlaying = false
        pausedTime = t
        try? engine.start()
        seek(to: t)
        if was { play() }
    }

    private func installTap() {
        eq.installTap(onBus: 0, bufferSize: AVAudioFrameCount(Self.fftSize), format: nil) { [weak self] buf, _ in
            self?.analyze(buf)
        }
    }

    private func analyze(_ buf: AVAudioPCMBuffer) {
        guard let ch = buf.floatChannelData else { return }
        let n = Self.fftSize
        let result = Self.computeSpectrum(channels: ch, channelCount: Int(buf.format.channelCount),
                                          frames: Int(buf.frameLength), window: window, setup: fftSetup, log2n: log2n, n: n)
        // Уровень громкости (RMS) для полосы босса
        let frames = Int(buf.frameLength), chans = Int(buf.format.channelCount)
        var sum: Float = 0
        for c in 0..<chans {
            var s: Float = 0
            vDSP_svesq(ch[c], 1, &s, vDSP_Length(frames))
            sum += s
        }
        let rms = (sum / Float(max(1, frames * chans))).squareRoot()
        let lvl = min(1, max(0, (20 * log10(rms + 1e-9) + 42) / 42))
        lock.lock(); spectrum = result; level = lvl; lock.unlock()
    }

    private var level: Float = 0

    func levelSnapshot() -> Float {
        lock.lock(); defer { lock.unlock() }
        return level
    }

    /// Возвращает n/2 значений 0…1 (логарифмическая шкала громкости).
    static func computeSpectrum(channels ch: UnsafePointer<UnsafeMutablePointer<Float>>, channelCount: Int, frames: Int,
                                window: [Float], setup: FFTSetup, log2n: vDSP_Length, n: Int) -> [Float] {
        let count = min(frames, n)
        let chans = max(1, channelCount)
        var input = [Float](repeating: 0, count: n)
        for i in 0..<count {
            var s: Float = 0
            for c in 0..<chans { s += ch[c][i] }
            input[i] = s / Float(chans) * window[i]
        }
        var real = [Float](repeating: 0, count: n / 2)
        var imag = [Float](repeating: 0, count: n / 2)
        var mags = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                input.withUnsafeBufferPointer { inp in
                    inp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(n / 2))
            }
        }
        // mags = |X|^2. Синус на полной громкости ≈ fullScaleDB.
        let floorDB: Float = fullScaleDB - 72
        return mags.map { m in
            let db = 10 * log10(m + 1e-12)
            return min(1, max(0, (db - floorDB) / (fullScaleDB - floorDB)))
        }
    }

    static var fullScaleDB: Float = 64
}
